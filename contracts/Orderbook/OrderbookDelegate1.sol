// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookData.sol";

contract OrderbookDelegate1 is OrderbookData {

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

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
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumZCBamount = minimumZCBLimitAmount(_maturityConversionRate, ratio);
		require(_amountZCB > minimumZCBamount);
		_;
	}

	modifier ensureValidYTSell(uint _amountYT, uint _maturityConversionRate) {
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
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

	function withdraw(uint _amountYield, int _amountBond) external {
		uint YD = YieldDeposited[msg.sender];
		int BD = BondDeposited[msg.sender];
		uint wrappedAmtLockedYT = lockedYT[msg.sender];
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		uint resultantYD = YD.sub(_amountYield);
		int resultantBD = BD.sub(_amountBond);

		requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, ratio);
		FCP.transferPosition(msg.sender, _amountYield, _amountBond);

		YieldDeposited[msg.sender] = resultantYD;
		BondDeposited[msg.sender] = resultantBD;
	}

	//---------------i-n-t-e-r-n-a-l---m-o-d-i-f-y---o-r-d-e-r-b-o-o-k--------------------

	function manageCollateral_SellZCB_makeOrder(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		uint YD = YieldDeposited[_addr];
		int BD = BondDeposited[_addr];
		uint wrappedAmtLockedYT = lockedYT[_addr];
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		int resultantBD = BD.sub(int(_amount));

		requireValidCollateral(YD, resultantBD, wrappedAmtLockedYT, ratio);

		BondDeposited[_addr] = resultantBD;
	}

	function manageCollateral_ReceiveZCB(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		int BD = BondDeposited[_addr];
		BondDeposited[_addr] = BD.add(int(_amount));
	}

	function manageCollateral_BuyZCB_takeOrder(address _addr, uint _amountZCB, uint _amountWrappedYT, uint _ratio, bool _useInternalBalances) internal {
		if (_useInternalBalances) {
			uint bondValChange = (_amountWrappedYT.mul(_ratio) / (1 ether)).add(_amountZCB);
			require(bondValChange < uint(type(int256).max));

			uint YD = YieldDeposited[_addr];
			uint wrappedAmtLockedYT = lockedYT[_addr];
			int BD = BondDeposited[_addr];
			uint resultantYD = YD.sub(_amountWrappedYT+1); //+1 to prevent off by 1 errors
			int resultantBD = BD.add(int(bondValChange));
			requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _ratio);
			YieldDeposited[_addr] = resultantYD;
			BondDeposited[_addr] = resultantBD;
		}
		else {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			//get YT
			FCP.transferPositionFrom(msg.sender, address(this), _amountWrappedYT+1, -int(unitAmtYT)); //+1 to prevent off by 1 errors
			//send ZCB
			FCP.transferPosition(msg.sender, 0, int(_amountZCB));
		}
	}

	function manageCollateral_SellYT_makeOrder(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		uint YD = YieldDeposited[_addr];
		int BD = BondDeposited[_addr];
		uint wrappedAmtLockedYT = lockedYT[_addr];
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);

		uint newWrappedAmtLockedYT = wrappedAmtLockedYT.add(_amount);

		requireValidCollateral(YD, BD, newWrappedAmtLockedYT, ratio);

		lockedYT[_addr] = newWrappedAmtLockedYT;
	}

	function manageCollateral_ReceiveYT_makeOrder(address _addr, uint _amount) internal {
		require(_amount < uint(type(int256).max));
		uint _lockedYT = lockedYT[_addr];
		lockedYT[_addr] = _lockedYT.sub(_amount);
	}

	function manageCollateral_ReceiveYT_fillOrder(address _addr, uint _amount, uint _ratio) internal {
		require(_amount < uint(type(int256).max));
		uint unitAmtYT = _amount.mul(_ratio) / (1 ether);
		uint YD = YieldDeposited[_addr];
		int BD = BondDeposited[_addr];
		uint resultantYD = YD.add(_amount);
		int resultantBD = BD.sub(int(unitAmtYT));
		YieldDeposited[_addr] = resultantYD;
		BondDeposited[_addr] = resultantBD;
	}

	function manageCollateral_BuyYT_takeOrder(address _addr, uint _amountZCB, uint _amountWrappedYT, uint _ratio, bool _useInternalBalances) internal {
		if (_useInternalBalances) {
			uint bondValChange = (_amountWrappedYT.mul(_ratio) / (1 ether)).add(_amountZCB);
			require(bondValChange < uint(type(int256).max));

			uint YD = YieldDeposited[_addr];
			uint wrappedAmtLockedYT = lockedYT[_addr];
			int BD = BondDeposited[_addr];
			uint resultantYD = YD.add(_amountWrappedYT);
			int resultantBD = BD.sub(int(bondValChange));
			requireValidCollateral(resultantYD, resultantBD, wrappedAmtLockedYT, _ratio);
			YieldDeposited[_addr] = resultantYD;
			BondDeposited[_addr] = resultantBD;
		}
		else {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			//get ZCB
			FCP.transferPositionFrom(msg.sender, address(this), 0, int(_amountZCB));
			//send YT
			FCP.transferPosition(msg.sender, _amountWrappedYT, -int(unitAmtYT));
		}
	}

 	function insertFromHead_SellZCB(uint _amount, uint _maturityConversionRate, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = headZCBSellID;
		if (currentID == 0) {
			headZCBSellID = _newID;
			ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
			return 0;
		}
		LimitSellZCB storage currentOrder = ZCBSells[currentID];
		if (_maturityConversionRate > currentOrder.maturityConversionRate) {
			headZCBSellID = _newID;
			ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
			return 0;
		}
		LimitSellZCB storage prevOrder; 
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = ZCBSells[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	function insertFromHead_SellYT(uint _amount, uint _maturityConversionRate, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = headYTSellID;
		if (currentID == 0) {
			headYTSellID = _newID;
			YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
			return 0;
		}
		LimitSellYT storage currentOrder = YTSells[currentID];
		if (_maturityConversionRate < currentOrder.maturityConversionRate) {
			headYTSellID = _newID;
			YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
			return 0;
		}
		LimitSellYT storage prevOrder; 
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = YTSells[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	function insertWithHint_SellZCB(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = _hintID;
		LimitSellZCB storage currentOrder = ZCBSells[currentID];
		LimitSellZCB storage prevOrder;
		uint startMCR = currentOrder.maturityConversionRate;
		require(_maturityConversionRate <= startMCR && startMCR > 0);
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = ZCBSells[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	function insertWithHint_SellYT(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID, uint _maxSteps) internal returns(uint prevID) {
		uint currentID = _hintID;
		LimitSellYT storage currentOrder = YTSells[currentID];
		LimitSellYT storage prevOrder;
		uint startMCR = currentOrder.maturityConversionRate;
		require(_maturityConversionRate >= startMCR && startMCR > 0);
		prevID = currentID;
		currentID = currentOrder.nextID;
		for (; currentID > 0; _maxSteps--) {
			require(_maxSteps > 0);
			prevOrder = currentOrder;
			currentOrder = YTSells[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return prevID;
			}
			prevID = currentID;
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
		return prevID;
	}

	function modifyFromHead_SellZCB(int _amount, uint _targetID, uint _maxSteps, uint _minimumAmount, bool _removeBelowMin) internal returns (int change) {
		uint currentID = headZCBSellID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = ZCBSells[currentID].amount;
				ZCBSells[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = ZCBSells[currentID].amount;
				if (
					prevAmt <= uint(-_amount) ||
					(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
				) {
					//delete order
					headZCBSellID = ZCBSells[currentID].nextID;
					delete ZCBSells[currentID];
					return -int(prevAmt);
				}
				else {
					if (prevAmt <= _minimumAmount) {
						return 0;
					}
					else if (prevAmt - uint(-_amount) <= _minimumAmount) {
						ZCBSells[currentID].amount = _minimumAmount;
						return int(_minimumAmount).sub(int(prevAmt));
					}
					ZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
					return _amount;
				}
			}
		}

		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = ZCBSells[currentID].nextID;
			require(currentID != 0);
		}

		uint prevAmt = ZCBSells[currentID].amount;
		if (_amount > 0) {
			ZCBSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				ZCBSells[prevID].nextID = ZCBSells[currentID].nextID;
				delete ZCBSells[currentID];
				return -int(prevAmt);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt - uint(-_amount) <= _minimumAmount) {
					ZCBSells[currentID].amount = _minimumAmount;
					return int(_minimumAmount).sub(int(prevAmt));
				}
				ZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyFromHead_SellYT(int _amount, uint _targetID, uint _maxSteps, uint _minimumAmount, bool _removeBelowMin) internal returns (int change) {
		uint currentID = headYTSellID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = YTSells[currentID].amount;
				YTSells[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = YTSells[currentID].amount;
				if (
					prevAmt <= uint(-_amount) ||
					(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
				) {
					//delete order
					headYTSellID = YTSells[currentID].nextID;
					delete YTSells[currentID];
					return -int(prevAmt);
				}
				else {
					if (prevAmt <= _minimumAmount) {
						return 0;
					}
					else if (prevAmt - uint(-_amount) <= _minimumAmount) {
						YTSells[currentID].amount = _minimumAmount;
						return int(_minimumAmount).sub(int(prevAmt));
					}
					YTSells[currentID].amount = prevAmt.sub(uint(-_amount));
					return _amount;
				}
			}
		}

		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = YTSells[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = YTSells[currentID].amount;
			YTSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = YTSells[currentID].amount;
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				YTSells[prevID].nextID = YTSells[currentID].nextID;
				delete YTSells[currentID];
				return -int(prevAmt);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt - uint(-_amount) <= _minimumAmount) {
					YTSells[currentID].amount = _minimumAmount;
					return int(_minimumAmount).sub(int(prevAmt));
				}
				YTSells[currentID].amount = prevAmt.sub(uint(-_amount));
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
			currentID = ZCBSells[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = ZCBSells[currentID].amount;
			ZCBSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = ZCBSells[currentID].amount;
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				ZCBSells[prevID].nextID = ZCBSells[currentID].nextID;
				delete ZCBSells[currentID];
				return -int(prevAmt);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt - uint(-_amount) <= _minimumAmount) {
					ZCBSells[currentID].amount = _minimumAmount;
					return int(_minimumAmount).sub(int(prevAmt));
				}
				ZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
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
			currentID = YTSells[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = YTSells[currentID].amount;
			YTSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = YTSells[currentID].amount;
			if (
				prevAmt <= uint(-_amount) ||
				(_removeBelowMin && (prevAmt - uint(-_amount) <= _minimumAmount))
			) {
				//delete order
				YTSells[prevID].nextID = YTSells[currentID].nextID;
				delete YTSells[currentID];
				return -int(prevAmt);
			}
			else {
				if (prevAmt <= _minimumAmount) {
					return 0;
				}
				else if (prevAmt - uint(-_amount) <= _minimumAmount) {
					YTSells[currentID].amount = _minimumAmount;
					return int(_minimumAmount).sub(int(prevAmt));
				}
				YTSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

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
		require(msg.sender == ZCBSells[_targetID].maker);
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumAmount = minimumZCBLimitAmount(ZCBSells[_targetID].maturityConversionRate, ratio);
		if (_hintID == 0) {
			change = modifyFromHead_SellZCB(_amount, _targetID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		else {
			require(_targetID != headZCBSellID);
			change = modifyWithHint_SellZCB(_amount, _targetID, _hintID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		if (change > 0) {
			manageCollateral_SellZCB_makeOrder(msg.sender, uint(change));
		}
		else if (change < 0) {
			manageCollateral_ReceiveZCB(msg.sender, uint(-change));
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
		require(msg.sender == YTSells[_targetID].maker);
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint minimumAmount = minimumYTlimitAmount(YTSells[_targetID].maturityConversionRate, ratio);
		if (_hintID == 0) {
			change = modifyFromHead_SellYT(_amount, _targetID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		else {
			require(_targetID != headYTSellID);
			change = modifyWithHint_SellYT(_amount, _targetID, _hintID, _maxSteps, minimumAmount, _removeBelowMin);
		}
		if (change > 0) {
			manageCollateral_SellYT_makeOrder(msg.sender, uint(change));
		}
		else if (change < 0) {
			manageCollateral_ReceiveYT_makeOrder(msg.sender, uint(-change));
		}
	}

	function marketBuyYT(
		uint _amountYT,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount) {
		newHeadID = headYTSellID;
		LimitSellYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = YTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				if (i != 0) {
					headYTSellID = newHeadID;
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

				manageCollateral_ReceiveZCB(order.maker, scaledZCBamt);
				if (order.amount == _amountYT) {
					headYTSellID = order.nextID;
					delete YTSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = YTSells[newHeadID].nextID;
				}
				else {
					newHeadAmount = order.amount - _amountYT;
					YTSells[newHeadID].amount = newHeadAmount;
					headYTSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, orderZCBamt);
				delete YTSells[newHeadID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountYT -= order.amount;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headYTSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : YTSells[newHeadID].amount;
	}

	function marketSellYT(
		uint _amountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = headZCBSellID;
		LimitSellZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = ZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				if (i != 0) {
					headZCBSellID = newHeadID;
				}
				newHeadAmount = order.amount;
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
					headZCBSellID = order.nextID;
					delete ZCBSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = ZCBSells[newHeadID].amount;
				}
				else {
					newHeadAmount = order.amount - scaledZCBamt;
					ZCBSells[newHeadID].amount = newHeadAmount;
					headZCBSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete ZCBSells[newHeadID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountYT -= orderYTamt;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headZCBSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : ZCBSells[newHeadID].amount;
	}


	function marketBuyZCB(
		uint _amountZCB,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint ZCBbought, uint YTsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = headZCBSellID;
		LimitSellZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = ZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				if (i != 0) {
					headZCBSellID = newHeadID;
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
					headZCBSellID = order.nextID;
					delete ZCBSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = ZCBSells[newHeadID].amount;
				}
				else {
					newHeadAmount = order.amount - _amountZCB;
					ZCBSells[newHeadID].amount = newHeadAmount;
					headZCBSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete ZCBSells[newHeadID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountZCB -= order.amount;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headZCBSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : ZCBSells[newHeadID].amount;
	}

	function marketSellZCB(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external setRateModifier returns(uint YTbought, uint ZCBsold, uint newHeadID, uint newHeadAmount) {

		newHeadID = headYTSellID;
		LimitSellYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = YTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				if (i != 0) {
					headYTSellID = newHeadID;
				}
				newHeadAmount = order.amount;
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (orderZCBamt >= _amountZCB) {
				uint scaledYTamt = order.amount.mul(_amountZCB);
				scaledYTamt = scaledYTamt.div(orderZCBamt); // prevent stack too deep

				ZCBsold += _amountZCB;
				YTbought += scaledYTamt;

				manageCollateral_ReceiveZCB(order.maker, _amountZCB);
				if (order.amount == scaledYTamt) {
					headYTSellID = order.nextID;
					delete YTSells[newHeadID];
					newHeadID = order.nextID;
					newHeadAmount = YTSells[newHeadID].amount;
				}
				else {
					newHeadAmount = order.amount - scaledYTamt;
					YTSells[newHeadID].amount = newHeadAmount;
					headYTSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold, newHeadID, newHeadAmount);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, orderZCBamt);
				delete YTSells[newHeadID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountZCB -= orderZCBamt;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headYTSellID = newHeadID;
		newHeadAmount = newHeadID == 0 ? 0 : YTSells[newHeadID].amount;
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
		uint newHeadID = headYTSellID;
		LimitSellYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = YTSells[newHeadID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				if (i != 0) {
					headYTSellID = newHeadID;
				}
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
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			uint orderUnitYTamt = order.amount.mul(ratio) / (1 ether);
			if (_amountZCB <= orderZCBamt || orderUnitYTamt.add(unitAmtYTbought) >= _amountZCB.sub(orderZCBamt)) {
				uint orderRatio = orderZCBamt.mul(1 ether).div(order.amount); //ratio of ZCB to YT for specific order
				/*
					unitAmtYTbought + unitYTtoBuy == _amountZCB - ZCBtoSell
					ZCBtoSell == YTtoBuy * orderRatio
					unitYTtoBuy = YTtoBuy * ratio
					unitAmtYTbought + YTtoBuy*ratio == _amountZCB - YTtoBuy*orderRatio
					YTtoBuy * (orderRatio + ratio) == _amountZCB - unitAmtYTbought
					YTtoBuy == (_amountZCB - unitAmtYTbought) / (orderRatio + ratio)
				*/
				uint copyAmountZCB = _amountZCB; //prevent stack too deep
				uint YTtoBuy = copyAmountZCB.sub(unitAmtYTbought).mul(1 ether).div(ratio.add(orderRatio));
				uint ZCBtoSell = YTtoBuy.mul(orderRatio) / (1 ether);
				YTbought += YTtoBuy;
				ZCBsold += ZCBtoSell;

				manageCollateral_ReceiveZCB(order.maker, ZCBtoSell);
				if (order.amount <= ZCBtoSell) {
					headYTSellID = order.nextID;
					delete YTSells[newHeadID];
					newHeadID = order.nextID;
					order.amount = YTSells[newHeadID].amount; //overwrite to prevent stack too deep
				}
				else {
					order.amount = order.amount - YTtoBuy; // overwrite to prevent stack too deep
					YTSells[newHeadID].amount = order.amount;
					headYTSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
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

				manageCollateral_ReceiveZCB(order.maker, order.amount);
				delete YTSells[newHeadID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountZCB -= orderZCBamt;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headYTSellID = newHeadID;
		uint newHeadAmount = newHeadID == 0 ? 0 : YTSells[newHeadID].amount;
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
		uint newHeadID = headZCBSellID;
		LimitSellZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && newHeadID != 0; i++) {
			order = ZCBSells[newHeadID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				if (i != 0) {
					headZCBSellID = newHeadID;
				}
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
			uint orderUnitAmtYT = orderYTamt.mul(ratio) / (1 ether);
			if (orderUnitAmtYT >= _unitAmountYT || ZCBbought.add(order.amount) >= _unitAmountYT.sub(orderUnitAmtYT)) {
				uint orderRatio = order.amount.mul(1 ether).div(orderUnitAmtYT); //ratio of ZCB to unit YT for specific order
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

				manageCollateral_ReceiveYT_fillOrder(order.maker, YTtoSell, ratio);
				if (order.amount <= ZCBtoBuy) {
					headZCBSellID = order.nextID;
					delete ZCBSells[newHeadID];
					newHeadID = order.nextID;
					order.amount = ZCBSells[newHeadID].amount; //overwrite to prevent stack too deep
				}
				else {
					order.amount = order.amount - ZCBtoBuy; //overwrite to prevent stack too deep
					ZCBSells[newHeadID].amount = order.amount;
					headZCBSellID = newHeadID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
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
				delete ZCBSells[newHeadID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_unitAmountYT -= orderUnitAmtYT;
			}
			newHeadID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headZCBSellID = newHeadID;
		uint newHeadAmount = newHeadID == 0 ? 0 : ZCBSells[newHeadID].amount;
		assembly {
			mstore(0, ZCBbought)
			mstore(0x20, YTsold)
			mstore(0x40, newHeadID)
			mstore(0x60, newHeadAmount)
			return(0, 0x80)
		}
	}

	//---------------------------R-a-t-e---O-r-a-c-l-e---------------------------------

	/*
		@Description: force this contract to store a data point in its rate oracle
	*/
	function forceRateDataUpdate() external setRateModifier {}

	/*
		@Description: write the next rate datapoint to storage

		@param uint8 _index: the index within the impliedRates array for which to set a value
	*/
	function internalSetOracleMCR(uint8 _index) internal {
		uint YThead = headYTSellID;
		if (YThead == 0) return;
		uint ZCBhead = headZCBSellID;
		if (ZCBhead == 0) return;

		uint ytMCR = YTSells[YThead].maturityConversionRate;
		uint zcbMCR = ZCBSells[ZCBhead].maturityConversionRate;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
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