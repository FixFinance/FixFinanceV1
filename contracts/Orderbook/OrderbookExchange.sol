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

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	constructor(
		address _internalFCPaddress,
		address _infoOracleAddress,
		address _delegate1Address,
		address _delegate2Address
	) public {
		internalFCP = IFixCapitalPool(_internalFCPaddress);
		internalIORC = IInfoOracle(_infoOracleAddress);
		IWrapper tempWrapper = IFixCapitalPool(_internalFCPaddress).wrapper();
		internalMaturity = IFixCapitalPool(_internalFCPaddress).maturity();
		internalWrapper = tempWrapper;
		delegate1Address = _delegate1Address;
		delegate2Address = _delegate2Address;
		tempWrapper.registerAsDistributionAccount();
	}

	function deposit(uint _amountYield, int _amountBond) external override {
		require(_amountYield <= uint(type(int256).max));
		IFixCapitalPool fcp = internalFCP; //gas savings
		fcp.transferPositionFrom(msg.sender, address(this), _amountYield, _amountBond);
		internalWrapper.editSubAccountPosition(false, msg.sender, address(fcp), int(_amountYield), _amountBond);
		internalYieldDeposited[msg.sender] = internalYieldDeposited[msg.sender].add(_amountYield);
		internalBondDeposited[msg.sender] = internalBondDeposited[msg.sender].add(_amountBond);
	}

	function withdraw(uint _amountYield, int _amountBond) external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"withdraw(uint256,int256)",
			_amountYield,
			_amountBond
		));
		require(success);
	}

	//-------------------externally-callable-------------------

	function limitSellZCB(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) external override {
		address _delegateAddress = delegate2Address;
		bytes memory sig = abi.encodeWithSignature(
			"limitSellZCB(uint256,uint256,uint256,uint256)",
			_amount,
			_maturityConversionRate,
			_hintID,
			_maxSteps
		);

		uint prevID;
		assembly {
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x20)

			if iszero(success) { revert(0,0) }

			prevID := mload(0)
		}

		emit MakeLimitSellZCB(msg.sender, prevID, _amount, _maturityConversionRate);
	}

	function limitSellYT(
		uint _amount,
		uint _maturityConversionRate,
		uint _hintID,
		uint _maxSteps
	) external override {
		address _delegateAddress = delegate2Address;
		bytes memory sig = abi.encodeWithSignature(
			"limitSellYT(uint256,uint256,uint256,uint256)",
			_amount,
			_maturityConversionRate,
			_hintID,
			_maxSteps
		);

		uint prevID;
		assembly {
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x20)

			if iszero(success) { revert(0,0) }

			prevID := mload(0)
		}

		emit MakeLimitSellYT(msg.sender, prevID, _amount, _maturityConversionRate);
	}

	function modifyZCBLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps,
		bool _removeBelowMin
	) external override returns(int change) {
		address _delegateAddress = delegate2Address;
		bytes memory sig = abi.encodeWithSignature(
			"modifyZCBLimitSell(int256,uint256,uint256,uint256,bool)",
			_amount,
			_targetID,
			_hintID,
			_maxSteps,
			_removeBelowMin
		);

		assembly {
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x20)

			if iszero(success) { revert(0,0) }

			change := mload(0)
		}

		emit ModifyOrder(_targetID, change);
	}

	function modifyYTLimitSell(
		int _amount,
		uint _targetID,
		uint _hintID,
		uint _maxSteps,
		bool _removeBelowMin
	) external override returns(int change) {
		address _delegateAddress = delegate2Address;
		bytes memory sig = abi.encodeWithSignature(
			"modifyYTLimitSell(int256,uint256,uint256,uint256,bool)",
			_amount,
			_targetID,
			_hintID,
			_maxSteps,
			_removeBelowMin
		);

		assembly {
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x20)

			if iszero(success) { revert(0,0) }

			change := mload(0)
		}

		emit ModifyOrder(_targetID, change);
	}

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
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x80)

			if iszero(success) { revert(0,0) }

			log2(0x40, 0x40, nameTopic, caller())
			return(0, 0x40)
		}

	}

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
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x80)

			if iszero(success) { revert(0,0) }

			log2(0x40, 0x40, nameTopic, caller())
			return(0, 0x40)
		}
	}

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
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x80)

			if iszero(success) { revert(0,0) }

			log2(0x40, 0x40, nameTopic, caller())
			return(0, 0x40)
		}
	}

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
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x80)

			if iszero(success) { revert(0,0) }

			log2(0x40, 0x40, nameTopic, caller())
			return(0, 0x40)
		}
	}

	function marketSellZCBtoU(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external override returns(uint /*YTbought*/, uint /*ZCBsold*/) {
		address _delegateAddress = delegate1Address;
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
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x80)

			if iszero(success) { revert(0,0) }

			log2(0x40, 0x40, nameTopic, caller())
			return(0, 0x40)
		}
	}

	function marketSellUnitYTtoU(
		uint _unitAmountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external override returns(uint /*ZCBbought*/, uint /*YTsold*/) {
		address _delegateAddress = delegate1Address;
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
			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), 0, 0x80)

			if iszero(success) { revert(0,0) }

			log2(0x40, 0x40, nameTopic, caller())
			return(0, 0x40)
		}
	}

	//-----------------rate-oracle---------------------

	/*
		@Description: force the rate oracle to record a new datapoint
	*/
	function forceRateDataUpdate() external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature("forceRateDataUpdate()"));
		require(success);
	}

	/*
		@Description: set the median of all datapoints in the impliedRates array as the
			oracle rate, may only be called after all datapoints have been updated since
			last call to this function

		@param uint _MCR: the median of all MCR datapoints
	*/
	function setOracleMCR(uint _MCR) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
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
		@Description: set the minimum size of an order on the orderbook
			size is determined by the amount of U that the collateral for the order
			would be valued at using the MCR of that order
	*/
	function setMinimumOrderSize(uint _minimumOrderSize) external {
		require(msg.sender == Ownable(address(internalFCP)).owner());
		minimumOrderSize = _minimumOrderSize;
	}

	/*
		@Description: get the minimum NPV of a limit order
			where NPV is in U and is determined using the MCR of the limit order
	*/
	function getMinimumOrderSize() external view returns(uint) {
		return minimumOrderSize;
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

	function YieldRevenue() external view override returns(uint) {
		return internalYieldRevenue;
	}

	function BondRevenue() external view override returns(int) {
		return internalBondRevenue;
	}

}