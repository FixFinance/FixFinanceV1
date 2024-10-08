// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../helpers/Ownable.sol";
import "./OrderbookDelegateParent.sol";

contract OrderbookDelegate1 is OrderbookDelegateParent {

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	/*
		@Description: buy a specific amount of YT off of the market

		@param uint _amountYT: the amount of YT to buy
		@param uint _maxMaturityConversionRate: the maximum MCR of the head order to continue purchasing more YT
		@param uint _maxCumulativeMaturityConversionRate: if this is smaller than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketBuyYT(
		uint _amountYT,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount) {
		newHeadID = internalHeadYTSellID;
		LimitSellYT memory order;
		address[4] memory vitals = [address(internalWrapper), address(internalFCP), address(internalIORC), address(0)];
		vitals[3] = IInfoOracle(vitals[2]).TreasuryFeeIsCollected() ? IInfoOracle(vitals[2]).sendTo() : Ownable(vitals[1]).owner();
		reqPriorToPayoutPhase(vitals[1]);
		claimContractSubAccountRewards(vitals[0], vitals[1]);
		uint ratio = IWrapper(vitals[0]).WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = internalYTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				//account for fees
				uint ZCBfee = ZCBsold.mul(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) / TOTAL_BASIS_POINTS;
				ZCBsold = ZCBsold.add(ZCBfee);
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, ZCBfee, 0);
				manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				if (i != 0) {
					internalHeadYTSellID = newHeadID;
				}
				newHeadAmount = order.amount;
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (order.amount >= _amountYT) {
				uint scaledZCBamt = orderZCBamt.mul(_amountYT);
				scaledZCBamt = scaledZCBamt/order.amount + (scaledZCBamt%order.amount == 0 ? 0 : 1);

				ZCBsold += scaledZCBamt;
				YTbought += _amountYT;

				{
					uint copyAmtYT = _amountYT; //prevent stack too deep
					manageCollateral_fillYTSell(vitals, order.maker, scaledZCBamt, copyAmtYT, ratio);
				}

				if (order.amount == _amountYT) {
					internalHeadYTSellID = order.nextID;
					delete internalYTSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = internalYTSells[newHeadID].nextID;
				}
				else {
					newHeadAmount = order.amount - _amountYT;
					internalYTSells[newHeadID].amount = newHeadAmount;
					internalHeadYTSellID = newHeadID;
				}

				//account for fees
				uint ZCBfee = ZCBsold.mul(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) / TOTAL_BASIS_POINTS;
				ZCBsold = ZCBsold.add(ZCBfee);
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, ZCBfee, 0);
				{
					bool copyUseInternalBalances = _useInternalBalances;
					manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, copyUseInternalBalances);
				}
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_fillYTSell(vitals, order.maker, orderZCBamt, order.amount, ratio);
				delete internalYTSells[newHeadID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountYT -= order.amount;
			}
			newHeadID = order.nextID;
		}
		//account for fees
		uint ZCBfee = ZCBsold.mul(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) / TOTAL_BASIS_POINTS;
		ZCBsold = ZCBsold.add(ZCBfee);
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_payFee(vitals, ZCBfee, 0);
		manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		internalHeadYTSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalYTSells[newHeadID].amount;
	}

	/*
		@Description: sell a specific amount of YT off of the market

		@param uint _amountYT: the amount of YT to sell
		@param uint _minMaturityConversionRate: the minimum MCR of the head order to continue purchasing more YT
		@param uint _minCumulativeMaturityConversionRate: if this is greater than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketSellYT(
		uint _amountYTInitial, //deflate div (1 + fee), after execution inflate YTsold mul (1 + fee)
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = internalHeadZCBSellID;
		LimitSellZCB memory order;
		address[4] memory vitals = [address(internalWrapper), address(internalFCP), address(internalIORC), address(0)];
		vitals[3] = IInfoOracle(vitals[2]).TreasuryFeeIsCollected() ? IInfoOracle(vitals[2]).sendTo() : Ownable(vitals[1]).owner();
		reqPriorToPayoutPhase(vitals[1]);
		claimContractSubAccountRewards(vitals[0], vitals[1]);
		uint ratio = IWrapper(vitals[0]).WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint i = uint(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) << 16; //store fee multiplier in 17th to 24th bit of i, cast i to uint16 for iteration purpouses
		uint _amountYT = _amountYTInitial; //prevent stack too deep
		_amountYT = _amountYT.mul(TOTAL_BASIS_POINTS).div((i >> 16) + TOTAL_BASIS_POINTS);
		for ( ; uint16(i) < _maxIterations && newHeadID != 0; i++) {
			order = internalZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				if (uint16(i) != 0) {
					internalHeadZCBSellID = newHeadID;
				}
				newHeadAmount = order.amount;

				uint YTfee = YTsold.mul(i >> 16) / TOTAL_BASIS_POINTS;
				YTsold = YTsold.add(YTfee);
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, YTfee, ratio);
				{
					bool copyUseInternalBalances = _useInternalBalances;
					manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, copyUseInternalBalances);
				}
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (orderYTamt >= _amountYT) {
				uint scaledZCBamt = order.amount.mul(_amountYT);
				scaledZCBamt = scaledZCBamt.div(orderYTamt); // prevent stack too deep

				ZCBbought += scaledZCBamt;
				YTsold += _amountYT;

				manageCollateral_fillZCBSell(vitals, order.maker, _amountYT, scaledZCBamt, ratio);
				if (order.amount == scaledZCBamt) {
					internalHeadZCBSellID = order.nextID;
					delete internalZCBSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = internalZCBSells[newHeadID].amount;
				}
				else {
					newHeadAmount = order.amount - scaledZCBamt;
					internalZCBSells[newHeadID].amount = newHeadAmount;
					internalHeadZCBSellID = newHeadID;
				}

				uint YTfee = YTsold.mul(i >> 16) / TOTAL_BASIS_POINTS;
				YTsold = YTsold.add(YTfee);

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, YTfee, ratio);
				{
					bool copyUseInternalBalances = _useInternalBalances;
					manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, copyUseInternalBalances);
				}
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_fillZCBSell(vitals, order.maker, orderYTamt, order.amount, ratio);
				delete internalZCBSells[newHeadID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountYT -= orderYTamt;
			}
			newHeadID = order.nextID;
		}
		uint YTfee = YTsold.mul(i >> 16) / TOTAL_BASIS_POINTS;
		YTsold = YTsold.add(YTfee);

		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_payFee(vitals, YTfee, ratio);
		bool copyUseInternalBalances = _useInternalBalances;
		manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, copyUseInternalBalances);
		internalHeadZCBSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalZCBSells[newHeadID].amount;
	}


	/*
		@Description: buy a specific amount of ZCB off of the market

		@param uint _amountZCB: the amount of ZCB to buy
		@param uint _minMaturityConversionRate: the minimum MCR of the head order to continue purchasing more ZCB
		@param uint _minCumulativeMaturityConversionRate: if this is greater than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketBuyZCB(
		uint _amountZCB,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = internalHeadZCBSellID;
		LimitSellZCB memory order;
		address[4] memory vitals = [address(internalWrapper), address(internalFCP), address(internalIORC), address(0)];
		vitals[3] = IInfoOracle(vitals[2]).TreasuryFeeIsCollected() ? IInfoOracle(vitals[2]).sendTo() : Ownable(vitals[1]).owner();
		reqPriorToPayoutPhase(vitals[1]);
		claimContractSubAccountRewards(vitals[0], vitals[1]);
		uint ratio = IWrapper(vitals[0]).WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = internalZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				uint YTfee = YTsold.mul(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) / TOTAL_BASIS_POINTS;
				YTsold = YTsold.add(YTfee);
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, YTfee, ratio);
				manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				if (i != 0) {
					internalHeadZCBSellID = newHeadID;
				}
				newHeadAmount = order.amount;
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (order.amount >= _amountZCB) {
				uint scaledYTamt = orderYTamt.mul(_amountZCB);
				scaledYTamt = scaledYTamt/order.amount + (scaledYTamt%order.amount == 0 ? 0 : 1);

				ZCBbought += _amountZCB;
				YTsold += scaledYTamt;

				{
					uint copyAmtZCB = _amountZCB; //prevent stack too deep
					manageCollateral_fillZCBSell(vitals, order.maker, scaledYTamt, copyAmtZCB, ratio);
				}

				if (order.amount == _amountZCB) {
					internalHeadZCBSellID = order.nextID;
					delete internalZCBSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = internalZCBSells[newHeadID].amount;
				}
				else {
					newHeadAmount = order.amount - _amountZCB;
					internalZCBSells[newHeadID].amount = newHeadAmount;
					internalHeadZCBSellID = newHeadID;
				}

				uint YTfee = YTsold.mul(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) / TOTAL_BASIS_POINTS;
				YTsold = YTsold.add(YTfee);
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, YTfee, ratio);
				{
					bool copyUseInternalBalances = _useInternalBalances;
					manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, copyUseInternalBalances);
				}
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_fillZCBSell(vitals, order.maker, orderYTamt, order.amount, ratio);
				delete internalZCBSells[newHeadID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountZCB -= order.amount;
			}
			newHeadID = order.nextID;
		}
		uint YTfee = YTsold.mul(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) / TOTAL_BASIS_POINTS;
		YTsold = YTsold.add(YTfee);
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_payFee(vitals, YTfee, ratio);
		manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		internalHeadZCBSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalZCBSells[newHeadID].amount;
	}

	/*
		@Description: sell a specific amount of ZCB on the market

		@param uint _amountZCB: the amount of ZCB to sell
		@param uint _maxMaturityConversionRate: the maximum MCR of the head order to continue selling more ZCB
		@param uint _maxCumulativeMaturityConversionRate: if this is smaller than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketSellZCB(
		uint _amountZCBInitial, //deflate div (1 + fee), after execution inflate YTsold mul (1 + fee)
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = internalHeadYTSellID;
		LimitSellYT memory order;
		address[4] memory vitals = [address(internalWrapper), address(internalFCP), address(internalIORC), address(0)];
		vitals[3] = IInfoOracle(vitals[2]).TreasuryFeeIsCollected() ? IInfoOracle(vitals[2]).sendTo() : Ownable(vitals[1]).owner();
		reqPriorToPayoutPhase(vitals[1]);
		claimContractSubAccountRewards(vitals[0], vitals[1]);
		uint ratio = IWrapper(vitals[0]).WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint i = uint(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) << 16; //store fee multiplier in 17th to 24th bit of i, cast i to uint16 for iteration purpouses
		uint _amountZCB = _amountZCBInitial; // prevent stack too deep
		_amountZCB = _amountZCB.mul(TOTAL_BASIS_POINTS).div((i >> 16) + TOTAL_BASIS_POINTS);
		for ( ; uint16(i) < _maxIterations && newHeadID != 0; i++) {
			order = internalYTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				if (uint16(i) != 0) {
					internalHeadYTSellID = newHeadID;
				}
				newHeadAmount = order.amount;
				uint ZCBfee = ZCBsold.mul(i >> 16) / TOTAL_BASIS_POINTS;
				ZCBsold = ZCBsold.add(ZCBfee);
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, ZCBfee, 0);
				{
					bool copyUseInternalBalances = _useInternalBalances;
					manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, copyUseInternalBalances);
				}
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (orderZCBamt >= _amountZCB) {
				uint scaledYTamt = order.amount.mul(_amountZCB);
				scaledYTamt = scaledYTamt.div(orderZCBamt); // prevent stack too deep

				ZCBsold += _amountZCB;
				YTbought += scaledYTamt;

				manageCollateral_fillYTSell(vitals, order.maker, _amountZCB, scaledYTamt, ratio);
				if (order.amount == scaledYTamt) {
					internalHeadYTSellID = order.nextID;
					delete internalYTSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = internalYTSells[newHeadID].amount;
				}
				else {
					newHeadAmount = order.amount - scaledYTamt;
					internalYTSells[newHeadID].amount = newHeadAmount;
					internalHeadYTSellID = newHeadID;
				}

				uint ZCBfee = ZCBsold.mul(i >> 16) / TOTAL_BASIS_POINTS;
				ZCBsold = ZCBsold.add(ZCBfee);
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(vitals, ZCBfee, 0);
				{
					bool copyUseInternalBalances = _useInternalBalances; //prevent stack too deep
					uint copyYTbought = YTbought; //prevent stack too deep
					manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, copyYTbought, ratio, copyUseInternalBalances);
				}
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_fillYTSell(vitals, order.maker, orderZCBamt, order.amount, ratio);
				delete internalYTSells[newHeadID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountZCB -= orderZCBamt;
			}
			newHeadID = order.nextID;
		}
		uint ZCBfee = ZCBsold.mul(i >> 16) / TOTAL_BASIS_POINTS;
		ZCBsold = ZCBsold.add(ZCBfee);
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_payFee(vitals, ZCBfee, 0);
		bool copyUseInternalBalances = _useInternalBalances; //prevent stack too deep
		manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, copyUseInternalBalances);
		internalHeadYTSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalYTSells[newHeadID].amount;
	}

}