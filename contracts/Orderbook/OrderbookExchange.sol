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

	address immutable delegate1Address;

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	constructor(address _FCPaddress, address _delegate1Address) public {
		FCP = IFixCapitalPool(_FCPaddress);
		wrapper = IFixCapitalPool(_FCPaddress).wrapper();
		maturity = IFixCapitalPool(_FCPaddress).maturity();
		delegate1Address = _delegate1Address;
	}

	function deposit(uint _amountYield, int _amountBond) public {
		FCP.transferPositionFrom(msg.sender, address(this), _amountYield, _amountBond);
		YieldDeposited[msg.sender] += _amountYield;
		BondDeposited[msg.sender] += _amountBond;
	}

	function withdraw(uint _amountYield, int _amountBond) public {
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
	) external {
		address _delegateAddress = delegate1Address;
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
	) external {
		address _delegateAddress = delegate1Address;
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
		uint _maxSteps
	) external returns(int change) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature(
			"modifyZCBLimitSell(int256,uint256,uint256,uint256)",
			_amount,
			_targetID,
			_hintID,
			_maxSteps
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
		uint _maxSteps
	) external returns(int change) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature(
			"modifyYTLimitSell(int256,uint256,uint256,uint256)",
			_amount,
			_targetID,
			_hintID,
			_maxSteps
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
	) external returns (uint /*YTbought*/,uint /*ZCBsold*/) {
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
	) external returns(uint /*ZCBbought*/, uint /*YTsold*/) {
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
	) external returns(uint /*ZCBbought*/, uint /*YTsold*/) {
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
	) external returns(uint /*YTbought*/, uint /*ZCBsold*/) {
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
	) external returns(uint /*YTbought*/, uint /*ZCBsold*/) {
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
	) external returns(uint /*ZCBbought*/, uint /*YTsold*/) {
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
		@Description: returns the implied yield from the rate offered in this amm between now and maturity

		@return uint yieldToMaturity: the multiplier by which the market anticipates the conversionRate to increase by up to maturity
	*/
	function impliedYieldToMaturity() external view returns (uint yieldToMaturity) {
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint _oracleMCR = OracleMCR;
		return ratio < _oracleMCR ? _oracleMCR.mul(1 ether).div(ratio) : (1 ether);
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
		@Description: get the implied MCR from the rate oracle
	*/
	function getImpliedMCRFromOracle() external view returns(uint impliedMCR) {
		impliedMCR = OracleMCR;
	}

	/*
		@Description: get all rate datapoints and the timestamps at which they were recorded
	*/
	function getOracleData() external view returns (
		uint[LENGTH_RATE_SERIES] memory _impliedMCRs,
		uint _lastDatapointCollection,
		uint8 _toSet
	) {
		_impliedMCRs = impliedMCRs;
		_lastDatapointCollection = lastDatapointCollection;
		_toSet = toSet;
	}

}