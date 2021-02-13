pragma solidity >=0.6.0;
import "./organizer.sol";
import "./helpers/IZCBamm.sol";
import "./helpers/Ownable.sol";
import "./interfaces/IVaultHealth.sol";
import "./interfaces/ICapitalHandler.sol";
import "./libraries/ABDKMath64x64.sol";
import "./libraries/SafeMath.sol";
import "./oracle/interfaces/IOracleContainer.sol";


contract VaultHealth is IVaultHealth, Ownable {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	uint private constant SecondsPerYear = 31556926;

	int128 private constant ABDK_1 = 1<<64;

	uint private constant BONE = 1 ether;

	enum RateAdjuster {
		UPPER_DEPOSIT,
		MID_DEPOSIT,
		LOW_DEPOSIT,
		BASE,
		LOW_BORROW,
		MID_BORROW,
		UPPER_BORROW
	}

	/*
		When a user deposits bonds we take the Maximum of the rate shown in the oracle +
		MIN_RATE_BOND_DEPOSITED and the rate shown in the oracle adjusted with the
		corresponding rate threshold as the rate for which collateralization requirements
		will be calculated
	*/
	int128 constant MIN_RATE_ADJUSTMENT = ABDK_1 / 100;

	mapping(address => uint120) public LowerCollateralizationRatio;

	mapping(address => uint120) public MiddleCollateralizationRatio;

	mapping(address => uint120) public UpperCollateralizationRatio;


	/*
		Because rates are always over 1.0 the rate thresholds refer to the % change in the rate.
		For example if there is a rate treshold of 25% and the current rate for that asset is 
		3% the rate used when calculating borrow requirements for that asset will be
		3% * (100% - 25%) == 3% * (75%) == 3% * 0.75 == 2.25%
		To calculate the rate for deposit calculations for that asset we would do the following
		3% * (100% + 25%) == 3% * (125%) == 3% * 1.25 == 3.75%
	*/
	mapping(address => uint120) public LowerRateThreshold;

	mapping(address => uint120) public MiddleRateThreshold;

	mapping(address => uint120) public UpperRateThreshold;

	address organizerAddress;
	address oracleContainerAddress;

	constructor(address _oracleContainerAddress) public {
		oracleContainerAddress = _oracleContainerAddress;
	}

	function getYearsRemaining(address _capitalHandlerAddress) internal view returns (int128) {
		return int128(((ICapitalHandler(_capitalHandlerAddress).maturity() - block.timestamp) << 64) / SecondsPerYear);
	}

	function isDepoisted(RateAdjuster ra) internal pure returns(bool) {
		return ra == RateAdjuster.UPPER_DEPOSIT || ra == RateAdjuster.MID_DEPOSIT || ra == RateAdjuster.LOW_DEPOSIT;
	}

	function isBorrowed(RateAdjuster ra) internal pure returns(bool) {
		return ra == RateAdjuster.UPPER_BORROW || ra == RateAdjuster.MID_BORROW || ra == RateAdjuster.LOW_BORROW;
	}

	function getRateThresholdMultiplier(address _capitalHandlerAddress, RateAdjuster _rateAdjuster) internal view returns (int128 multiplier) {
		multiplier = ABDK_1;
		if (_rateAdjuster == RateAdjuster.UPPER_BORROW) {
			multiplier -= int128(UpperRateThreshold[_capitalHandlerAddress]);
		}
		else if (_rateAdjuster == RateAdjuster.MID_BORROW) {
			multiplier -= int128(MiddleRateThreshold[_capitalHandlerAddress]);
		}
		else if (_rateAdjuster == RateAdjuster.LOW_BORROW) {
			multiplier -= int128(LowerRateThreshold[_capitalHandlerAddress]);
		}
		else if (_rateAdjuster == RateAdjuster.UPPER_DEPOSIT) {
			multiplier += int128(UpperRateThreshold[_capitalHandlerAddress]);
		}
		else if (_rateAdjuster == RateAdjuster.MID_DEPOSIT) {
			multiplier += int128(MiddleRateThreshold[_capitalHandlerAddress]);
		}
		else if (_rateAdjuster == RateAdjuster.LOW_DEPOSIT) {
			multiplier += int128(LowerRateThreshold[_capitalHandlerAddress]);
		}
		require(multiplier != ABDK_1 || _rateAdjuster == RateAdjuster.BASE);
	}

	function getRateMultiplier(address _capitalHandlerAddress, RateAdjuster _rateAdjuster) internal view returns (uint) {
		IZCBamm amm = IZCBamm(organizer(organizerAddress).ZCBamms(_capitalHandlerAddress));
		if (address(amm) == address(0)) return BONE;
		int128 yearsRemaining = getYearsRemaining(_capitalHandlerAddress);
		int128 apy = amm.getAPYFromOracle();
		int128 adjApy = apy.sub(ABDK_1).mul(getRateThresholdMultiplier(_capitalHandlerAddress, _rateAdjuster)).add(ABDK_1);
		if (isDepoisted(_rateAdjuster)) {
			int128 temp = apy.add(MIN_RATE_ADJUSTMENT);
			adjApy = temp > adjApy ? adjApy : temp;
		}
		else if (isBorrowed(_rateAdjuster)) {
			int128 temp = apy.sub(MIN_RATE_ADJUSTMENT);
			adjApy = temp > adjApy ? temp : adjApy;
		}
		if (adjApy <= ABDK_1) return BONE;
		/*
			rateMultiplier == 1 / ((adjApy)**yearsRemaining)
			rateMultiplier == 1 / (2**(log_2((adjApy)**yearsRemaining)))
			rateMultiplier == 1 / (2**(yearsRemaining*log_2((adjApy))))
			rateMultiplier == 2**(-1*yearsRemaining*log_2((adjApy)))
			rateMultiplier == adjApy.log_2().mul(yearsRemaining).neg().exp_2()
		*/
		int128 rateMultiplier = adjApy.log_2().mul(yearsRemaining).neg().exp_2();
		if (rateMultiplier >= ABDK_1) return BONE;
		//normalize by changing to BONE format
		return uint(rateMultiplier).mul(BONE) >> 64;
	}

	/*
		@Description: returns price of deposited/borrowed
	*/
	function crossAssetPrice(address _deposited, address _borrowed) internal view returns(uint) {
		organizer org = organizer(organizerAddress);
		address _oracleContainerAddress = oracleContainerAddress;

		//get aToken addresss
		address baseBorrowedAsset = org.capitalHandlerToAToken(_borrowed);
		require(baseBorrowedAsset != address(0));
		uint PriceBorrowededAsset = IOracleContainer(_oracleContainerAddress).getAssetPrice(_borrowed);
		uint PriceDepositedAsset;
		// deposited asset is an aToken)
		if (UpperRateThreshold[_deposited] != 0) {
			PriceDepositedAsset = IOracleContainer(_oracleContainerAddress).getAssetPrice(_deposited);
		}
		// else deposited asset is a ZCB
		else {
			address baseDepositedAsset = org.capitalHandlerToAToken(_deposited);
			require(baseDepositedAsset != address(0));
			PriceDepositedAsset = IOracleContainer(_oracleContainerAddress).getAssetPrice(baseDepositedAsset);
		}
		return BONE.mul(PriceDepositedAsset).div(PriceBorrowededAsset);
	}

	//-------------------implement IVaultHealth------------------------

	//return true if collateral is above upper limit
	function upperLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		uint price = crossAssetPrice(_assetSupplied, _assetBorrowed);
		uint RateMultiplierSupplied = getRateMultiplier(_assetSupplied, RateAdjuster.UPPER_DEPOSIT);
		uint RateMultiplierBorrowed = getRateMultiplier(_assetBorrowed, RateAdjuster.UPPER_BORROW);
		uint RequiredCollateralizationRatio = uint(UpperCollateralizationRatio[_assetSupplied]).mul(uint(UpperCollateralizationRatio[_assetBorrowed])).div(BONE);
		//return price.mul(_amountBorrowed).mul(RateMultiplierBorrowed).mul(RequiredCollateralizationRatio).div(BONE**3) < _amountSupplied.mul(RateMultiplierSupplied).div(BONE);
		return price.mul(_amountBorrowed).mul(RateMultiplierBorrowed).mul(RequiredCollateralizationRatio).div(BONE**2) < _amountSupplied.mul(RateMultiplierSupplied);
	}
	//return true if collateral is above middle limit
	function middleLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		uint price = crossAssetPrice(_assetSupplied, _assetBorrowed);
		uint RateMultiplierSupplied = getRateMultiplier(_assetSupplied, RateAdjuster.MID_DEPOSIT);
		uint RateMultiplierBorrowed = getRateMultiplier(_assetBorrowed, RateAdjuster.MID_BORROW);
		uint RequiredCollateralizationRatio = uint(MiddleCollateralizationRatio[_assetSupplied]).mul(uint(MiddleCollateralizationRatio[_assetBorrowed])).div(BONE);
		//return price.mul(_amountBorrowed).mul(RateMultiplierBorrowed).mul(RequiredCollateralizationRatio).div(BONE**3) < _amountSupplied.mul(RateMultiplierSupplied).div(BONE);
		return price.mul(_amountBorrowed).mul(RateMultiplierBorrowed).mul(RequiredCollateralizationRatio).div(BONE**2) < _amountSupplied.mul(RateMultiplierSupplied);
	}
	//return true if collateral is above lower limit
	function lowerLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		uint price = crossAssetPrice(_assetSupplied, _assetBorrowed);
		uint RateMultiplierSupplied = getRateMultiplier(_assetSupplied, RateAdjuster.LOW_DEPOSIT);
		uint RateMultiplierBorrowed = getRateMultiplier(_assetBorrowed, RateAdjuster.LOW_BORROW);
		uint RequiredCollateralizationRatio = uint(LowerCollateralizationRatio[_assetSupplied]).mul(uint(LowerCollateralizationRatio[_assetBorrowed])).div(BONE);
		//return price.mul(_amountBorrowed).mul(RateMultiplierBorrowed).mul(RequiredCollateralizationRatio).div(BONE**3) < _amountSupplied.mul(RateMultiplierSupplied).div(BONE);
		return price.mul(_amountBorrowed).mul(RateMultiplierBorrowed).mul(RequiredCollateralizationRatio).div(BONE**2) < _amountSupplied.mul(RateMultiplierSupplied);
	}


	//-----------------------a-d-m-i-n---o-p-e-r-a-t-i-o-n-s---------------------------
	function setCollateralizationRatios(address _aTokenAddress, uint120 _upper, uint120 _middle, uint120 _lower) external onlyOwner {
		require(_upper >= _middle && _middle >= _lower && _lower > ABDK_1);
		UpperCollateralizationRatio[_aTokenAddress] = _upper;
		MiddleCollateralizationRatio[_aTokenAddress] = _middle;
		LowerCollateralizationRatio[_aTokenAddress] = _lower;
	}

	function setRateThresholds(address _aTokenAddress, uint120 _upper, uint120 _middle, uint120 _lower) external onlyOwner {
		require(_upper >= _middle && _middle >= _lower && _lower > 0);
		UpperRateThreshold[_aTokenAddress] = _upper;
		MiddleRateThreshold[_aTokenAddress] = _middle;
		LowerRateThreshold[_aTokenAddress] = _lower;
	}

	function setOrganizerAddress(address _organizerAddress) external onlyOwner {
		require(organizerAddress == address(0));
		organizerAddress = _organizerAddress;
	}
}

