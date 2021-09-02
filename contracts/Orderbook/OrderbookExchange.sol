// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IOrderbookExchange.sol";
import "../helpers/Ownable.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "./OrderbookData.sol";

contract OrderbookExchange is OrderbookData, IOrderbookExchange {

	address immutable delegate1Address;
	address immutable delegate2Address;
	address immutable delegate3Address;

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	constructor(
		address _FCPaddress,
		address _infoOracleAddress,
		address _delegate1Address,
		address _delegate2Address,
		address _delegate3Address
	) public {
		internalFCP = IFixCapitalPool(_FCPaddress);
		internalIORC = IInfoOracle(_infoOracleAddress);
		IWrapper tempWrapper = IFixCapitalPool(_FCPaddress).wrapper();
		internalMaturity = IFixCapitalPool(_FCPaddress).maturity();
		internalWrapper = tempWrapper;
		delegate1Address = _delegate1Address;
		delegate2Address = _delegate2Address;
		delegate3Address = _delegate3Address;
		tempWrapper.registerAsDistributionAccount();
	}

	/*
		@Description: deposit ZCB & YT into the orderbook, pass a yield and bond amount

		@param uint _amountYield: the yield amount of the ZCB YT position to deposit
		@param int _amoutBond: the bond amount of the ZCB YT position to deposit
	*/
	function deposit(uint _amountYield, int _amountBond) external override {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
			"deposit(uint256,int256)",
			_amountYield,
			_amountBond
		));
		require(success);
	}

	/*
		@Description: withdraw ZCB & YT from the orderbook, pass a yiel and bond amount

		@param uint _amountYield: the yield amount of the ZCB YT position to withdraw
		@param int _amountBond: the bond amount of the ZCB YT position to withdraw
	*/
	function withdraw(uint _amountYield, int _amountBond) external override {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
			"withdraw(uint256,int256)",
			_amountYield,
			_amountBond
		));
		require(success);
	}

	//-------------------externally-callable-------------------

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
	) external override {
		address _delegateAddress = delegate3Address;
		bytes memory sig = abi.encodeWithSignature(
			"limitSellZCB(uint256,uint256,uint256,uint256)",
			_amount,
			_maturityConversionRate,
			_hintID,
			_maxSteps
		);

		uint prevID;
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			prevID := mload(retPtr)
		}

		emit MakeLimitSellZCB(msg.sender, prevID, _amount, _maturityConversionRate);
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
	) external override {
		address _delegateAddress = delegate3Address;
		bytes memory sig = abi.encodeWithSignature(
			"limitSellYT(uint256,uint256,uint256,uint256)",
			_amount,
			_maturityConversionRate,
			_hintID,
			_maxSteps
		);

		uint prevID;
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			prevID := mload(retPtr)
		}

		emit MakeLimitSellYT(msg.sender, prevID, _amount, _maturityConversionRate);
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
	) external override returns(int change) {
		address _delegateAddress = delegate3Address;
		bytes memory sig = abi.encodeWithSignature(
			"modifyZCBLimitSell(int256,uint256,uint256,uint256,bool)",
			_amount,
			_targetID,
			_hintID,
			_maxSteps,
			_removeBelowMin
		);

		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			change := mload(retPtr)
		}

		emit ModifyOrder(_targetID, change);
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
	) external override returns(int change) {
		address _delegateAddress = delegate3Address;
		bytes memory sig = abi.encodeWithSignature(
			"modifyYTLimitSell(int256,uint256,uint256,uint256,bool)",
			_amount,
			_targetID,
			_hintID,
			_maxSteps,
			_removeBelowMin
		);

		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			change := mload(retPtr)
		}

		emit ModifyOrder(_targetID, change);
	}

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
	) external override returns(uint /*YTbought*/,uint /*ZCBsold*/) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature(
			"marketBuyYT(uint256,uint256,uint256,uint16,bool)",
			_amountYT,
			_maxMaturityConversionRate,
			_maxCumulativeMaturityConversionRate,
			_maxIterations,
			_useInternalBalances
		);

		bytes32 nameTopic = keccak256("MarketBuyYT(address,uint256,uint256)");
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x80)

			if iszero(success) { revert(0,0) }

			log2(add(retPtr, 0x40), 0x40, nameTopic, caller())
			return(retPtr, 0x40)
		}

	}

	/*
		@Description: sell a specific amount of YT on the market

		@param uint _amountYT: the amount of YT to sell
		@param uint _minMaturityConversionRate: the minimum MCR of the head order to continue selling more YT
		@param uint _minCumulativeMaturityConversionRate: if this is greater than the effective MCR based on YT in and ZCB out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations
		@param bool _useInternalBalances: pass true to ue YieldDeposited and BondDeposited to cover costs and receive payment
			otherwise use transferPositionFrom and transferPosition on the baseFCP to get required input and send required output
	*/
	function marketSellYT(
		uint _amountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external override returns(uint /*ZCBbought*/, uint /*YTsold*/) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature(
			"marketSellYT(uint256,uint256,uint256,uint16,bool)",
			_amountYT,
			_minMaturityConversionRate,
			_minCumulativeMaturityConversionRate,
			_maxIterations,
			_useInternalBalances
		);

		bytes32 nameTopic = keccak256("MarketBuyZCB(address,uint256,uint256)");
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x80)

			if iszero(success) { revert(0,0) }

			log2(add(retPtr, 0x40), 0x40, nameTopic, caller())
			return(retPtr, 0x40)
		}
	}

	/*
		@Description: buy a specific amount of ZCB off of the market

		@param uint _amountZCB: the amount of ZCB to buy
		@param uint _minMaturityConversionRate: the minimum MCR of the head order to continue purchasing more ZCB
		@param uint _minCumulativeMaturityConversionRate: if this is greater than the effective MCR based on YT in and ZCB out at end of execution revert
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
	) external override returns(uint /*ZCBbought*/, uint /*YTsold*/) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature(
			"marketBuyZCB(uint256,uint256,uint256,uint16,bool)",
			_amountZCB,
			_minMaturityConversionRate,
			_minCumulativeMaturityConversionRate,
			_maxIterations,
			_useInternalBalances
		);

		bytes32 nameTopic = keccak256("MarketBuyZCB(address,uint256,uint256)");
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x80)

			if iszero(success) { revert(0,0) }

			log2(add(retPtr, 0x40), 0x40, nameTopic, caller())
			return(retPtr, 0x40)
		}
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
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external override returns(uint /*YTbought*/, uint /*ZCBsold*/) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature(
			"marketSellZCB(uint256,uint256,uint256,uint16,bool)",
			_amountZCB,
			_maxMaturityConversionRate,
			_maxCumulativeMaturityConversionRate,
			_maxIterations,
			_useInternalBalances
		);

		bytes32 nameTopic = keccak256("MarketBuyYT(address,uint256,uint256)");
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x80)

			if iszero(success) { revert(0,0) }

			log2(add(retPtr, 0x40), 0x40, nameTopic, caller())
			return(retPtr, 0x40)
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
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external override returns(uint /*YTbought*/, uint /*ZCBsold*/) {
		address _delegateAddress = delegate2Address;
		bytes memory sig = abi.encodeWithSignature(
			"marketSellZCBtoU(uint256,uint256,uint256,uint16,bool)",
			_amountZCB,
			_maxMaturityConversionRate,
			_maxCumulativeMaturityConversionRate,
			_maxIterations,
			_useInternalBalances
		);

		bytes32 nameTopic = keccak256("MarketBuyYT(address,uint256,uint256)");
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x80)

			if iszero(success) { revert(0,0) }

			log2(add(retPtr, 0x40), 0x40, nameTopic, caller())
			return(retPtr, 0x40)
		}
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
		uint _unitAmountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external override returns(uint /*ZCBbought*/, uint /*YTsold*/) {
		address _delegateAddress = delegate2Address;
		bytes memory sig = abi.encodeWithSignature(
			"marketSellUnitYTtoU(uint256,uint256,uint256,uint16,bool)",
			_unitAmountYT,
			_minMaturityConversionRate,
			_minCumulativeMaturityConversionRate,
			_maxIterations,
			_useInternalBalances
		);

		bytes32 nameTopic = keccak256("MarketBuyZCB(address,uint256,uint256)");
		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x80)

			if iszero(success) { revert(0,0) }

			log2(add(retPtr, 0x40), 0x40, nameTopic, caller())
			return(retPtr, 0x40)
		}
	}

	/*
		@Description: force claim sub account rewards where distribution account is the orderbook and sub acct is msg.sender
	*/
	function forceClaimSubAccountRewards() external override {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature("forceClaimSubAccountRewards()"));
		require(success);
	}

	//-----------------rate-oracle---------------------

	/*
		@Description: force the rate oracle to record a new datapoint
	*/
	function forceRateDataUpdate() external override {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature("forceRateDataUpdate()"));
		require(success);
	}

	/*
		@Description: set the median of all datapoints in the impliedRates array as the
			oracle rate, may only be called after all datapoints have been updated since
			last call to this function

		@param uint _MCR: the median of all MCR datapoints
	*/
	function setOracleMCR(uint _MCR) external override {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
			"setOracleMCR(uint256)",
			_MCR
		));
		require(success);
	}

	/*
		@Description: returns the implied yield from the rate offered in this amm between now and maturity

		@return uint yieldToMaturity: the multiplier by which the market anticipates the conversionRate to increase by up to maturity
	*/
	function impliedYieldToMaturity() external view override returns (uint yieldToMaturity) {
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint _oracleMCR = OracleMCR;
		return ratio < _oracleMCR ? _oracleMCR.mul(1 ether).div(ratio) : (1 ether);
	}

	/*
		@Description: get the implied APY of this amm

		@return int128 APY: the implied APY of this amm in ABDK64.64 format
	*/
	function getAPYFromOracle() external view override returns (int128 APY) {
		uint _oracleMCR = OracleMCR;
		uint ratio = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		if (ratio >= _oracleMCR) {
			return ABDK_1;
		}
		/*
			APY**yearsRemaining == MCR / ratio
			APY == (MCR / ratio)**(1/yearsRemaining)
			APY == exp2 ( log 2 ( (MCR/ratio)**(1/yearsRemaining) ))
			APY == exp2 ( (1/yearsRemaining) * log 2 (MCR/ratio))
		*/
		int128 yearsRemaining = int128((uint(internalMaturity).sub(internalWrapper.lastUpdate()) << 64) / SecondsPerYear);
		uint base = _oracleMCR.mul(1 << 64).div(ratio);
		require(base <= uint(type(int128).max));
		int128 exp = ABDK_1.div(yearsRemaining);
		APY = BigMath.Pow(int128(base), exp);
	}

	/*
		@Description: get the implied MCR from the rate oracle
	*/
	function getImpliedMCRFromOracle() external view override returns(uint impliedMCR) {
		impliedMCR = OracleMCR;
	}

	/*
		@Description: get all rate datapoints and information about the state of the rate oracle
	*/
	function getOracleData() external view override returns (
		uint[LENGTH_RATE_SERIES] memory _impliedMCRs,
		uint _lastDatapointCollection,
		uint _oracleMCR,
		uint8 _toSet
	) {
		_impliedMCRs = impliedMCRs;
		_lastDatapointCollection = lastDatapointCollection;
		_oracleMCR = OracleMCR;
		_toSet = toSet;
	}

	//-----------------admin-------------------------

	/*
		@Description: payout fees earned by the orderbook contract
	*/
	function claimRevenue() external override {
		require(msg.sender == Ownable(address(internalFCP)).owner());
		IInfoOracle iorc = internalIORC;
		IWrapper wrp = internalWrapper;
		IFixCapitalPool fcp = internalFCP;
		address treasury = iorc.sendTo();
		(uint yieldTreasury, int bondTreasury) = wrp.subAccountPositions(address(this), treasury, address(fcp));
		(uint yieldOwner, int bondOwner) = wrp.subAccountPositions(address(this), msg.sender, address(fcp));

		//if owner has funds deposited in the orderbook we need to disregard the effect that has on the owner's sub account with the orderbook
		yieldOwner = yieldOwner.sub(internalYieldDeposited[msg.sender]);
		bondOwner = bondOwner.sub(internalBondDeposited[msg.sender]);

		if (iorc.TreasuryFeeIsCollected()) {
			/*
				Despite sub account yield going to treasury, half of that sub account position is actually paid out to the owner in fees
				This is because 100% of all yield exposure is given to the treasury when TreasuryFeeIsCollected() returns true
			*/
			uint adjYieldTreasury = yieldTreasury/2;
			int adjBondTreasury = bondTreasury/2;

			uint adjYieldOwner = yieldOwner.add(yieldTreasury - adjYieldTreasury);
			int adjBondOwner = bondOwner.add(bondTreasury - adjBondTreasury);

			fcp.transferPosition(treasury, adjYieldTreasury, adjBondTreasury);
			fcp.transferPosition(msg.sender, adjYieldOwner, adjBondOwner);
		}
		else {
			fcp.transferPosition(treasury, yieldOwner.add(yieldTreasury), bondOwner.add(bondTreasury));
		}

		if (yieldTreasury != 0 || bondTreasury != 0) {
			internalWrapper.editSubAccountPosition(false, treasury, address(fcp), yieldTreasury.toInt().mul(-1), bondTreasury.mul(-1));
		}

		if (yieldOwner != 0 || bondOwner != 0) {
			internalWrapper.editSubAccountPosition(false, msg.sender, address(fcp), yieldOwner.toInt().mul(-1), bondOwner.mul(-1));
		}
	}

	/*
		@Description: set the minimum size of an order on the orderbook
			size is determined by the amount of U that the collateral for the order
			would be valued at using the MCR of that order

		@param MIN_ORDER_SIZE_MODE mode: the mode for which minimum order sized will be calculated
		@param uint _minimumOrderSize: if NPV, the minimum NPV in dynamic amounts
			if NOMINAL, this is the actual nominal amount of the minimum order size
			if NONE, this param doesn't matter
	*/
	function setMinimumOrderSize(MIN_ORDER_SIZE_MODE mode, uint _minimumOrderSize) external override {
		require(msg.sender == Ownable(address(internalFCP)).owner());
		minimumOrderSize = mode == MIN_ORDER_SIZE_MODE.NONE ? 0 : _minimumOrderSize;
		sizingMode = mode;
	}

	//-----------------VIEWS-----------------

	function YieldDeposited(address _depositor) external view override returns(uint) {
		return internalYieldDeposited[_depositor];
	}

	function BondDeposited(address _depositor) external view override returns(int) {
		return internalBondDeposited[_depositor];
	}

	function lockedYT(address _depositor) external view override returns(uint) {
		return internalLockedYT[_depositor];
	}

	function lockedZCB(address _depositor) external view override returns(uint) {
		return internalLockedZCB[_depositor];
	}

	function YTSells(uint _ID) external view override returns(
		address maker,
		uint amount,
		uint maturityConversionRate,
		uint nextID
	) {
		LimitSellYT memory order = internalYTSells[_ID];
		maker = order.maker;
		amount = order.amount;
		maturityConversionRate = order.maturityConversionRate;
		nextID = order.nextID;
	}

	function ZCBSells(uint _ID) external view override returns(
		address maker,
		uint amount,
		uint maturityConversionRate,
		uint nextID
	) {
		LimitSellZCB memory order = internalZCBSells[_ID];
		maker = order.maker;
		amount = order.amount;
		maturityConversionRate = order.maturityConversionRate;
		nextID = order.nextID;
	}

	function headYTSellID() external view override returns(uint ID) {
		ID = internalHeadYTSellID;
	}

	function headZCBSellID() external view override returns(uint ID) {
		ID = internalHeadZCBSellID;
	}

	function FCP() external view override returns(IFixCapitalPool) {
		return internalFCP;
	}

	function IORC() external view override returns(IInfoOracle) {
		return internalIORC;
	}

	function wrapper() external view override returns(IWrapper) {
		return internalWrapper;
	}

	function maturity() external view override returns(uint40) {
		return internalMaturity;
	}

	/*
		@Description: if min order sizing mode is NPV, get the minimum NPV of a limit order
			where NPV is in U and is determined using the MCR of the limit order
			if min order sizing mode is NOMINAL return the nominal amount of ZCB and dynamic YT for limit orders
			if min order sizing mode is NONE, return 0
	*/
	function getMinimumOrderSize() external view override returns(uint) {
		return minimumOrderSize;
	}

	/*
		@Description: get the current mode by which minimum limit order sizes are calculated
	*/
	function getMinimumOrderSizeMode() external view override returns(MIN_ORDER_SIZE_MODE) {
		return sizingMode;
	}
}