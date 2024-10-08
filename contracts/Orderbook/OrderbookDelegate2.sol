// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookDelegateParent.sol";

contract OrderbookDelegate2 is OrderbookDelegateParent {

/*
	This contract cointains functions which attempt to do the impossible given the maximum stack depth allowed by the EVM
	while still attempting to be relatively gas efficient
	as a result the functions below will be tough to read, we have to do some assembly magic & such but do not be intimidated
*/

	/*
		@Description: write 4 words consecutively to memory starting at the free memory pointer
			write to memory with the intent of later returning this 4 words memory slot

		@param word0: the first word to write to memory
		@param word1: the second word to write to memory
		@param word2: the third word to write to memory
		@param word3: the fourth word to write to memory

		@return uint retPtr: return the pointer at which the first word was written
			this is the free memory pointer at beginning of execution of this function
	*/
	function prepare4WordReturn(
		uint word0,
		uint word1,
		uint word2,
		uint word3
	) internal pure returns(uint retPtr) {
		assembly {
			retPtr := mload(0x40)
			mstore(retPtr, word0)
			mstore(add(retPtr, 0x20), word1)
			mstore(add(retPtr, 0x40), word2)
			mstore(add(retPtr, 0x60), word3)
		}
	}

	/*
		@Description: sell a specific amount of ZCB on the market in order to recive U (an equal amount of ZCB & YT)

		@param uint _amountZCB: the amount of ZCB to sell
		@param uint _maxMaturityConversionRate: the maximum MCR of the head order to continue selling more ZCB
		@param uint _maxCumulativeMaturityConversionRate: if this is smaller than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketSellZCBtoU(
		uint _amountZCBInitial,
		uint _maxMaturityConversionRateInitial,
		uint _maxCumulativeMaturityConversionRateInitial,
		uint16 _maxIterationsInitial,
		bool _useInternalBalancesInitial
	) external setRateModifier {
		/*
			this function actually returns (uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount)
			but solidity poorly allocates stack space for return variables so to prevent stack too deep we must
			pretend that we aren't going to return anything then use assembly to avoid allocation
			on the stack and write directly to memory then return
		*/
		address[4] memory vitals;
		vitals[0] = address(internalWrapper);
		vitals[1] = address(internalFCP);
		vitals[2] = address(internalIORC);
		vitals[3] = IInfoOracle(vitals[2]).TreasuryFeeIsCollected() ? IInfoOracle(vitals[2]).sendTo() : Ownable(vitals[1]).owner();
		reqPriorToPayoutPhase(vitals[1]);
		claimContractSubAccountRewards(vitals[0], vitals[1]);
		uint _amountZCB = _amountZCBInitial;
		uint _maxMaturityConversionRate = _maxMaturityConversionRateInitial;
		uint _maxCumulativeMaturityConversionRate = _maxCumulativeMaturityConversionRateInitial;
		uint16 _maxIterations = _maxIterationsInitial;
		bool _useInternalBalances = _useInternalBalancesInitial;
		uint YTbought;
		uint ZCBsold;
		uint newHeadID = internalHeadYTSellID;
		LimitSellYT memory order;
		uint ratio = IWrapper(vitals[0]).WrappedAmtToUnitAmt_RoundDown(1 ether);
		/*
			to conserve stack space we must put as much as we can into i,

			least significant 2 bytes: current index
			3rd least significant byte: orderbook fee bips
			the most significant 29 bytes will store a copy of the memory address of the vitals array
		*/
		uint i = uint(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) << 16;
		assembly {
			i := or(i, shl(24, vitals))
		}
		for ( ; uint16(i) < _maxIterations && newHeadID != 0; i++) {
			order = internalYTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				if (uint16(i) != 0) {
					internalHeadYTSellID = newHeadID;
				}
				uint normalizedZCB = ZCBsold.mul(TOTAL_BASIS_POINTS).div(TOTAL_BASIS_POINTS + ((i >> 16) & 0xff));
				uint fee = ZCBsold - normalizedZCB;
				fee = fee == 0 ? 0 : fee-1;
				manageCollateral_payFee(vitals, fee, 0);
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				uint retPtr = prepare4WordReturn(YTbought, ZCBsold, newHeadID, newHeadAmount);
				assembly{return(retPtr, 0x80)}
			}
			uint unitAmtYTbought = YTbought.mul(ratio) / (1 ether);
			//double name because this variable may be overwritten and have a different use depending on the control flow, prevent stack too deep
			//this variable starts life serving the purpouse of its first name 'orderZCBamt'
			uint orderZCBamt_orderRatio = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			uint feeAdjOrderZCBamt = orderZCBamt_orderRatio.mul(TOTAL_BASIS_POINTS + ((i >> 16) & 0xff)) / TOTAL_BASIS_POINTS; //fee adjust
			uint orderUnitYTamt = order.amount.mul(ratio) / (1 ether);
			if (
				_amountZCB <= feeAdjOrderZCBamt || 
				orderUnitYTamt.add(unitAmtYTbought) >= _amountZCB - feeAdjOrderZCBamt
			) {	
				//variable takes purpouse of its second name 'orderRatio'
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
				YTtoBuy = YTtoBuy > order.amount ? order.amount : YTtoBuy; //prevent odd case

				YTbought += YTtoBuy;
				ZCBsold += ZCBtoSell;

				{
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_fillYTSell(copyVitals, order.maker, ZCBtoSell.mul(TOTAL_BASIS_POINTS) / (TOTAL_BASIS_POINTS + ((i >> 16) & 0xff)), YTtoBuy, ratio);
				}
				if (order.amount == YTtoBuy) {
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
					normalizedZCB = normalizedZCB / (((i >> 16) & 0xff) + TOTAL_BASIS_POINTS);
					uint fee = ZCBsold - normalizedZCB;
					fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_payFee(copyVitals, fee, 0);
				}
				bool copyUseInternalBalances = _useInternalBalances; // prevent stack too deep
				uint copyYTbought = YTbought; // prevent stack too deep;
				uint copyZCBsold = ZCBsold; // prevent stack too deep;
				{
					uint copyRatio = ratio; //prevent stack too deep
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_BuyYT_takeOrder(copyVitals, msg.sender, copyZCBsold, copyYTbought, copyRatio, copyUseInternalBalances);
				}
				uint copyNewHeadID = newHeadID; //prevent stack too deep
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				uint retPtr = prepare4WordReturn(copyYTbought, copyZCBsold, copyNewHeadID, newHeadAmount);
				assembly{return(retPtr, 0x80)}
			}
			else {
				{
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_fillYTSell(copyVitals, order.maker, orderZCBamt_orderRatio, order.amount, ratio);
				}
				delete internalYTSells[newHeadID];

				ZCBsold += feeAdjOrderZCBamt;
				YTbought += order.amount;
				_amountZCB -= feeAdjOrderZCBamt;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		uint normalizedZCB = ZCBsold.mul(TOTAL_BASIS_POINTS) / (((i >> 16) & 0xff) + TOTAL_BASIS_POINTS);
		uint fee = ZCBsold - normalizedZCB;
		fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
		manageCollateral_payFee(vitals, fee, 0);
		manageCollateral_BuyYT_takeOrder(vitals, msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		internalHeadYTSellID = newHeadID;
		uint newHeadAmount = newHeadID == 0 ? 0 : internalYTSells[newHeadID].amount;
		uint retPtr = prepare4WordReturn(YTbought, ZCBsold, newHeadID, newHeadAmount);
		assembly {return(retPtr, 0x80)}
	}

	/*
		@Description: sell a specific amount of YT on the market in order to receive U (an equal amount of ZCB & YT)

		@param uint _amountYT: the amount of YT to sell
		@param uint _minMaturityConversionRate: the minimum MCR of the head order to continue selling more YT
		@param uint _minCumulativeMaturityConversionRate: if this is greater than the effective MCR based on YT in and ZCB out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketSellUnitYTtoU(
		uint _unitAmountYTInitial,
		uint _minMaturityConversionRateInitial,
		uint _minCumulativeMaturityConversionRateInitial,
		uint16 _maxIterationsInitial,
		bool _useInternalBalancesInitial
	) external setRateModifier {
		/*
			this function actually returns (uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount)
			but solidity poorly allocates stack space for return variables so to prevent stack too deep we must
			pretend that we aren't going to return anything then use assembly to avoid allocation
			on the stack and write directly to memory then return
		*/
		uint16 _maxIterations = _maxIterationsInitial;
		address[4] memory vitals;
		vitals[0] = address(internalWrapper);
		vitals[1] = address(internalFCP);
		vitals[2] = address(internalIORC);
		vitals[3] = IInfoOracle(vitals[2]).TreasuryFeeIsCollected() ? IInfoOracle(vitals[2]).sendTo() : Ownable(vitals[1]).owner();
		reqPriorToPayoutPhase(vitals[1]);
		claimContractSubAccountRewards(vitals[0], vitals[1]);
		uint _unitAmountYT = _unitAmountYTInitial;
		uint _minMaturityConversionRate = _minMaturityConversionRateInitial;
		uint _minCumulativeMaturityConversionRate = _minCumulativeMaturityConversionRateInitial;
		bool _useInternalBalances = _useInternalBalancesInitial;
		uint ZCBbought;
		uint YTsold;
		uint newHeadID = internalHeadZCBSellID;
		LimitSellZCB memory order;
		uint ratio = IWrapper(vitals[0]).WrappedAmtToUnitAmt_RoundDown(1 ether);
		/*
			to conserve stack space we must put as much as we can into i,

			least significant 2 bytes: current index
			3rd least significant byte: orderbook fee bips
			the most significant 29 bytes will store a copy of the memory address of the vitals array
		*/
		uint i = uint(IInfoOracle(vitals[2]).getOrderbookFeeBips(vitals[1])) << 16;
		assembly {
			i := or(i, shl(24, vitals))
		}
		for ( ; uint16(i) < _maxIterations && newHeadID != 0; i++) {
			order = internalZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				if (uint16(i) != 0) {
					internalHeadZCBSellID = newHeadID;
				}
				uint normalizedYT = YTsold.mul(TOTAL_BASIS_POINTS).div(((i >> 16) & 0xff) + TOTAL_BASIS_POINTS);
				uint fee = YTsold - normalizedYT;
				fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
				manageCollateral_payFee(vitals, fee, ratio);
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				uint retPtr = prepare4WordReturn(ZCBbought, YTsold, newHeadID, newHeadAmount);
				assembly {return(retPtr, 0x80)}
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			uint orderFeeAdjUnitYT = (orderYTamt.mul(ratio) / (1 ether)).mul(((i >> 16) & 0xff) + TOTAL_BASIS_POINTS) / TOTAL_BASIS_POINTS;
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
				ZCBtoBuy = ZCBtoBuy > order.amount ? order.amount : ZCBtoBuy; //prevent odd case

				YTsold += YTtoSell;
				ZCBbought += ZCBtoBuy;

				{
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_fillZCBSell(copyVitals, order.maker, YTtoSell.mul(TOTAL_BASIS_POINTS) / (((i >> 16) & 0xff) + TOTAL_BASIS_POINTS), ZCBtoBuy, ratio);
				}
				if (order.amount == ZCBtoBuy) {
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
					normalizedYT = normalizedYT / (((i >> 16) & 0xff) + TOTAL_BASIS_POINTS);
					uint fee = YTsold - normalizedYT;
					fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_payFee(copyVitals, fee, ratio);
				}
				bool copyUseInternalBalances = _useInternalBalances; // prevent stack too deep
				uint copyZCBbought = ZCBbought; // prevent stack too deep
				uint copyYTsold = YTsold; // prevent stack too deep
				{
					uint copyRatio = ratio; //prevent stack too deep
					address[4] memory copyVitals;
					assembly {
						copyVitals := shr(24, i)
					}
					manageCollateral_BuyZCB_takeOrder(copyVitals, msg.sender, copyZCBbought, copyYTsold, copyRatio, copyUseInternalBalances);
				}
				uint copyNewHeadID = newHeadID; //prevent stack too deep
				uint newHeadAmount = order.amount; //copy to stack to prevent getting overwritten with later mstore opcodes
				uint retPtr = prepare4WordReturn(copyZCBbought, copyYTsold, copyNewHeadID, newHeadAmount);
				assembly {return(retPtr, 0x80)}
			}
			else {
				manageCollateral_fillZCBSell(vitals, order.maker, orderYTamt, order.amount, ratio);
				delete internalZCBSells[newHeadID];

				uint feeAdjOrderYTamt = orderYTamt.mul(((i >> 16) & 0xff) + TOTAL_BASIS_POINTS) / TOTAL_BASIS_POINTS;

				ZCBbought += order.amount;
				YTsold += feeAdjOrderYTamt;
				_unitAmountYT -= orderFeeAdjUnitYT;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		uint normalizedYT = YTsold.mul(TOTAL_BASIS_POINTS).div(((i >> 16) & 0xff) + TOTAL_BASIS_POINTS);
		uint fee = YTsold - normalizedYT;
		fee = fee == 0 ? 0 : fee - 1; //ensure no rounding errors
		manageCollateral_payFee(vitals, fee, ratio);
		manageCollateral_BuyZCB_takeOrder(vitals, msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		internalHeadZCBSellID = newHeadID;
		uint newHeadAmount = newHeadID == 0 ? 0 : internalZCBSells[newHeadID].amount;
		uint retPtr = prepare4WordReturn(ZCBbought, YTsold, newHeadID, newHeadAmount);
		assembly {return(retPtr, 0x80)}
	}

}