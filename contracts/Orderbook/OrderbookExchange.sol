// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";


contract OrderbookExchange {

	using SafeMath for uint256;
	using SignedSafeMath for int256;

	struct LimitBuyZCB {
		//same as LimitSellYT
		address maker;
		uint amount;
		uint maturityConversionRate;
		uint nextID;
	}

	struct LimitBuyYT {
		//same as LimitSellZCB
		address maker;
		uint amount;
		uint maturityConversionRate;
		uint nextID;
	}

	mapping(address => uint) public YieldDeposited;
	mapping(address => int) public BondDeposited;

	//amount of YT that is being used as collateral for a limit order
	mapping(address => uint) public lockedYT;

	mapping(uint => LimitBuyYT) public YTBuys;
	mapping(uint => LimitBuyZCB) public ZCBBuys;

	uint headYTBuyID;
	uint headZCBBuyID;

	//value of totalNumOrders at the time an order is created is its key in the order mapping
	uint totalNumOrders;

	IFixCapitalPool public FCP;
	IWrapper public wrapper;
	uint public maturity;

	constructor(address _FCPaddress) public {
		FCP = IFixCapitalPool(_FCPaddress);
		wrapper = IFixCapitalPool(_FCPaddress).wrapper();
		maturity = IFixCapitalPool(_FCPaddress).maturity();
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

	//---------------i-n-t-e-r-n-a-l---m-o-d-i-f-y---o-r-d-e-r-b-o-o-k--------------------

	function manageCollateral_BuyZCB(address _addr, uint _amount) internal {
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


	function manageCollateral_BuyYT_makeOrder(address _addr, uint _amount) internal {
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
		lockedYT[_addr] = _lockedYT.add(_amount);
	}

 	function insertFromHead_BuyZCB(uint _amount, uint _maturityConversionRate, uint _newID) internal {
		uint currentID = headZCBBuyID;
		if (currentID == 0) {
			headZCBBuyID = _newID;
			ZCBBuys[_newID] = LimitBuyZCB(msg.sender, _amount, _maturityConversionRate, 0);
			return;
		}
		LimitBuyZCB storage currentOrder = ZCBBuys[currentID];
		if (_maturityConversionRate < currentOrder.maturityConversionRate) {
			headZCBBuyID = _newID;
			ZCBBuys[_newID] = LimitBuyZCB(msg.sender, _amount, _maturityConversionRate, currentID);
			return;
		}
		LimitBuyZCB storage prevOrder; 
		currentID = currentOrder.nextID;
		while (currentID > 0) {
			prevOrder = currentOrder;
			currentOrder = ZCBBuys[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				ZCBBuys[_newID] = LimitBuyZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		ZCBBuys[_newID] = LimitBuyZCB(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function insertFromHead_BuyYT(uint _amount, uint _maturityConversionRate, uint _newID) internal {
		uint currentID = headYTBuyID;
		if (currentID == 0) {
			headYTBuyID = _newID;
			YTBuys[_newID] = LimitBuyYT(msg.sender, _amount, _maturityConversionRate, 0);
			return;
		}
		LimitBuyYT storage currentOrder = YTBuys[currentID];
		if (_maturityConversionRate > currentOrder.maturityConversionRate) {
			headYTBuyID = _newID;
			YTBuys[_newID] = LimitBuyYT(msg.sender, _amount, _maturityConversionRate, currentID);
			return;
		}
		LimitBuyYT storage prevOrder; 
		currentID = currentOrder.nextID;
		while (currentID > 0) {
			prevOrder = currentOrder;
			currentOrder = YTBuys[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				YTBuys[_newID] = LimitBuyYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		YTBuys[_newID] = LimitBuyYT(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function insertWithHint_BuyZCB(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID) internal {
		uint currentID = _hintID;
		LimitBuyZCB storage currentOrder = ZCBBuys[currentID];
		LimitBuyZCB storage prevOrder;
		require(_maturityConversionRate >= currentOrder.maturityConversionRate);
		currentID = currentOrder.nextID;
		while (currentID > 0) {
			prevOrder = currentOrder;
			currentOrder = ZCBBuys[currentID];
			if (_maturityConversionRate < currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				ZCBBuys[_newID] = LimitBuyZCB(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		ZCBBuys[_newID] = LimitBuyZCB(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function insertWithHint_BuyYT(uint _amount, uint _maturityConversionRate, uint _hintID, uint _newID) internal {
		uint currentID = _hintID;
		LimitBuyYT storage currentOrder = YTBuys[currentID];
		LimitBuyYT storage prevOrder;
		require(_maturityConversionRate <= currentOrder.maturityConversionRate);
		currentID = currentOrder.nextID;
		while (currentID > 0) {
			prevOrder = currentOrder;
			currentOrder = YTBuys[currentID];
			if (_maturityConversionRate > currentOrder.maturityConversionRate) {
				prevOrder.nextID = _newID;
				YTBuys[_newID] = LimitBuyYT(msg.sender, _amount, _maturityConversionRate, currentID);
				return;
			}
			currentID = currentOrder.nextID;
		}
		currentOrder.nextID = _newID;
		YTBuys[_newID] = LimitBuyYT(msg.sender, _amount, _maturityConversionRate, 0);
	}

	function modifyFromHead_BuyZCB(int _amount, uint _targetID, uint _maxSteps) internal returns (int change) {
		uint currentID = headZCBBuyID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = ZCBBuys[currentID].amount;
				ZCBBuys[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = ZCBBuys[currentID].amount;
				if (prevAmt <= uint(-_amount)) {
					//delete order
					headZCBBuyID = ZCBBuys[currentID].nextID;
					delete ZCBBuys[currentID];
					return -int(prevAmt);
				}
				else {
					ZCBBuys[currentID].amount = prevAmt.sub(uint(-_amount));
					return _amount;
				}
			}
		}

		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = ZCBBuys[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = ZCBBuys[currentID].amount;
			ZCBBuys[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = ZCBBuys[currentID].amount;
			if (prevAmt <= uint(-_amount)) {
				//delete order
				ZCBBuys[prevID].nextID = ZCBBuys[currentID].nextID;
				delete ZCBBuys[currentID];
				return -int(prevAmt);
			}
			else {
				ZCBBuys[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyFromHead_BuyYT(int _amount, uint _targetID, uint _maxSteps) internal returns (int change) {
		uint currentID = headYTBuyID;
		if (currentID == _targetID) {
			if (_amount > 0) {
				uint prevAmt = YTBuys[currentID].amount;
				YTBuys[currentID].amount = prevAmt.add(uint(_amount));
				return _amount;
			}
			else {
				uint prevAmt = YTBuys[currentID].amount;
				if (prevAmt <= uint(-_amount)) {
					//delete order
					headYTBuyID = YTBuys[currentID].nextID;
					delete YTBuys[currentID];
					return -int(prevAmt);
				}
				else {
					YTBuys[currentID].amount = prevAmt.sub(uint(-_amount));
					return _amount;
				}
			}
		}

		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = YTBuys[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = YTBuys[currentID].amount;
			YTBuys[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = YTBuys[currentID].amount;
			if (prevAmt <= uint(-_amount)) {
				//delete order
				YTBuys[prevID].nextID = YTBuys[currentID].nextID;
				delete YTBuys[currentID];
				return -int(prevAmt);
			}
			else {
				YTBuys[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyWithHint_BuyZCB(int _amount, uint _targetID, uint _hintID, uint _maxSteps) internal returns (int change) {
		uint currentID = _hintID;
		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = ZCBBuys[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = ZCBBuys[currentID].amount;
			ZCBBuys[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = ZCBBuys[currentID].amount;
			if (prevAmt <= uint(-_amount)) {
				//delete order
				ZCBBuys[prevID].nextID = ZCBBuys[currentID].nextID;
				delete ZCBBuys[currentID];
				return -int(prevAmt);
			}
			else {
				ZCBBuys[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	function modifyWithHint_BuyYT(int _amount, uint _targetID, uint _hintID, uint _maxSteps) internal returns (int change) {
		uint currentID = _hintID;
		uint prevID;
		for (uint i = 0; currentID != _targetID; i++) {
			require(i < _maxSteps);
			prevID = currentID;
			currentID = YTBuys[currentID].nextID;
			require(currentID != 0);
		}

		if (_amount > 0) {
			uint prevAmt = YTBuys[currentID].amount;
			YTBuys[currentID].amount = prevAmt.add(uint(_amount));
			return _amount;
		}
		else {
			uint prevAmt = YTBuys[currentID].amount;
			if (prevAmt <= uint(-_amount)) {
				//delete order
				YTBuys[prevID].nextID = YTBuys[currentID].nextID;
				delete YTBuys[currentID];
				return -int(prevAmt);
			}
			else {
				YTBuys[currentID].amount = prevAmt.sub(uint(-_amount));
				return _amount;
			}
		}
	}

	//-------------------externally-callable-------------------

	function limitBuyZCB(uint _amount, uint _maturityConversionRate, uint _hintID) public {
		uint newID = totalNumOrders+1;
		if (_hintID == 0) {
			insertFromHead_BuyZCB(_amount, _maturityConversionRate, newID);
		}
		else {
			insertWithHint_BuyZCB(_amount, _maturityConversionRate, _hintID, newID);
		}
		manageCollateral_BuyZCB(msg.sender, _amount);
		totalNumOrders = newID;
	}

	function limitBuyYT(uint _amount, uint _maturityConversionRate, uint _hintID) public {
		uint newID = totalNumOrders+1;
		if (_hintID == 0) {
			insertFromHead_BuyYT(_amount, _maturityConversionRate, newID);
		}
		else {
			insertWithHint_BuyYT(_amount, _maturityConversionRate, _hintID, newID);
		}
		manageCollateral_BuyYT(msg.sender, _amount);
		totalNumOrders = newID;
	}

	function modifyZCBLimitBuy(int _amount, uint _targetID, uint _hintID, uint _maxSteps) public {
		require(msg.sender == ZCBBuys[_targetID].maker);
		int change;
		if (_hintID == 0) {
			change = modifyFromHead_BuyZCB(_amount, _targetID, _maxSteps);
		}
		else {
			require(_targetID != headZCBBuyID);
			change = modifyWithHint_BuyZCB(_amount, _targetID, _hintID, _maxSteps);
		}
		if (change > 0) {
			manageCollateral_BuyZCB(msg.sender, uint(_amount));
		}
		else {
			manageCollateral_ReceiveZCB(msg.sender, uint(-_amount));
		}
	}

	function modifyYTLimitBuy(int _amount, uint _targetID, uint _hintID, uint _maxSteps) public {
		require(msg.sender == YTBuys[_targetID].maker);
		int change;
		if (_hintID == 0) {
			change = modifyFromHead_BuyYT(_amount, _targetID, _maxSteps);
		}
		else {
			require(_targetID != headYTBuyID);
			change = modifyWithHint_BuyYT(_amount, _targetID, _hintID, _maxSteps);
		}
		if (change > 0) {
			manageCollateral_BuyYT_makeOrder(msg.sender, uint(_amount));
		}
		else {
			manageCollateral_ReceiveYT_makeOrder(msg.sender, uint(-_amount));
		}
	}

	function marketBuyYT(uint _amountYT, uint _maxMaturityConversionRate, uint _maxIterations) public {

	}

	function marketSellYT(uint _amountYT, uint _minMaturityConversionRate, uint _maxIterations) public {

	}

	function marketBuyZCB(uint _amountZCB, uint _minMaturityConversionRate, uint _maxIterations) public {

	}

	function marketSellZCB(uint _amountZCB, uint _maxMaturityConversionRate, uint _maxIterations) public {

	}

	function takeOrderZCBtoYT_Uout(uint _amountZCB, uint _amountYT) public {

	}

	function takeOrderYTtoZCB_Uout(uint _amountZCB, uint _amountYT) public {

	}
}