// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookDelegateParent.sol";

contract OrderbookDelegate1 is OrderbookDelegateParent {

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	function withdraw(uint _amountYield, int _amountBond) external {
		uint YD = internalYieldDeposited[msg.sender];
		int BD = internalBondDeposited[msg.sender];
		uint wrappedAmtLockedYT = internalLockedYT[msg.sender];
		uint _lockedZCB = internalLockedZCB[msg.sender];
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		uint resultantYD = YD.sub(_amountYield);
		int resultantBD = BD.sub(_amountBond);

		requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _lockedZCB, ratio);
		internalFCP.transferPosition(msg.sender, _amountYield, _amountBond);

		internalYieldDeposited[msg.sender] = resultantYD;
		internalBondDeposited[msg.sender] = resultantBD;
	}

	function marketBuyYT(
		uint _amountYT,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount) {
		newHeadID = internalHeadYTSellID;
		LimitSellYT memory order;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = internalYTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				//account for fees
				uint ZCBfee = ZCBsold.mul(internalIORC.getOrderbookFeeBips(address(internalFCP))) / TOTAL_BASIS_POINTS;
				ZCBsold = ZCBsold.add(ZCBfee);
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(ZCBfee, 0);
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
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

				manageCollateral_ReceiveZCB_fillOrder(order.maker, scaledZCBamt);
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
				uint ZCBfee = ZCBsold.mul(internalIORC.getOrderbookFeeBips(address(internalFCP))) / TOTAL_BASIS_POINTS;
				ZCBsold = ZCBsold.add(ZCBfee);
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(ZCBfee, 0);
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveZCB_fillOrder(order.maker, orderZCBamt);
				delete internalYTSells[newHeadID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountYT -= order.amount;
			}
			newHeadID = order.nextID;
		}
		//account for fees
		uint ZCBfee = ZCBsold.mul(internalIORC.getOrderbookFeeBips(address(internalFCP))) / TOTAL_BASIS_POINTS;
		ZCBsold = ZCBsold.add(ZCBfee);
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_payFee(ZCBfee, 0);
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		internalHeadYTSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalYTSells[newHeadID].amount;
	}

	function marketSellYT(
		uint _amountYT, //deflate div (1 + fee), after execution inflate YTsold mul (1 + fee)
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = internalHeadZCBSellID;
		LimitSellZCB memory order;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint i = uint(internalIORC.getOrderbookFeeBips(address(internalFCP))) << 16; //store fee multiplier in 17th to 24th bit of i, cast i to uint16 for iteration purpouses
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
				manageCollateral_payFee(YTfee, ratio);
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (orderYTamt >= _amountYT) {
				uint scaledZCBamt = order.amount.mul(_amountYT);
				scaledZCBamt = scaledZCBamt.div(orderYTamt); // prevent stack too deep

				ZCBbought += scaledZCBamt;
				YTsold += _amountYT;

				manageCollateral_ReceiveYT_fillOrder(order.maker, _amountYT, ratio);
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
				manageCollateral_payFee(YTfee, ratio);
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
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
		manageCollateral_payFee(YTfee, ratio);
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		internalHeadZCBSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalZCBSells[newHeadID].amount;
	}


	function marketBuyZCB(
		uint _amountZCB,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = internalHeadZCBSellID;
		LimitSellZCB memory order;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = internalZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				uint YTfee = YTsold.mul(internalIORC.getOrderbookFeeBips(address(internalFCP))) / TOTAL_BASIS_POINTS;
				YTsold = YTsold.add(YTfee);
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(YTfee, ratio);
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
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

				manageCollateral_ReceiveYT_fillOrder(order.maker, scaledYTamt, ratio);
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

				uint YTfee = YTsold.mul(internalIORC.getOrderbookFeeBips(address(internalFCP))) / TOTAL_BASIS_POINTS;
				YTsold = YTsold.add(YTfee);
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_payFee(YTfee, ratio);
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete internalZCBSells[newHeadID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountZCB -= order.amount;
			}
			newHeadID = order.nextID;
		}
		uint YTfee = YTsold.mul(internalIORC.getOrderbookFeeBips(address(internalFCP))) / TOTAL_BASIS_POINTS;
		YTsold = YTsold.add(YTfee);
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_payFee(YTfee, ratio);
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		internalHeadZCBSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalZCBSells[newHeadID].amount;
	}

	function marketSellZCB(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = internalHeadYTSellID;
		LimitSellYT memory order;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint i = uint(internalIORC.getOrderbookFeeBips(address(internalFCP))) << 16; //store fee multiplier in 17th to 24th bit of i, cast i to uint16 for iteration purpouses
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
				manageCollateral_payFee(ZCBfee, 0);
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (orderZCBamt >= _amountZCB) {
				uint scaledYTamt = order.amount.mul(_amountZCB);
				scaledYTamt = scaledYTamt.div(orderZCBamt); // prevent stack too deep

				ZCBsold += _amountZCB;
				YTbought += scaledYTamt;

				manageCollateral_ReceiveZCB_fillOrder(order.maker, _amountZCB);
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
				manageCollateral_payFee(ZCBfee, 0);
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveZCB_fillOrder(order.maker, orderZCBamt);
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
		manageCollateral_payFee(ZCBfee, 0);
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		internalHeadYTSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : internalYTSells[newHeadID].amount;
	}

	function marketSellZCBtoU(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier {
		/*
			lokey this function actually returns (uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount)
			but solidity poorly allocates stack space for return variables so to prevent stack too deep we must
			pretend that we aren't going to return anything then use assembly to avoid allocation
			on the stack and write directly to memory then we return
		*/
		uint YTbought;
		uint ZCBsold;
		uint newHeadID = internalHeadYTSellID;
		LimitSellYT memory order;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint i = uint(internalIORC.getOrderbookFeeBips(address(internalFCP))) << 16; //store fee multiplier in 17th to 24th bit of i, cast i to uint16 for iteration purpouses
		for ( ; uint16(i) < _maxIterations && newHeadID != 0; i++) {
			order = internalYTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				if (uint16(i) != 0) {
					internalHeadYTSellID = newHeadID;
				}
				uint normalizedZCB = ZCBsold.mul(TOTAL_BASIS_POINTS).div(TOTAL_BASIS_POINTS + (i >> 16));
				uint fee = ZCBsold - normalizedZCB;
				fee = fee == 0 ? 0 : fee-1;
				manageCollateral_payFee(fee, 0);
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				assembly {
					mstore(0, YTbought)
					mstore(0x20, ZCBsold)
					mstore(0x40, newHeadID)
					mstore(0x60, newHeadAmount)
					return(order, 0x80)
				}
			}
			uint unitAmtYTbought = YTbought.mul(ratio) / (1 ether);
			//double name because this variable may be overwritten and have a different use depending on the control flow, prevent stack too deep
			uint orderZCBamt_orderRatio = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			uint feeAdjOrderZCBamt = orderZCBamt_orderRatio.mul(TOTAL_BASIS_POINTS + (i >> 16)) / TOTAL_BASIS_POINTS; //fee adjust
			uint orderUnitYTamt = order.amount.mul(ratio) / (1 ether);
			if (
				_amountZCB <= feeAdjOrderZCBamt || 
				orderUnitYTamt.add(unitAmtYTbought) >= _amountZCB - feeAdjOrderZCBamt
			) {	
				orderZCBamt_orderRatio = feeAdjOrderZCBamt.mul(1 ether).div(order.amount); //ratio of ZCB to YT for specific order
				/*
					unitAmtYTbought + unitYTtoBuy == _amountZCB - ZCBtoSell
					ZCBtoSell == YTtoBuy * orderRatio
					unitYTtoBuy = YTtoBuy * ratio
					unitAmtYTbought + YTtoBuy*ratio == _amountZCB - YTtoBuy*orderRatio
					YTtoBuy * (orderRatio + ratio) == _amountZCB - unitAmtYTbought
					YTtoBuy == (_amountZCB - unitAmtYTbought) / (orderRatio + ratio)
				*/
				uint copyAmountZCB = _amountZCB; //prevent stack too deep
				uint YTtoBuy = copyAmountZCB.sub(unitAmtYTbought).mul(1 ether).div(ratio.add(orderZCBamt_orderRatio));
				uint ZCBtoSell = YTtoBuy.mul(orderZCBamt_orderRatio) / (1 ether);
				YTbought += YTtoBuy;
				ZCBsold += ZCBtoSell;

				manageCollateral_ReceiveZCB_fillOrder(order.maker, ZCBtoSell.mul(TOTAL_BASIS_POINTS) / (TOTAL_BASIS_POINTS + (i >> 16)));
				if (order.amount <= ZCBtoSell) {
					internalHeadYTSellID = order.nextID;
					delete internalYTSells[newHeadID];
					newHeadID = order.nextID;
					order.amount = internalYTSells[newHeadID].amount; //overwrite to prevent stack too deep
				}
				else {
					order.amount = order.amount - YTtoBuy; // overwrite to prevent stack too deep
					internalYTSells[newHeadID].amount = order.amount;
					internalHeadYTSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				{
					uint normalizedZCB = ZCBsold.mul(TOTAL_BASIS_POINTS);
					normalizedZCB = normalizedZCB / ((i >> 16) + TOTAL_BASIS_POINTS);
					uint fee = ZCBsold - normalizedZCB;
					fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
					manageCollateral_payFee(fee, 0);
				}
				bool copyUseInternalBalances = _useInternalBalances; // prevent stack too deep
				uint copyYTbought = YTbought; // prevent stack too deep;
				uint copyZCBsold = ZCBsold; // prevent stack too deep;
				manageCollateral_BuyYT_takeOrder(msg.sender, copyZCBsold, copyYTbought, ratio, copyUseInternalBalances);
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				assembly {
					mstore(0, copyYTbought)
					mstore(0x20, copyZCBsold)
					mstore(0x40, newHeadID)
					mstore(0x60, newHeadAmount)
					return(0, 0x80)
				}
			}
			else {

				manageCollateral_ReceiveZCB_fillOrder(order.maker, orderZCBamt_orderRatio);
				delete internalYTSells[newHeadID];

				ZCBsold += feeAdjOrderZCBamt;
				YTbought += order.amount;
				_amountZCB -= feeAdjOrderZCBamt;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		uint normalizedZCB = ZCBsold.mul(TOTAL_BASIS_POINTS) / ((i >> 16) + TOTAL_BASIS_POINTS);
		uint fee = ZCBsold - normalizedZCB;
		fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
		manageCollateral_payFee(fee, 0);
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		internalHeadYTSellID = newHeadID;
		uint newHeadAmount = newHeadID == 0 ? 0 : internalYTSells[newHeadID].amount;
		assembly {
			mstore(0, YTbought)
			mstore(0x20, ZCBsold)
			mstore(0x40, newHeadID)
			mstore(0x60, newHeadAmount)
			return(0, 0x80)
		}
	}

	function marketSellUnitYTtoU(
		uint _unitAmountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier {
		/*
			lokey this function actually returns (uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount)
			but solidity poorly allocates stack space for return variables so to prevent stack too deep we must
			pretend that we aren't going to return anything then use assembly to avoid allocation
			on the stack and write directly to memory then we return
		*/
		uint ZCBbought;
		uint YTsold;
		uint newHeadID = internalHeadZCBSellID;
		LimitSellZCB memory order;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint i = uint(internalIORC.getOrderbookFeeBips(address(internalFCP))) << 16; //store fee multiplier in 17th to 24th bit of i, cast i to uint16 for iteration purpouses
		for ( ; uint16(i) < _maxIterations && newHeadID != 0; i++) {
			order = internalZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				if (uint16(i) != 0) {
					internalHeadZCBSellID = newHeadID;
				}
				uint normalizedYT = YTsold.mul(TOTAL_BASIS_POINTS).div((i >> 16) + TOTAL_BASIS_POINTS);
				uint fee = YTsold - normalizedYT;
				fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
				manageCollateral_payFee(fee, ratio);
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				assembly {
					mstore(0, ZCBbought)
					mstore(0x20, YTsold)
					mstore(0x40, newHeadID)
					mstore(0x60, newHeadAmount)
					return(0, 0x80)
				}
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			uint orderFeeAdjUnitYT = (orderYTamt.mul(ratio) / (1 ether)).mul((i >> 16) + TOTAL_BASIS_POINTS) / TOTAL_BASIS_POINTS;
			if (
				orderFeeAdjUnitYT >= _unitAmountYT ||
				ZCBbought.add(order.amount) >= _unitAmountYT - orderFeeAdjUnitYT
			) {
				uint orderRatio = order.amount.mul(1 ether).div(orderFeeAdjUnitYT); //ratio of ZCB to unit YT for specific order
				/*
					_unitAmountYT - unitYTtoSell == ZCBbought + ZCBtoBuy
					ZCBtoBuy == unitYTtoSell * orderRatio
					YTtoSell = unitYTtoSell / ratio

					_unitAmountYT - unitYTtoSell == ZCBbought + unitYTtoSell*orderRatio
					unitYTtoSell*(orderRatio + 1) == _unitAmountYT - ZCBbought
					unitYTtoSell == (_unitAmountYT - ZCBbought) / (orderRatio + 1)
				*/
				uint copyUnitAmtYT = _unitAmountYT; //prevent stack too deep
				uint unitYTtoSell = copyUnitAmtYT.sub(ZCBbought).mul(1 ether).div(orderRatio.add(1 ether));
				uint YTtoSell = unitYTtoSell.mul(1 ether).div(ratio);
				uint ZCBtoBuy = unitYTtoSell.mul(orderRatio) / (1 ether);

				YTsold += YTtoSell;
				ZCBbought += ZCBtoBuy;


				manageCollateral_ReceiveYT_fillOrder(order.maker, YTtoSell.mul(TOTAL_BASIS_POINTS) / ((i >> 16) + TOTAL_BASIS_POINTS), ratio);
				if (order.amount <= ZCBtoBuy) {
					internalHeadZCBSellID = order.nextID;
					delete internalZCBSells[newHeadID];
					newHeadID = order.nextID;
					order.amount = internalZCBSells[newHeadID].amount; //overwrite to prevent stack too deep
				}
				else {
					order.amount = order.amount - ZCBtoBuy; //overwrite to prevent stack too deep
					internalZCBSells[newHeadID].amount = order.amount;
					internalHeadZCBSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				{
					uint normalizedYT = YTsold.mul(TOTAL_BASIS_POINTS);
					normalizedYT = normalizedYT / ((i >> 16) + TOTAL_BASIS_POINTS);
					uint fee = YTsold - normalizedYT;
					fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
					manageCollateral_payFee(fee, ratio);
				}
				bool copyUseInternalBalances = _useInternalBalances; // prevent stack too deep
				uint copyZCBbought = ZCBbought; // prevent stack too deep
				uint copyYTsold = YTsold; // prevent stack too deep
				manageCollateral_BuyZCB_takeOrder(msg.sender, copyZCBbought, copyYTsold, ratio, copyUseInternalBalances);
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				assembly {
					mstore(0, copyZCBbought)
					mstore(0x20, copyYTsold)
					mstore(0x40, newHeadID)
					mstore(0x60, newHeadAmount)
					return(0, 0x80)
				}
			}
			else {
				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete internalZCBSells[newHeadID];

				uint feeAdjOrderYTamt = orderYTamt.mul((i >> 16) + TOTAL_BASIS_POINTS) / TOTAL_BASIS_POINTS;

				ZCBbought += order.amount;
				YTsold += feeAdjOrderYTamt;
				_unitAmountYT -= orderFeeAdjUnitYT;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		uint normalizedYT = YTsold.mul(TOTAL_BASIS_POINTS).div((i >> 16) + TOTAL_BASIS_POINTS);
		uint fee = YTsold - normalizedYT;
		fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
		manageCollateral_payFee(fee, ratio);
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		internalHeadZCBSellID = newHeadID;
		uint newHeadAmount = newHeadID == 0 ? 0 : internalZCBSells[newHeadID].amount;
		assembly {
			mstore(0, ZCBbought)
			mstore(0x20, YTsold)
			mstore(0x40, newHeadID)
			mstore(0x60, newHeadAmount)
			return(0, 0x80)
		}
	}
}