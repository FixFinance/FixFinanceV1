// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookData.sol";

contract OrderbookExchange is OrderbookData {

	address delegateAddress;

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;


	modifier ensureMCRAboveCurrentRatio(uint _maturityConversionRate) {
		require(_maturityConversionRate > wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether));
		_;
	}

	constructor(address _FCPaddress, address _delegateAddress) public {
		FCP = IFixCapitalPool(_FCPaddress);
		wrapper = IFixCapitalPool(_FCPaddress).wrapper();
		maturity = IFixCapitalPool(_FCPaddress).maturity();
		delegateAddress = _delegateAddress;
	}

	function deposit(uint _amountYield, int _amountBond) public {
		FCP.transferPositionFrom(msg.sender, address(this), _amountYield, _amountBond);
		YieldDeposited[msg.sender] += _amountYield;
		BondDeposited[msg.sender] += _amountBond;
	}

	function withdraw(uint _amountYield, int _amountBond) public {
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

 	function insertFromHead_SellZCB(uint _amount, uint _maturityConversionRate, uint _newID, uint _maxSteps) internal {
		uint currentID = headZCBSellID;
		if (currentID == 0) {
			headZCBSellID = _newID;
			ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
			return;
		}
		LimitSellZCB storage currentOrder = ZCBSells[currentID];
		if (_maturityConversionRate > currentOrder.maturityConversionRate) {
			headZCBSellID = _newID;
			ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
			return;
		}
		LimitSellZCB storage prevOrder; 
		currentID = currentOrder.nextID;
		for (uint i = 0; i < _maxSteps && currentID > 0; i++) {
			prevOrder = currentOrder;
			currentOrder = ZCBSells[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function insertFromHead_SellYT(uint _amount, uint _maturityConversionRate, uint _newID, uint _maxSteps) internal {
		uint currentID = headYTSellID;
		if (currentID == 0) {
			headYTSellID = _newID;
			YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
			return;
		}
		LimitSellYT storage currentOrder = YTSells[currentID];
		if (_maturityConversionRate < currentOrder.maturityConversionRate) {
			headYTSellID = _newID;
			YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
			return;
		}
		LimitSellYT storage prevOrder; 
		currentID = currentOrder.nextID;
		for (uint i = 0; i < _maxSteps && currentID > 0; i++) {
			prevOrder = currentOrder;
			currentOrder = YTSells[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function insertWithHint_SellZCB(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID, uint _maxSteps) internal {
		uint currentID = _hintID;
		LimitSellZCB storage currentOrder = ZCBSells[currentID];
		LimitSellZCB storage prevOrder;
		uint startMCR = currentOrder.maturityConversionRate;
		require(_maturityConversionRate <= startMCR && startMCR > 0);
		currentID = currentOrder.nextID;
		for (uint i = 0; i < _maxSteps && currentID > 0; i++) {
			prevOrder = currentOrder;
			currentOrder = ZCBSells[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		ZCBSells[_newID] = LimitSellZCB(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function insertWithHint_SellYT(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID, uint _maxSteps) internal {
		uint currentID = _hintID;
		LimitSellYT storage currentOrder = YTSells[currentID];
		LimitSellYT storage prevOrder;
		uint startMCR = currentOrder.maturityConversionRate;
		require(_maturityConversionRate >= startMCR && startMCR > 0);
		currentID = currentOrder.nextID;
		for (uint i = 0; i < _maxSteps && currentID > 0; i++) {
			prevOrder = currentOrder;
			currentOrder = YTSells[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		YTSells[_newID] = LimitSellYT(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function modifyFromHead_SellZCB(int _amount, uint _targetID, uint _maxSteps) internal returns (int change) {
		uint currentID = headZCBSellID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = ZCBSells[currentID].amount;
				ZCBSells[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = ZCBSells[currentID].amount;
				if (prevAmt <= uint(-_amount)) {
					//delete order
					headZCBSellID = ZCBSells[currentID].nextID;
					delete ZCBSells[currentID];
					return -int(prevAmt);
				}
				else {
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

		if (_amount > 0) {
			uint prevAmt = ZCBSells[currentID].amount;
			ZCBSells[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = ZCBSells[currentID].amount;
			if (prevAmt <= uint(-_amount)) {
				//delete order
				ZCBSells[prevID].nextID = ZCBSells[currentID].nextID;
				delete ZCBSells[currentID];
				return -int(prevAmt);
			}
			else {
				ZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyFromHead_SellYT(int _amount, uint _targetID, uint _maxSteps) internal returns (int change) {
		uint currentID = headYTSellID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = YTSells[currentID].amount;
				YTSells[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = YTSells[currentID].amount;
				if (prevAmt <= uint(-_amount)) {
					//delete order
					headYTSellID = YTSells[currentID].nextID;
					delete YTSells[currentID];
					return -int(prevAmt);
				}
				else {
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
			if (prevAmt <= uint(-_amount)) {
				//delete order
				YTSells[prevID].nextID = YTSells[currentID].nextID;
				delete YTSells[currentID];
				return -int(prevAmt);
			}
			else {
				YTSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyWithHint_SellZCB(int _amount, uint _targetID, uint _hintID, uint _maxSteps) internal returns (int change) {
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
			if (prevAmt <= uint(-_amount)) {
				//delete order
				ZCBSells[prevID].nextID = ZCBSells[currentID].nextID;
				delete ZCBSells[currentID];
				return -int(prevAmt);
			}
			else {
				ZCBSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyWithHint_SellYT(int _amount, uint _targetID, uint _hintID, uint _maxSteps) internal returns (int change) {
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
			if (prevAmt <= uint(-_amount)) {
				//delete order
				YTSells[prevID].nextID = YTSells[currentID].nextID;
				delete YTSells[currentID];
				return -int(prevAmt);
			}
			else {
				YTSells[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	//-------------------externally-callable-------------------

	function limitSellZCB(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) public ensureMCRAboveCurrentRatio(_maturityConversionRate) {
		uint newID = totalNumOrders+1;
		if (_hintID == 0) {
			insertFromHead_SellZCB(_amount, _maturityConversionRate, newID, _maxSteps);
		}
		else {
			insertWithHint_SellZCB(_amount, _maturityConversionRate, _hintID, newID, _maxSteps);
		}
		manageCollateral_SellZCB_makeOrder(msg.sender, _amount);
		totalNumOrders = newID;
	}

	function limitSellYT(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) public ensureMCRAboveCurrentRatio(_maturityConversionRate) {
		uint newID = totalNumOrders+1;
		if (_hintID == 0) {
			insertFromHead_SellYT(_amount, _maturityConversionRate, newID, _maxSteps);
		}
		else {
			insertWithHint_SellYT(_amount, _maturityConversionRate, _hintID, newID, _maxSteps);
		}
		manageCollateral_SellYT_makeOrder(msg.sender, _amount);
		totalNumOrders = newID;
	}

	function modifyZCBLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps
	) public returns(int change) {
		require(msg.sender == ZCBSells[_targetID].maker);
		if (_hintID == 0) {
			change = modifyFromHead_SellZCB(_amount, _targetID, _maxSteps);
		}
		else {
			require(_targetID != headZCBSellID);
			change = modifyWithHint_SellZCB(_amount, _targetID, _hintID, _maxSteps);
		}
		if (change > 0) {
			manageCollateral_SellZCB_makeOrder(msg.sender, uint(change));
		}
		else {
			manageCollateral_ReceiveZCB(msg.sender, uint(-change));
		}
	}

	function modifyYTLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps
	) public returns(int change) {
		require(msg.sender == YTSells[_targetID].maker);
		if (_hintID == 0) {
			change = modifyFromHead_SellYT(_amount, _targetID, _maxSteps);
		}
		else {
			require(_targetID != headYTSellID);
			change = modifyWithHint_SellYT(_amount, _targetID, _hintID, _maxSteps);
		}
		if (change > 0) {
			manageCollateral_SellYT_makeOrder(msg.sender, uint(change));
		}
		else {
			manageCollateral_ReceiveYT_makeOrder(msg.sender, uint(-change));
		}
	}

	function marketBuyYT(
		uint _amountYT,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint YTbought, uint ZCBsold) {

		uint currentID = headYTSellID;
		LimitSellYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = YTSells[currentID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
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
					delete YTSells[currentID];
				}
				else {
					YTSells[currentID].amount = order.amount - _amountYT;
					headYTSellID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, orderZCBamt);
				delete YTSells[currentID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountYT -= order.amount;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headYTSellID = currentID;
	}

	function marketSellYT(
		uint _amountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint ZCBbought, uint YTsold) {

		uint currentID = headZCBSellID;
		LimitSellZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = ZCBSells[currentID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (orderYTamt >= _amountYT) {
				uint scaledZCBamt = order.amount.mul(_amountYT).div(orderYTamt);

				ZCBbought += scaledZCBamt;
				YTsold += _amountYT;

				manageCollateral_ReceiveYT_fillOrder(order.maker, _amountYT, ratio);
				if (order.amount == scaledZCBamt) {
					headZCBSellID = order.nextID;
					delete ZCBSells[currentID];
				}
				else {
					ZCBSells[currentID].amount = order.amount - scaledZCBamt;
					headZCBSellID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete ZCBSells[currentID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountYT -= orderYTamt;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headZCBSellID = currentID;
	}


	function marketBuyZCB(
		uint _amountZCB,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint ZCBbought, uint YTsold) {

		uint currentID = headZCBSellID;
		LimitSellZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = ZCBSells[currentID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
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
					delete ZCBSells[currentID];
				}
				else {
					ZCBSells[currentID].amount = order.amount - _amountZCB;
					headZCBSellID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete ZCBSells[currentID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_amountZCB -= order.amount;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headZCBSellID = currentID;
	}

	function marketSellZCB(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint YTbought, uint ZCBsold) {

		uint currentID = headYTSellID;
		LimitSellYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = YTSells[currentID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (orderZCBamt >= _amountZCB) {
				uint scaledYTamt = order.amount.mul(_amountZCB).div(orderZCBamt);

				ZCBsold += _amountZCB;
				YTbought += scaledYTamt;

				manageCollateral_ReceiveZCB(order.maker, _amountZCB);
				if (order.amount == scaledYTamt) {
					headYTSellID = order.nextID;
					delete YTSells[currentID];
				}
				else {
					YTSells[currentID].amount = order.amount - scaledYTamt;
					headYTSellID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, orderZCBamt);
				delete YTSells[currentID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountZCB -= orderZCBamt;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headYTSellID = currentID;
	}

	function marketSellZCBtoU(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint YTbought, uint ZCBsold) {

		uint currentID = headYTSellID;
		LimitSellYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = YTSells[currentID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
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
					delete YTSells[currentID];
				}
				else {
					YTSells[currentID].amount = order.amount - YTtoBuy;
					headYTSellID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				bool copyUseInternalBalances = _useInternalBalances; // prevent stack too deep
				uint copyYTbought = YTbought; // prevent stack too deep;
				uint copyZCBsold = ZCBsold; // prevent stack too deep;
				manageCollateral_BuyYT_takeOrder(msg.sender, copyZCBsold, copyYTbought, ratio, copyUseInternalBalances);
				return (copyYTbought, copyZCBsold);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, order.amount);
				delete YTSells[currentID];

				ZCBsold += orderZCBamt;
				YTbought += order.amount;
				_amountZCB -= orderZCBamt;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headYTSellID = currentID;
	}

	function marketSellUnitYTtoU(
		uint _unitAmountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint ZCBbought, uint YTsold) {

		uint currentID = headZCBSellID;
		LimitSellZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = ZCBSells[currentID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
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
					delete ZCBSells[currentID];
				}
				else {
					ZCBSells[currentID].amount = order.amount - ZCBtoBuy;
					headZCBSellID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				bool copyUseInternalBalances = _useInternalBalances; // prevent stack too deep
				uint copyZCBbought = ZCBbought; // prevent stack too deep
				uint copyYTsold = YTsold; // prevent stack too deep
				manageCollateral_BuyZCB_takeOrder(msg.sender, copyZCBbought, copyYTsold, ratio, copyUseInternalBalances);
				return (copyZCBbought, copyYTsold);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, orderYTamt, ratio);
				delete ZCBSells[currentID];

				ZCBbought += order.amount;
				YTsold += orderYTamt;
				_unitAmountYT -= orderUnitAmtYT;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headZCBSellID = currentID;
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
		impliedMCRs[impliedMCR] = impliedMCR;
		timestamps[_index] = block.timestamp;
		if (_index+1 == LENGTH_RATE_SERIES) {
			CanSetOracleMCR = true;
			toSet = 0;
		}
		else {
			toSet++;
		}
	}

	/*
		@Description: if enough time has elapsed automatically update the rate data in the oracle
	*/
	modifier setRateModifier() {
		uint8 _toSet = toSet;
		uint8 mostRecent = (LENGTH_RATE_SERIES-1+_toSet)%LENGTH_RATE_SERIES;
		if (block.timestamp >= timestamps[mostRecent] + TIME_BETWEEN_DATAPOINTS) internalSetOracleMCR(_toSet);
		_;
	}

	/*
		@Description: returns the implied yield from the rate offered in this amm between now and maturity

		@return uint yieldToMaturity: the multiplier by which the market anticipates the conversionRate to increase by up to maturity
	*/
	function impliedYieldToMaturity() external view returns (uint yieldToMaturity) {
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint _oracleMCR = OracleMCR;
		return ratio < _oracleMCR ? _oracleMCR.mul(1 ether).div(ratio) : (1 ether);
	}

	/*
		@Description: set the median of all datapoints in the impliedRates array as the
			oracle rate, may only be called after all datapoints have been updated since
			last call to this function

		@param uint _MCR: the median of all MCR datapoints
	*/
	function setOracleMCR(uint _MCR) external {
		require(CanSetOracleMCR);

		uint8 numLarger;
		uint8 numEqual;
		for (uint8 i = 0; i < LENGTH_RATE_SERIES; i++) {
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
		CanSetOracleMCR = false;
		toSet = 0;
	}

	/*
		@Description: get the implied APY of this amm

		@return int128 APY: the implied APY of this amm in ABDK64.64 format
	*/
	function getAPYFromOracle() external view returns (int128 APY) {
		uint _oracleMCR = OracleMCR;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		if (ratio >= _oracleMCR) {
			return ABDK_1;
		}
		/*
			APY**yearsRemaining == MCR / ratio
			APY == (MCR / ratio)**(1/yearsRemaining)
			APY == exp2 ( log 2 ( (MCR/ratio)**(1/yearsRemaining) ))
			APY == exp2 ( (1/yearsRemaining) * log 2 (MCR/ratio))
		*/
		int128 yearsRemaining = int128((maturity.sub(wrapper.lastUpdate()) << 64) / SecondsPerYear);
		uint base = _oracleMCR.mul(1 << 64).div(ratio);
		require(base <= uint(type(int128).max));
		int128 exp = ABDK_1.div(yearsRemaining);
		APY = BigMath.Pow(int128(base), exp);
	}

	/*
		@Description: get all rate datapoints and the timestamps at which they were recorded
	*/
	function getImpliedRateData() external view returns (
		uint[LENGTH_RATE_SERIES] memory _impliedMCRs,
		uint[LENGTH_RATE_SERIES] memory _timestamps
	) {
		_impliedMCRs = impliedMCRs;
		_timestamps = timestamps;
	}

}