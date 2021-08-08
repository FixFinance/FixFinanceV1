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

	function requireValidCollateral(uint _YD, int _BD, uint _wrappedAmtLockedYT, uint _lockedZCB, uint _ratio) internal pure {
		require(_lockedZCB <= uint(type(int256).max));
		uint unitAmtLockedYT = _wrappedAmtLockedYT.mul(_ratio)/(1 ether);
		uint minimumYieldCollateral = _YD.sub(_wrappedAmtLockedYT);
		int minimumBondCollateral = _BD.add(int(unitAmtLockedYT)).sub(int(_lockedZCB));
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

	function manageCollateral_SellZCB_makeOrder(address _addr, uint _amount, uint _ratio) internal {
		require(_amount < uint(type(int256).max));
		uint YD = internalYieldDeposited[_addr];
		int BD = internalBondDeposited[_addr];
		uint wrappedAmtLockedYT = internalLockedYT[_addr];
		uint resultantLockedZCB = internalLockedZCB[_addr].add(_amount);

		requireValidCollateral(YD, BD, wrappedAmtLockedYT, resultantLockedZCB, _ratio);

		internalLockedZCB[_addr] = resultantLockedZCB;
	}

	function manageCollateral_BuyZCB_takeOrder(
		address[3] memory vitals, // [address(internalWrapper), address(internalFCP), address(internalIORC)]
		address _addr,
		uint _amountZCB,
		uint _amountWrappedYT,
		uint _ratio,
		bool _useInternalBalances
	) internal {
		if (_useInternalBalances) {
			require(_amountWrappedYT < uint(type(int256).max));
			uint bondValChange = (_amountWrappedYT.mul(_ratio) / (1 ether)).add(_amountZCB);
			require(bondValChange <= uint(type(int256).max));

			uint YD = internalYieldDeposited[_addr];
			int BD = internalBondDeposited[_addr];
			uint wrappedAmtLockedYT = internalLockedYT[_addr];
			uint _lockedZCB = internalLockedZCB[_addr];
			int changeYield = int(_amountWrappedYT+1).mul(-1);
			IWrapper(vitals[0]).editSubAccountPosition(false, _addr, vitals[1], changeYield, int(bondValChange));
			uint resultantYD = YD.sub(_amountWrappedYT+1); //+1 to prevent off by 1 errors
			int resultantBD = BD.add(int(bondValChange));
			requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _lockedZCB, _ratio);
			internalYieldDeposited[_addr] = resultantYD;
			internalBondDeposited[_addr] = resultantBD;
		}
		else {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			IFixCapitalPool fcp = IFixCapitalPool(vitals[1]);
			//get YT
			fcp.transferPositionFrom(msg.sender, address(this), _amountWrappedYT+1, -int(unitAmtYT)); //+1 to prevent off by 1 errors
			//send ZCB
			fcp.transferPosition(msg.sender, 0, int(_amountZCB));
		}
	}

	function manageCollateral_SellYT_makeOrder(address _addr, uint _amount, uint _ratio) internal {
		require(_amount < uint(type(int256).max));
		uint YD = internalYieldDeposited[_addr];
		int BD = internalBondDeposited[_addr];
		uint resultantWrappedAmtLockedYT = internalLockedYT[_addr].add(_amount);
		uint _lockedZCB = internalLockedZCB[_addr];

		requireValidCollateral(YD, BD, resultantWrappedAmtLockedYT, _lockedZCB, _ratio);

		internalLockedYT[_addr] = resultantWrappedAmtLockedYT;
	}


	function manageCollateral_BuyYT_takeOrder(
		address[3] memory vitals, // [address(internalWrapper), address(internalFCP), address(internalIORC)]
		address _addr,
		uint _amountZCB,
		uint _amountWrappedYT,
		uint _ratio,
		bool _useInternalBalances
	) internal {
		if (_useInternalBalances) {
			require(_amountWrappedYT <= uint(type(int256).max));
			uint bondDecrease = (_amountWrappedYT.mul(_ratio) / (1 ether)).add(_amountZCB);
			require(bondDecrease <= uint(type(int256).max));
			int bondChange = -int(bondDecrease);

			uint YD = internalYieldDeposited[_addr];
			int BD = internalBondDeposited[_addr];
			uint wrappedAmtLockedYT = internalLockedYT[_addr];
			uint _lockedZCB = internalLockedZCB[_addr];
			IWrapper(vitals[0]).editSubAccountPosition(false, _addr, vitals[1], int(_amountWrappedYT), bondChange);
			uint resultantYD = YD.add(_amountWrappedYT);
			int resultantBD = BD.add(bondChange);
			requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _lockedZCB, _ratio);
			internalYieldDeposited[_addr] = resultantYD;
			internalBondDeposited[_addr] = resultantBD;
		}
		else {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			IFixCapitalPool fcp = IFixCapitalPool(vitals[1]);
			//get ZCB
			fcp.transferPositionFrom(msg.sender, address(this), 0, int(_amountZCB));
			//send YT
			fcp.transferPosition(msg.sender, _amountWrappedYT, -int(unitAmtYT));
		}
	}

	function manageCollateral_closeZCBSell(address _addr, uint _ZCBclosed) internal {
		require(_ZCBclosed < uint(type(int256).max));
		uint resultantLockedZCB = internalLockedZCB[_addr].sub(_ZCBclosed);
		internalLockedZCB[_addr] = resultantLockedZCB;
	}

	function manageCollateral_fillYTSell(
		address[3] memory vitals, // [address(internalWrapper), address(internalFCP), address(internalIORC)]
		address _addr,
		uint _ZCBreceived,
		uint _YTsold,
		uint _ratio
	) internal {
		require(_ZCBreceived <= uint(type(int256).max));
		require(_YTsold <= uint(type(int256).max));
		uint unitAmtYT = _YTsold.mul(_ratio) / (1 ether);
		int prevBD = internalBondDeposited[_addr];
		uint prevYD = internalYieldDeposited[_addr];
		uint prevWrappedAmtLockedYT = internalLockedYT[_addr];
		int changeYield = -int(_YTsold);
		int changeBond = int(unitAmtYT).add(int(_ZCBreceived));
		internalBondDeposited[_addr] = prevBD.add(changeBond);
		internalYieldDeposited[_addr] = prevYD.sub(_YTsold);
		internalLockedYT[_addr] = prevWrappedAmtLockedYT.sub(_YTsold);
		IWrapper(vitals[0]).editSubAccountPosition(false, _addr, vitals[1], changeYield, changeBond);
	}

	function manageCollateral_closeYTSell(address _addr, uint _YTclosed) internal {
		require(_YTclosed < uint(type(int256).max));
		uint prevLockedYT = internalLockedYT[_addr];
		internalLockedYT[_addr] = prevLockedYT.sub(_YTclosed);
	}

	function manageCollateral_fillZCBSell(
		address[3] memory vitals, // [address(internalWrapper), address(internalFCP), address(internalIORC)]
		address _addr,
		uint _YTreceived,
		uint _ZCBsold,
		uint _ratio
	) internal {
		require(_YTreceived <= uint(type(int256).max));
		require(_ZCBsold <= uint(type(int256).max));
		uint unitAmtYT = _YTreceived.mul(_ratio) / (1 ether);
		uint prevYD = internalYieldDeposited[_addr];
		int prevBD = internalBondDeposited[_addr];
		uint prevLockedZCB = internalLockedZCB[_addr];
		int changeBond = int(unitAmtYT).add(int(_ZCBsold)).mul(-1);
		internalYieldDeposited[_addr] = prevYD.add(_YTreceived);
		internalBondDeposited[_addr] = prevBD.add(changeBond);
		internalLockedZCB[_addr] = prevLockedZCB.sub(_ZCBsold);
		IWrapper(vitals[0]).editSubAccountPosition(false, _addr, vitals[1], int(_YTreceived), changeBond);
	}

	function manageCollateral_payFee(
		address[3] memory vitals, // [address(internalWrapper), address(internalFCP), address(internalIORC)]
		uint _amount,
		uint _ratio
	) internal {
		require(_amount <= uint(type(int256).max));
		int BR = internalBondRevenue;
		if (_ratio == 0) {
			//ratio of 0 means fee is in ZCB
			internalBondRevenue = BR.add(int(_amount));
			IWrapper(vitals[0]).editSubAccountPosition(false, internalTreasuryAddress, vitals[1], 0, int(_amount));
		}
		else {
			//the conversion below is always safe because / (1 ether) always deflates enough
			int bondAmount = -int(_amount.mul(_ratio) / (1 ether));
			uint YR = internalYieldRevenue;
			internalYieldRevenue = YR.add(_amount);
			internalBondRevenue = BR.add(bondAmount);
			IWrapper(vitals[0]).editSubAccountPosition(false, internalTreasuryAddress, vitals[1], int(_amount), bondAmount);
		}
	}

	function claimContractSubAccountRewards(address _wrapperAddress, address _fcpAddress) internal {
		IWrapper(_wrapperAddress).forceClaimSubAccountRewards(true, _fcpAddress, address(this), _fcpAddress);
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