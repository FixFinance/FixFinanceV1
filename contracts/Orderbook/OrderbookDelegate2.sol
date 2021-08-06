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

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	//---------------i-n-t-e-r-n-a-l---m-o-d-i-f-y---o-r-d-e-r-b-o-o-k--------------------

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

	//---------------------external-------------------------------------

	function limitSellZCB(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) external ensureValidZCBSell(_amount, _maturityConversionRate) setRateModifier returns(uint prevID) {
		uint newID = totalNumOrders+1;
		if (_hintID == 0) {
			prevID = insertFromHead_SellZCB(_amount, _maturityConversionRate, newID, _maxSteps);
		}
		else {
			prevID = insertWithHint_SellZCB(_amount, _maturityConversionRate, _hintID, newID, _maxSteps);
		}
		manageCollateral_SellZCB_makeOrder(msg.sender, _amount);
		totalNumOrders = newID;
	}

	function limitSellYT(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) external ensureValidYTSell(_amount, _maturityConversionRate) setRateModifier returns(uint prevID) {
		uint newID = totalNumOrders+1;
		if (_hintID == 0) {
			prevID = insertFromHead_SellYT(_amount, _maturityConversionRate, newID, _maxSteps);
		}
		else {
			prevID = insertWithHint_SellYT(_amount, _maturityConversionRate, _hintID, newID, _maxSteps);
		}
		manageCollateral_SellYT_makeOrder(msg.sender, _amount);
		totalNumOrders = newID;
	}

	function modifyZCBLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps,
		bool _removeBelowMin
	) external setRateModifier returns(int change) {
		require(_amount != 0);
		require(msg.sender == internalZCBSells[_targetID].maker);
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
			manageCollateral_SellZCB_makeOrder(msg.sender, uint(change));
		}
		else if (change < 0) {
			manageCollateral_closeZCBSell(msg.sender, uint(-change));
		}
	}

	function modifyYTLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps,
		bool _removeBelowMin
	) external setRateModifier returns(int change) {
		require(_amount != 0);
		require(msg.sender == internalYTSells[_targetID].maker);
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
			manageCollateral_SellYT_makeOrder(msg.sender, uint(change));
		}
		else if (change < 0) {
			manageCollateral_closeYTSell(msg.sender, uint(-change));
		}
	}

	//---------------------------R-a-t-e---O-r-a-c-l-e---------------------------------

	/*
		@Description: force this contract to store a data point in its rate oracle
	*/
	function forceRateDataUpdate() external setRateModifier {}

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