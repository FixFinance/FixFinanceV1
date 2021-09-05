// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookDelegateParent.sol";

contract OrderbookDelegate3 is OrderbookDelegateParent {

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	/*
		@Description: withdraw ZCB & YT from the orderbook, pass a yiel and bond amount

		@param uint _amountYield: the yield amount of the ZCB YT position to withdraw
		@param int _amountBond: the bond amount of the ZCB YT position to withdraw
	*/
	function withdraw(uint _amountYield, int _amountBond) external {
		require(_amountYield <= uint(type(int256).max));
		IFixCapitalPool fcp = internalFCP;
		bool inPayoutPhase = fcp.inPayoutPhase();
		uint YD = internalYieldDeposited[msg.sender];
		int BD = internalBondDeposited[msg.sender];
		uint wrappedAmtLockedYT = inPayoutPhase ? 0 : internalLockedYT[msg.sender];
		uint _lockedZCB = inPayoutPhase ? 0 : internalLockedZCB[msg.sender];
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		uint resultantYD = YD.sub(_amountYield);
		int resultantBD = BD.sub(_amountBond);

		requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _lockedZCB, ratio);
		fcp.transferPosition(msg.sender, _amountYield, _amountBond);
		int yieldChange = -int(_amountYield);
		int bondChange = _amountBond.mul(-1);
		internalWrapper.editSubAccountPosition(false, msg.sender, address(fcp), yieldChange, bondChange);

		internalYieldDeposited[msg.sender] = resultantYD;
		internalBondDeposited[msg.sender] = resultantBD;
	}

	/*
		@Description: deposit ZCB & YT into the orderbook, pass a yield and bond amount

		@param uint _amountYield: the yield amount of the ZCB YT position to deposit
		@param int _amoutBond: the bond amount of the ZCB YT position to deposit
	*/
	function deposit(uint _amountYield, int _amountBond) external {
		require(_amountYield <= uint(type(int256).max));
		IFixCapitalPool fcp = internalFCP; //gas savings
		reqPriorToPayoutPhase(address(fcp));
		fcp.transferPositionFrom(msg.sender, address(this), _amountYield, _amountBond);
		internalWrapper.editSubAccountPosition(false, msg.sender, address(fcp), int(_amountYield), _amountBond);
		internalYieldDeposited[msg.sender] = internalYieldDeposited[msg.sender].add(_amountYield);
		internalBondDeposited[msg.sender] = internalBondDeposited[msg.sender].add(_amountBond);
	}

	/*
		@Description: force claim sub account rewards where distribution account is the orderbook and sub acct is msg.sender
	*/
	function forceClaimSubAccountRewards() external {
		IFixCapitalPool fcp = internalFCP;
		IWrapper wrp = internalWrapper;
		wrp.forceClaimSubAccountRewards(true, address(fcp), address(this), address(fcp));
		wrp.forceClaimSubAccountRewards(false, address(this), msg.sender, address(fcp));
	}

	//---------------i-n-t-e-r-n-a-l---m-o-d-i-f-y---o-r-d-e-r-b-o-o-k--------------------

	/*
		@Description: add a ZCB limit sell order to the linked list

		@param uint _amount: the amount of ZCB to sell in the order
		@param uint _maturityConversionRate: the MCR of the limit sell
		@param uint _newID: the ID of the new order
		@param uint _maxSteps: the maximum iterations to find the correct insertion point
			if _maxSteps is exceeded the tx will revert

		@return uint prevID: the ID of the order directly previous to the new order,
			if the new order is the head this value will return 0
	*/
 	function insertFromHead_SellZCB(uint _amount, uint _maturityConversionRate, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = internalHeadZCBSellID;
		if (currentID == 0) {
			internalHeadZCBSellID = _newID;
			internalZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
			return 0;
		}
		LimitSellZCB storage currentOrder = internalZCBSells[currentID];
		if (_maturityConversionRate > currentOrder.maturityConversionRate) {
			internalHeadZCBSellID = _newID;
			internalZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
			return 0;
		}
		LimitSellZCB storage prevOrder; 
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = internalZCBSells[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				internalZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		internalZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	/*
		@Description: add a YT limit sell order to the linked list

		@param uint _amount: the amount of YT to sell in the order
		@param uint _maturityConversionRate: the MCR of the limit sell
		@param uint _newID: the ID of the new order
		@param uint _maxSteps: the maximum iterations to find the correct insertion point
			if _maxSteps is exceeded the tx will revert

		@return uint prevID: the ID of the order directly previous to the new order,
			if the new order is the head this value will return 0
	*/
	function insertFromHead_SellYT(uint _amount, uint _maturityConversionRate, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = internalHeadYTSellID;
		if (currentID == 0) {
			internalHeadYTSellID = _newID;
			internalYTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
			return 0;
		}
		LimitSellYT storage currentOrder = internalYTSells[currentID];
		if (_maturityConversionRate < currentOrder.maturityConversionRate) {
			internalHeadYTSellID = _newID;
			internalYTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
			return 0;
		}
		LimitSellYT storage prevOrder; 
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = internalYTSells[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				internalYTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		internalYTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	/*
		@Description: add a ZCB limit sell to the linked list, start search for insertion point with hint

		@param uint _amount: the amount of ZCB to sell in the order
		@param uint _maturityConversionRate: the MCR of the limit sell
		@param uint _hintID: ID of an order that is known to be previous to and near the target insertion point, helps gas efficiency
		@param uint _newID: the ID of the new order
		@param uint _maxSteps: the maximum iterations to find the correct insertion point
			if _maxSteps is exceeded the tx will revert

		@return uint prevID: the ID of the order directly previous to the new order,
	*/
	function insertWithHint_SellZCB(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = _hintID;
		LimitSellZCB storage currentOrder = internalZCBSells[currentID];
		LimitSellZCB storage prevOrder;
		uint startMCR = currentOrder.maturityConversionRate;
		require(_maturityConversionRate <= startMCR && startMCR > 0);
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = internalZCBSells[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				internalZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		internalZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	/*
		@Description: add a YT limit sell to the linked list, start search for insertion point with hint

		@param uint _amount: the amount of YT to sell in the order
		@param uint _maturityConversionRate: the MCR of the limit sell
		@param uint _hintID: ID of an order that is known to be previous to and near the target insertion point, helps gas efficiency
		@param uint _newID: the ID of the new order
		@param uint _maxSteps: the maximum iterations to find the correct insertion point
			if _maxSteps is exceeded the tx will revert

		@return uint prevID: the ID of the order directly previous to the new order,
			if the new order is the head this value will return 0
	*/
	function insertWithHint_SellYT(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = _hintID;
		LimitSellYT storage currentOrder = internalYTSells[currentID];
		LimitSellYT storage prevOrder;
		uint startMCR = currentOrder.maturityConversionRate;
		require(_maturityConversionRate >= startMCR && startMCR > 0);
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = internalYTSells[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				internalYTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		internalYTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	/*
		@Description: modify a ZCB limit sell order start searching for it from the head

		@param int _amount: the amount by which to change the order amount
		@param uint _targetID: the ID of the order to edit
		@param uint _maxSteps: the maximum iterations to find the correct insertion point, if _maxSteps is exceeded the tx will revert
		@param uint _minimumAmount: the minimum amount for a ZCB sell order
		@param bool _removeBelowMin: if true is passed the order will be entirely cancelled if the resulting change
			in order amount results in the order amount being below the minimum amount

		@return int change: the resultant change in the order amount from prior to after execution of this function
	*/
	function modifyFromHead_SellZCB(int _amount, uint _targetID, uint _maxSteps, uint _minimumAmount, bool _removeBelowMin) internal returns (int change) {
		uint currentID = internalHeadZCBSellID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = internalZCBSells[currentID].amount;
				internalZCBSells[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = internalZCBSells[currentID].amount;
				if (
					prevAmt <= uint(-_amount) ||
					(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
				) {
					//delete order
					internalHeadZCBSellID = internalZCBSells[currentID].nextID;
					delete internalZCBSells[currentID];
					return -int(prevAmt);
				}
				else {
					if (prevAmt <= _minimumAmount) {
						return 0;
					}
					else if (prevAmt - uint(-_amount) <= _minimumAmount) {
						internalZCBSells[currentID].amount = _minimumAmount;
						return int(_minimumAmount).sub(int(prevAmt));
					}
					internalZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
					return _amount;
				}
			}
		}

		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = internalZCBSells[currentID].nextID;
			require(currentID != 0);
		}

		uint prevAmt = internalZCBSells[currentID].amount;
		if (_amount > 0) {
			internalZCBSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				require(prevID != 0); //prevID must be found in order to delete order
				internalZCBSells[prevID].nextID = internalZCBSells[currentID].nextID;
				delete internalZCBSells[currentID];
				return -int(prevAmt);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt - uint(-_amount) <= _minimumAmount) {
					internalZCBSells[currentID].amount = _minimumAmount;
					return int(_minimumAmount).sub(int(prevAmt));
				}
				internalZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	/*
		@Description: modify a YT limit sell order start searching for it from the head

		@param int _amount: the amount by which to change the order amount
		@param uint _targetID: the ID of the order to edit
		@param uint _maxSteps: the maximum iterations to find the correct insertion point, if _maxSteps is exceeded the tx will revert
		@param uint _minimumAmount: the minimum amount for a YT sell order
		@param bool _removeBelowMin: if true is passed the order will be entirely cancelled if the resulting change
			in order amount results in the order amount being below the minimum amount

		@return int change: the resultant change in the order amount from prior to after execution of this function
	*/
	function modifyFromHead_SellYT(int _amount, uint _targetID, uint _maxSteps, uint _minimumAmount, bool _removeBelowMin) internal returns (int change) {
		uint currentID = internalHeadYTSellID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = internalYTSells[currentID].amount;
				internalYTSells[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = internalYTSells[currentID].amount;
				if (
					prevAmt <= uint(-_amount) ||
					(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
				) {
					//delete order
					internalHeadYTSellID = internalYTSells[currentID].nextID;
					delete internalYTSells[currentID];
					return -int(prevAmt);
				}
				else {
					if (prevAmt <= _minimumAmount) {
						return 0;
					}
					else if (prevAmt - uint(-_amount) <= _minimumAmount) {
						internalYTSells[currentID].amount = _minimumAmount;
						return int(_minimumAmount).sub(int(prevAmt));
					}
					internalYTSells[currentID].amount = prevAmt.sub(uint(-_amount));
					return _amount;
				}
			}
		}

		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = internalYTSells[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = internalYTSells[currentID].amount;
			internalYTSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = internalYTSells[currentID].amount;
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				require(prevID != 0); //prevID must be found in order to delete order
				internalYTSells[prevID].nextID = internalYTSells[currentID].nextID;
				delete internalYTSells[currentID];
				return -int(prevAmt);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt - uint(-_amount) <= _minimumAmount) {
					internalYTSells[currentID].amount = _minimumAmount;
					return int(_minimumAmount).sub(int(prevAmt));
				}
				internalYTSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	/*
		@Description: modify a ZCB limit sell order start searching for it from a hint ID

		@param int _amount: the amount by which to change the order amount
		@param uint _targetID: the ID of the order to edit
		@praam uint _hintID: the ID that will act as a hint to find the order previous to the target order
		@param uint _maxSteps: the maximum iterations to find the correct insertion point, if _maxSteps is exceeded the tx will revert
		@param uint _minimumAmount: the minimum amount for a ZCB sell order
		@param bool _removeBelowMin: if true is passed the order will be entirely cancelled if the resulting change
			in order amount results in the order amount being below the minimum amount

		@return int change: the resultant change in the order amount from prior to after execution of this function
	*/
	function modifyWithHint_SellZCB(int _amount, uint _targetID, uint _hintID, uint _maxSteps, uint _minimumAmount, bool _removeBelowMin) internal returns (int change) {
		uint currentID = _hintID;
		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = internalZCBSells[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = internalZCBSells[currentID].amount;
			internalZCBSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = internalZCBSells[currentID].amount;
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				require(prevID != 0); //prevID must be found in order to delete order
				internalZCBSells[prevID].nextID = internalZCBSells[currentID].nextID;
				delete internalZCBSells[currentID];
				return prevAmt.toInt().mul(-1);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				//prevAmt - uint(-_amount) <= _minimumAmount
				//prevAmt <= _minimumAmount + uint(-_amount)
				else if (prevAmt <= _minimumAmount.add(_amount.mul(-1).toUint())) {
					internalZCBSells[currentID].amount = _minimumAmount;
					return _minimumAmount.toInt().sub(prevAmt.toInt());
				}
				internalZCBSells[currentID].amount = prevAmt.sub(_amount.mul(-1).toUint());
				return _amount;
			}
		}
	}

	/*
		@Description: modify a YT limit sell order start searching for it from a hint ID

		@param int _amount: the amount by which to change the order amount
		@param uint _targetID: the ID of the order to edit
		@praam uint _hintID: the ID that will act as a hint to find the order previous to the target order
		@param uint _maxSteps: the maximum iterations to find the correct insertion point, if _maxSteps is exceeded the tx will revert
		@param uint _minimumAmount: the minimum amount for a YT sell order
		@param bool _removeBelowMin: if true is passed the order will be entirely cancelled if the resulting change
			in order amount results in the order amount being below the minimum amount

		@return int change: the resultant change in the order amount from prior to after execution of this function
	*/
	function modifyWithHint_SellYT(int _amount, uint _targetID, uint _hintID, uint _maxSteps, uint _minimumAmount, bool _removeBelowMin) internal returns (int change) {
		uint currentID = _hintID;
		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = internalYTSells[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = internalYTSells[currentID].amount;
			internalYTSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = internalYTSells[currentID].amount;
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				require(prevID != 0); //prevID must be found in order to delete order
				internalYTSells[prevID].nextID = internalYTSells[currentID].nextID;
				delete internalYTSells[currentID];
				return prevAmt.toInt().mul(-1);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt <= _minimumAmount.add(_amount.mul(-1).toUint())) {
					internalYTSells[currentID].amount = _minimumAmount;
					return _minimumAmount.toInt().sub(prevAmt.toInt());
				}
				internalYTSells[currentID].amount = prevAmt.sub((-_amount).toUint());
				return _amount;
			}
		}
	}

	//---------------------external-------------------------------------

	/*
		@Description: post a limit order to sell a specific amount of ZCB at a specific MCR

		@param uint _amount: the amount of ZCB to sell
		@param uint _maturityConversionRate: the MCR at which to sell the ZCB
		@param uint _hintID: the ID that will act as a hint for where to place the order, helps save gas
		@param uint _maxSteps: the maximum iterations to find the correct insertion point
			if _maxSteps is exceeded the tx will revert
	*/
	function limitSellZCB(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) external ensureValidZCBSell(_amount, _maturityConversionRate) setRateModifier returns(uint newID, uint prevID) {
		reqPriorToPayoutPhase(address(internalFCP));
		newID = totalNumOrders+1;
		if (_hintID == 0) {
			prevID = insertFromHead_SellZCB(_amount, _maturityConversionRate, newID, _maxSteps);
		}
		else {
			prevID = insertWithHint_SellZCB(_amount, _maturityConversionRate, _hintID, newID, _maxSteps);
		}
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		manageCollateral_SellZCB_makeOrder(msg.sender, _amount, ratio);
		totalNumOrders = newID;
	}

	/*
		@Description: post a limit order to sell a specific amount of static YT at a specific MCR

		@param uint _amount: the amount of YT to sell
		@param uint _maturityConversionRate: the MCR at which to sell the YT
		@param uint _hintID: the ID that will act as a hint for where to place the order, helps save gas
		@param uint _maxSteps: the maximum iterations to find the correct insertion point
			if _maxSteps is exceeded the tx will revert
	*/
	function limitSellYT(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) external ensureValidYTSell(_amount, _maturityConversionRate) setRateModifier returns(uint newID, uint prevID) {
		reqPriorToPayoutPhase(address(internalFCP));
		newID = totalNumOrders+1;
		if (_hintID == 0) {
			prevID = insertFromHead_SellYT(_amount, _maturityConversionRate, newID, _maxSteps);
		}
		else {
			prevID = insertWithHint_SellYT(_amount, _maturityConversionRate, _hintID, newID, _maxSteps);
		}
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		manageCollateral_SellYT_makeOrder(msg.sender, _amount, ratio);
		totalNumOrders = newID;
	}

	/*
		@Description: modify the amount in a ZCB limit sell order, msg.sender must be order maker

		@param int _amount: the amount by which to change the order amount
		@param uint _targetID: the ID of the order to edit
		@praam uint _hintID: the ID that will act as a hint to find the order previous to the target order
		@param uint _maxSteps: the maximum iterations to find the order previous to target order
		@param bool _removeBelowMin: if true is passed the order will be entirely cancelled if the resulting change
			in order amount results in the order amount being below the minimum amount
	*/
	function modifyZCBLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps,
		bool _removeBelowMin
	) external setRateModifier returns(int change) {
		require(_amount != 0);
		require(msg.sender == internalZCBSells[_targetID].maker);
		reqPriorToPayoutPhase(address(internalFCP));
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumAmount = minimumZCBLimitAmount(internalZCBSells[_targetID].maturityConversionRate, ratio);
		if (_hintID == 0) {
			change = modifyFromHead_SellZCB(_amount, _targetID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		else {
			require(_targetID != internalHeadZCBSellID);
			change = modifyWithHint_SellZCB(_amount, _targetID, _hintID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		if (change > 0) {
			manageCollateral_SellZCB_makeOrder(msg.sender, uint(change), ratio);
		}
		else if (change < 0) {
			manageCollateral_closeZCBSell(msg.sender, uint(-change));
		}
	}

	/*
		@Description: modify the amount in a YT limit sell order, msg.sender must be order maker

		@param int _amount: the amount by which to change the order amount
		@param uint _targetID: the ID of the order to edit
		@praam uint _hintID: the ID that will act as a hint to find the order previous to the target order
		@param uint _maxSteps: the maximum iterations to find the order previous to target order
		@param bool _removeBelowMin: if true is passed the order will be entirely cancelled if the resulting change
			in order amount results in the order amount being below the minimum amount
	*/
	function modifyYTLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps,
		bool _removeBelowMin
	) external setRateModifier returns(int change) {
		require(_amount != 0);
		require(msg.sender == internalYTSells[_targetID].maker);
		reqPriorToPayoutPhase(address(internalFCP));
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumAmount = minimumYTlimitAmount(internalYTSells[_targetID].maturityConversionRate, ratio);
		if (_hintID == 0) {
			change = modifyFromHead_SellYT(_amount, _targetID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		else {
			require(_targetID != internalHeadYTSellID);
			change = modifyWithHint_SellYT(_amount, _targetID, _hintID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		if (change > 0) {
			manageCollateral_SellYT_makeOrder(msg.sender, uint(change), ratio);
		}
		else if (change < 0) {
			manageCollateral_closeYTSell(msg.sender, uint(-change));
		}
	}

	//---------------------------R-a-t-e---O-r-a-c-l-e---------------------------------

	/*
		@Description: force this contract to store a data point in its rate oracle
	*/
	function forceRateDataUpdate() external setRateModifier {reqPriorToPayoutPhase(address(internalFCP));}

	/*
		@Description: set the median of all datapoints in the impliedRates array as the
			oracle rate, may only be called after all datapoints have been updated since
			last call to this function

		@param uint _MCR: the median of all MCR datapoints
	*/
	function setOracleMCR(uint _MCR) external {
		uint8 numLarger;
		uint8 numEqual;
		{
			uint lastMCR = impliedMCRs[LENGTH_RATE_SERIES-1];
			require(lastMCR > 0); //ensure the entire array has been filled with datapoints
			if (lastMCR > _MCR) {
				numLarger++;
			}
			else if (lastMCR == _MCR) {
				numEqual++;
			}
		}
		for (uint8 i = 0; i < LENGTH_RATE_SERIES-1; i++) {
			uint MCRi = impliedMCRs[i];
			if (MCRi > _MCR) {
				numLarger++;
			}
			else if (MCRi == _MCR) {
				numEqual++;
			}
		}
		uint8 numSmaller = LENGTH_RATE_SERIES - numEqual - numLarger;
		require(numLarger+numEqual >= numSmaller);
		require(numSmaller+numEqual >= numLarger);

		OracleMCR = _MCR;
	}
}