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

	address immutable delegateAddress;

	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

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
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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
		address _delegateAddress = delegateAddress;
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