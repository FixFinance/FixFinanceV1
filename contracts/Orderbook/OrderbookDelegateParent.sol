// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookData.sol";

contract OrderbookDelegateParent is OrderbookData {

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	uint internal constant TOTAL_BASIS_POINTS = 10_000;

	function minimumZCBLimitAmount(uint _maturityConversionRate, uint _ratio) internal view returns(uint minimum) {
		uint yieldToMaturity = _maturityConversionRate.mul(1 ether).div(_ratio);
		require(yieldToMaturity > 1 ether);
		/*
			U * NPVu == Z * NPVzcb0
			NPVu == 1
			NPVzcb == 1/yieldToMaturity
			U == Z * NPVzcb
			Z == U / NPVzcb
			Z == U * yieldToMaturity
		*/
		minimum = minimumOrderSize.mul(yieldToMaturity).div(1 ether);
	}

	function minimumYTlimitAmount(uint _maturityConversionRate, uint _ratio) internal view returns(uint minimum) {
		uint zcbDilutionToMatutity = _ratio.mul(1 ether).div(_maturityConversionRate);
		require(zcbDilutionToMatutity < 1 ether);
		/*
			U * NPVu == YT * NPVyt
			NPVu == 1
			NPVyt == (1 - zcbDilutiontoMatutity) * ratio
			U == YT * NPVyt
			YT == U / NPVyt
			YT == U / ((1 - zcbDilutiontoMatutity) * ratio)
		*/
		minimum = minimumOrderSize.mul(1 ether)
			.div(uint(1 ether).sub(zcbDilutionToMatutity).mul(_ratio) / (1 ether));
	}

	modifier ensureValidZCBSell(uint _amountZCB, uint _maturityConversionRate) {
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumZCBamount = minimumZCBLimitAmount(_maturityConversionRate, ratio);
		require(_amountZCB > minimumZCBamount);
		_;
	}

	modifier ensureValidYTSell(uint _amountYT, uint _maturityConversionRate) {
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumYTamount = minimumYTlimitAmount(_maturityConversionRate, ratio);
		require(_amountYT > minimumYTamount);
		_;
	}

	function requireValidCollateral(uint _YD, int _BD, uint _wrappedAmtLockedYT, uint _ratio) internal pure {
		uint unitAmtLockedYT = _wrappedAmtLockedYT.mul(_ratio)/(1 ether);
		uint minimumYieldCollateral = _YD.sub(_wrappedAmtLockedYT);
		int minimumBondCollateral = _BD.add(int(unitAmtLockedYT));
		require(minimumBondCollateral >= 0 || minimumYieldCollateral.mul(_ratio)/(1 ether) >= uint(-minimumBondCollateral));
	}

	function impliedMaturityConversionRate(uint _ZCB, uint _YT, uint _ratio) internal pure returns(uint) {
		uint effYT = _YT.mul(_ratio) / (1 ether);
		return (_ZCB.mul(1 ether) / effYT).add(1 ether).mul(_ratio) / (1 ether);
	}

	function impliedZCBamount(uint _YT, uint _ratio, uint _maturityConversionRate) internal pure returns(uint) {
		uint yieldToMaturity = _maturityConversionRate.mul(1 ether).div(_ratio);
		//ensure that for YTsell orders that yieldToMaturity is always positive
		yieldToMaturity = yieldToMaturity > (1 ether) ? yieldToMaturity : (1 ether) + 1;
		uint effYT = _YT.mul(_ratio) / (1 ether);
		return effYT.mul(yieldToMaturity.sub(1 ether)) / (1 ether);
	}

	function impliedYTamount(uint _ZCB, uint _ratio, uint _maturityConversionRate) internal pure returns(uint) {
		uint yieldToMaturity = _maturityConversionRate.mul(1 ether).div(_ratio);
		uint effYT = _ZCB.mul(1 ether).div(yieldToMaturity.sub(1 ether));
		return effYT.mul(1 ether).div(_ratio);
	}

	//---------------i-n-t-e-r-n-a-l---m-o-d-i-f-y---o-r-d-e-r-b-o-o-k--------------------

	function manageCollateral_SellZCB_makeOrder(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		uint YD = internalYieldDeposited[_addr];
		int BD = internalBondDeposited[_addr];
		uint wrappedAmtLockedYT = internalLockedYT[_addr];
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		int resultantBD = BD.sub(int(_amount));

		requireValidCollateral(YD, resultantBD, wrappedAmtLockedYT, ratio);

		internalBondDeposited[_addr] = resultantBD;
	}

	function manageCollateral_ReceiveZCB(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		int BD = internalBondDeposited[_addr];
		internalBondDeposited[_addr] = BD.add(int(_amount));
	}

	function manageCollateral_BuyZCB_takeOrder(address _addr, uint _amountZCB, uint _amountWrappedYT, uint _ratio, bool _useInternalBalances) internal {
		if (_useInternalBalances) {
			uint bondValChange = (_amountWrappedYT.mul(_ratio) / (1 ether)).add(_amountZCB);
			require(bondValChange < uint(type(int256).max));

			uint YD = internalYieldDeposited[_addr];
			uint wrappedAmtLockedYT = internalLockedYT[_addr];
			int BD = internalBondDeposited[_addr];
			uint resultantYD = YD.sub(_amountWrappedYT+1); //+1 to prevent off by 1 errors
			int resultantBD = BD.add(int(bondValChange));
			requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _ratio);
			internalYieldDeposited[_addr] = resultantYD;
			internalBondDeposited[_addr] = resultantBD;
		}
		else {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			//get YT
			internalFCP.transferPositionFrom(msg.sender, address(this), _amountWrappedYT+1, -int(unitAmtYT)); //+1 to prevent off by 1 errors
			//send ZCB
			internalFCP.transferPosition(msg.sender, 0, int(_amountZCB));
		}
	}

	function manageCollateral_SellYT_makeOrder(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		uint YD = internalYieldDeposited[_addr];
		int BD = internalBondDeposited[_addr];
		uint wrappedAmtLockedYT = internalLockedYT[_addr];
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		uint newWrappedAmtLockedYT = wrappedAmtLockedYT.add(_amount);

		requireValidCollateral(YD, BD, newWrappedAmtLockedYT, ratio);

		internalLockedYT[_addr] = newWrappedAmtLockedYT;
	}

	function manageCollateral_ReceiveYT_makeOrder(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		uint _internalLockedYT = internalLockedYT[_addr];
		internalLockedYT[_addr] = _internalLockedYT.sub(_amount);
	}

	function manageCollateral_ReceiveYT_fillOrder(address _addr, uint _amount, uint _ratio) internal {
		require(_amount < uint(type(int256).max));
		uint unitAmtYT = _amount.mul(_ratio) / (1 ether);
		uint YD = internalYieldDeposited[_addr];
		int BD = internalBondDeposited[_addr];
		uint resultantYD = YD.add(_amount);
		int resultantBD = BD.sub(int(unitAmtYT));
		internalYieldDeposited[_addr] = resultantYD;
		internalBondDeposited[_addr] = resultantBD;
	}

	function manageCollateral_BuyYT_takeOrder(
		address _addr,
		uint _amountZCB,
		uint _amountWrappedYT,
		uint _ratio,
		bool _useInternalBalances
	) internal {
		if (_useInternalBalances) {
			uint bondValChange = (_amountWrappedYT.mul(_ratio) / (1 ether)).add(_amountZCB);
			require(bondValChange < uint(type(int256).max));

			uint YD = internalYieldDeposited[_addr];
			uint wrappedAmtLockedYT = internalLockedYT[_addr];
			int BD = internalBondDeposited[_addr];
			uint resultantYD = YD.add(_amountWrappedYT);
			int resultantBD = BD.sub(int(bondValChange));
			requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _ratio);
			internalYieldDeposited[_addr] = resultantYD;
			internalBondDeposited[_addr] = resultantBD;
		}
		else {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			//get ZCB
			internalFCP.transferPositionFrom(msg.sender, address(this), 0, int(_amountZCB));
			//send YT
			internalFCP.transferPosition(msg.sender, _amountWrappedYT, -int(unitAmtYT));
		}
	}

	function manageCollateral_payFee(uint _amount, uint _ratio) internal {
		int BR = internalBondRevenue;
		if (_ratio == 0) {
			//ratio of 0 means fee is in ZCB
			require(_amount <= uint(type(int256).max));
			internalBondRevenue = BR.add(int(_amount));
		}
		else {
			//the conversion below is always safe because / (1 ether) always deflates enough
			int bondAmount = int(_amount.mul(_ratio) / (1 ether));
			uint YR = internalYieldRevenue;
			internalYieldRevenue = YR.add(_amount);
			internalBondRevenue = BR.sub(bondAmount);
		}
	}

	//---------------------------R-a-t-e---O-r-a-c-l-e---------------------------------

	/*
		@Description: write the next rate datapoint to storage

		@param uint8 _index: the index within the impliedRates array for which to set a value
	*/
	function internalSetOracleMCR(uint8 _index) internal {
		uint YThead = internalHeadYTSellID;
		if (YThead == 0) return;
		uint ZCBhead = internalHeadZCBSellID;
		if (ZCBhead == 0) return;

		uint ytMCR = internalYTSells[YThead].maturityConversionRate;
		uint zcbMCR = internalZCBSells[ZCBhead].maturityConversionRate;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		ytMCR = ytMCR < ratio ? ratio : ytMCR;
		zcbMCR = zcbMCR < ratio ? ratio : zcbMCR;
		//take average, not as good as geometric mean scaled with ratio as 1.0, though this is more computationally efficient
		uint impliedMCR = ytMCR.add(zcbMCR) >> 1;
		impliedMCRs[_index] = impliedMCR;
		lastDatapointCollection = uint40(block.timestamp);
		toSet = (_index+1) % LENGTH_RATE_SERIES;
	}

	/*
		@Description: if enough time has elapsed automatically update the rate data in the oracle
	*/
	modifier setRateModifier() {
		if (block.timestamp > lastDatapointCollection + TIME_BETWEEN_DATAPOINTS) internalSetOracleMCR(toSet);
		_;
	}

}