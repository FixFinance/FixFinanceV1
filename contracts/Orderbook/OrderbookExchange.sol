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

	function impliedMaturityConversionRate(uint _ZCB, uint _YT, uint _ratio) internal pure returns(uint) {
		uint effYT = _YT.mul(_ratio) / (1 ether);
		return (_ZCB.mul(1 ether) / effYT).add(1 ether).mul(_ratio) / (1 ether);
	}

	function impliedZCBamount(uint _YT, uint _ratio, uint _maturityConversionRate) internal pure returns(uint) {
		uint yieldToMaturity = _maturityConversionRate.mul(1 ether).div(_ratio);
		uint effYT = _YT.mul(_ratio) / (1 ether);
		return effYT.mul(yieldToMaturity.sub(1 ether)) / (1 ether);
	}

	function impliedYTamount(uint _ZCB, uint _ratio, uint _maturityConversionRate) internal pure returns(uint) {
		uint yieldToMaturity = _maturityConversionRate.mul(1 ether).div(_ratio);
		uint effYT = _ZCB.mul(1 ether).div(yieldToMaturity.sub(1 ether));
		return effYT.mul(1 ether).div(_ratio);
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

	function manageCollateral_BuyZCB_takeOrder(address _addr, uint _amountZCB, uint _amountWrappedYT, uint _ratio, bool _useInternalBalances) internal {
		if (_useInternalBalances) {
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			//get YT
			FCP.transferPositionFrom(msg.sender, address(this), _amountWrappedYT+1, -int(unitAmtYT)); //+1 to prevent off by 1 errors
			//send ZCB
			FCP.transferPosition(msg.sender, 0, int(_amountZCB));
		}
		else {
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
			require(_amountZCB < uint(type(int256).max));
			uint unitAmtYT = _amountWrappedYT.mul(_ratio) / (1 ether);
			//get ZCB
			FCP.transferPositionFrom(msg.sender, address(this), 0, int(_amountZCB));
			//send YT
			FCP.transferPosition(msg.sender, _amountWrappedYT, -int(unitAmtYT));
		}
		else {
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
		manageCollateral_BuyYT_makeOrder(msg.sender, _amount);
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

	function marketBuyYT(
		uint _amountYT,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint YTbought, uint ZCBsold) {

		uint currentID = headZCBBuyID;
		LimitBuyZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = ZCBBuys[currentID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (orderYTamt >= _amountYT) {
				uint scaledZCBamt = order.amount.mul(_amountYT);
				scaledZCBamt = scaledZCBamt/orderYTamt + (scaledZCBamt%orderYTamt == 0 ? 0 : 1);

				ZCBsold += scaledZCBamt;
				YTbought += _amountYT;

				manageCollateral_ReceiveZCB(order.maker, scaledZCBamt);
				if (order.amount == scaledZCBamt) {
					headZCBBuyID = order.nextID;
					delete ZCBBuys[currentID];
				}
				else {
					ZCBBuys[currentID].amount = order.amount - scaledZCBamt;
					headZCBBuyID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, order.amount);
				delete ZCBBuys[currentID];

				ZCBsold += order.amount;
				YTbought += orderYTamt;
				_amountYT -= orderYTamt;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headZCBBuyID = currentID;
	}

	function marketSellYT(
		uint _amountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint ZCBbought, uint YTsold) {

		uint currentID = headYTBuyID;
		LimitBuyYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = YTBuys[currentID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (order.amount >= _amountYT) {
				uint scaledZCBamt = orderZCBamt.mul(_amountYT).div(order.amount);

				ZCBbought += scaledZCBamt;
				YTsold += _amountYT;

				manageCollateral_ReceiveYT_fillOrder(order.maker, _amountYT, ratio);
				if (order.amount == _amountYT) {
					headYTBuyID = order.nextID;
					delete YTBuys[currentID];
				}
				else {
					YTBuys[currentID].amount = order.amount - _amountYT;
					headYTBuyID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, order.amount, ratio);
				delete YTBuys[currentID];

				ZCBbought += orderZCBamt;
				YTsold += order.amount;
				_amountYT -= order.amount;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headYTBuyID = currentID;
	}


	function marketBuyZCB(
		uint _amountZCB,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint ZCBbought, uint YTsold) {

		uint currentID = headYTBuyID;
		LimitBuyYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = YTBuys[currentID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (orderZCBamt >= _amountZCB) {
				uint scaledYTamt = order.amount.mul(_amountZCB);
				scaledYTamt = scaledYTamt/orderZCBamt + (scaledYTamt%orderZCBamt == 0 ? 0 : 1);

				ZCBbought += _amountZCB;
				YTsold += scaledYTamt;

				manageCollateral_ReceiveYT_fillOrder(order.maker, scaledYTamt, ratio);
				if (order.amount == scaledYTamt) {
					headYTBuyID = order.nextID;
					delete YTBuys[currentID];
				}
				else {
					YTBuys[currentID].amount = order.amount - _amountZCB;
					headYTBuyID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			else {

				manageCollateral_ReceiveYT_fillOrder(order.maker, order.amount, ratio);
				delete YTBuys[currentID];

				ZCBbought += orderZCBamt;
				YTsold += order.amount;
				_amountZCB -= orderZCBamt;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headYTBuyID = currentID;
	}

	function marketSellZCB(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint YTbought, uint ZCBsold) {

		uint currentID = headZCBBuyID;
		LimitBuyZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = ZCBBuys[currentID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (order.amount >= _amountZCB) {
				uint scaledYTamt = orderYTamt.mul(_amountZCB).div(order.amount);

				ZCBsold += _amountZCB;
				YTbought += scaledYTamt;

				manageCollateral_ReceiveZCB(order.maker, _amountZCB);
				if (order.amount == _amountZCB) {
					headZCBBuyID = order.nextID;
					delete ZCBBuys[currentID];
				}
				else {
					ZCBBuys[currentID].amount = order.amount - _amountZCB;
					headZCBBuyID = currentID;
				}

				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			else {

				manageCollateral_ReceiveZCB(order.maker, order.amount);
				delete ZCBBuys[currentID];

				ZCBsold += order.amount;
				YTbought += orderYTamt;
				_amountZCB -= order.amount;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headZCBBuyID = currentID;
	}

	function marketSellZCBtoU(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint YTbought, uint ZCBsold) {

		uint currentID = headZCBBuyID;
		LimitBuyZCB memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = ZCBBuys[currentID];
			if (order.maturityConversionRate > _maxMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
				return (YTbought, ZCBsold);
			}
			uint unitAmtYTbought = YTbought.mul(ratio) / (1 ether);
			uint orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			uint orderUnitYTamt = orderYTamt.mul(ratio) / (1 ether);
			if (_amountZCB <= order.amount || orderUnitYTamt.add(unitAmtYTbought) >= _amountZCB.sub(order.amount)) {
				uint orderRatio = order.amount.mul(1 ether).div(orderYTamt); //ratio of ZCB to YT for specific order
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
					headZCBBuyID = order.nextID;
					delete ZCBBuys[currentID];
				}
				else {
					ZCBBuys[currentID].amount = order.amount - ZCBtoSell;
					headZCBBuyID = currentID;
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
				delete ZCBBuys[currentID];

				ZCBsold += order.amount;
				YTbought += orderYTamt;
				_amountZCB -= order.amount;
			}
		}
		require(impliedMaturityConversionRate(ZCBsold, YTbought, ratio) <= _maxCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyYT_takeOrder(msg.sender, ZCBsold, YTbought, ratio, _useInternalBalances);
		headZCBBuyID = currentID;
	}

	function marketSellYTtoU(
		uint _amountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) public returns(uint ZCBbought, uint YTsold) {

		uint currentID = headYTBuyID;
		LimitBuyYT memory order;
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		for (uint16 i = 0; i < _maxIterations && currentID != 0; i++) {
			order = YTBuys[currentID];
			if (order.maturityConversionRate < _minMaturityConversionRate) {
				require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
				//collect & distribute to taker
				manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
				return (ZCBbought, YTsold);
			}
			uint unitAmtYT = _amountYT.mul(ratio) / (1 ether);
			uint orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			uint orderUnitAmtYT = order.amount.mul(ratio) / (1 ether);
			if (orderUnitAmtYT >= unitAmtYT || ZCBbought.add(orderZCBamt) >= unitAmtYT.sub(orderUnitAmtYT)) {
				uint orderRatio = orderZCBamt.mul(1 ether).div(order.amount); //ratio of ZCB to YT for specific order
				/*
					unitAmtYT - unitYTtoSell == ZCBbought + ZCBtoBuy
					ZCBtoBuy == YTtoSell * orderRatio
					YTtoSell = unitYTtoSell / ratio

					unitAmtYT - YTtoSell*ratio == ZCBbought + YTtoSell*orderRatio
					YTtoSell*(orderRatio + ratio) == unitAmtYT - ZCBbought
					YTtoSell == (unitAmtYT - ZCBbought) / (orderRatio + ratio)
				*/
				uint YTtoSell = unitAmtYT.sub(ZCBbought).mul(1 ether).div(ratio.add(orderRatio));
				uint ZCBtoBuy = YTtoSell.mul(orderRatio) / (1 ether);

				YTsold += YTtoSell;
				ZCBbought += ZCBtoBuy;

				manageCollateral_ReceiveYT_fillOrder(order.maker, YTtoSell, ratio);
				if (order.amount <= YTtoSell) {
					headYTBuyID = order.nextID;
					delete YTBuys[currentID];
				}
				else {
					YTBuys[currentID].amount = order.amount - YTtoSell;
					headYTBuyID = currentID;
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

				manageCollateral_ReceiveYT_fillOrder(order.maker, order.amount, ratio);
				delete YTBuys[currentID];

				ZCBbought += orderZCBamt;
				YTsold += order.amount;
				_amountYT -= order.amount;
			}
			currentID = order.nextID;
		}
		require(impliedMaturityConversionRate(ZCBbought, YTsold, ratio) >= _minCumulativeMaturityConversionRate);
		//collect & distribute to taker
		manageCollateral_BuyZCB_takeOrder(msg.sender, ZCBbought, YTsold, ratio, _useInternalBalances);
		headYTBuyID = currentID;
	}

}