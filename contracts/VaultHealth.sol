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

	uint private constant TOTAL_BASIS_POINTS = 10_000;

	int128 private constant ABDK_1 = 1<<64;

	uint private constant BONE = 1 ether;

	enum RateAdjuster {
		UPPER_DEPOSIT,
		LOW_DEPOSIT,
		BASE,
		LOW_BORROW,
		UPPER_BORROW
	}

	enum Safety {
		UPPER,
		LOW
	}

	/*
		When a user deposits bonds we take the Maximum of the rate shown in the oracle +
		MIN_RATE_BOND_DEPOSITED and the rate shown in the oracle adjusted with the
		corresponding rate threshold as the rate for which collateralization requirements
		will be calculated
	*/
	int128 constant MIN_RATE_ADJUSTMENT = ABDK_1 / 100;

	mapping(address => uint120) public LowerCollateralizationRatio;

	mapping(address => uint120) public UpperCollateralizationRatio;


	/*
		Because rates are always over 1.0 the rate thresholds refer to the % change in the rate minus 1.
		All rate thresholds must be above 1.0 as well,to get the resultant threshold adjusted rate for
		borrowing we find 1 + (rate - 1)/threshold
		to get the resultatn threshold adjusted rate for depositing we find
		1 + (rate - 1)*threshold
		For example if there is a rate treshold of 1.25 and the current rate for that asset is 
		3% the rate used when calculating borrow requirements for that asset will be
		3% / 1.25 == 2.4%
		To calculate the rate for deposit calculations for that asset we would do the following
		3% * 1.25 == 3.75%
	*/
	mapping(address => uint120) public LowerRateThreshold;

	mapping(address => uint120) public UpperRateThreshold;

	/*
		Set by contract owner this mapping shows the maximum amount of any underlying asset (at all durations combined)
		that may be shorted via the BoneMinter contract
	*/
	mapping(address => uint) public override maximumShortInterest;

	address organizerAddress;
	address oracleContainerAddress;

	constructor(address _oracleContainerAddress) public {
		oracleContainerAddress = _oracleContainerAddress;
	}

	function getYearsRemaining(address _capitalHandlerAddress) internal view returns (int128) {
		return int128(((ICapitalHandler(_capitalHandlerAddress).maturity() - block.timestamp) << 64) / SecondsPerYear);
	}

	function isDeposited(RateAdjuster ra) internal pure returns(bool) {
		return ra == RateAdjuster.UPPER_DEPOSIT  || ra == RateAdjuster.LOW_DEPOSIT;
	}

	function isBorrowed(RateAdjuster ra) internal pure returns(bool) {
		return ra == RateAdjuster.UPPER_BORROW || ra == RateAdjuster.LOW_BORROW;
	}

	function getRateThresholdMultiplier(address _underlyingAssetAddress, RateAdjuster _rateAdjuster) internal view returns (int128 multiplier) {
		if (_rateAdjuster == RateAdjuster.UPPER_BORROW) {
			multiplier = ABDK_1.div(int128(UpperRateThreshold[_underlyingAssetAddress]));
		}
		else if (_rateAdjuster == RateAdjuster.LOW_BORROW) {
			multiplier = ABDK_1.div(int128(LowerRateThreshold[_underlyingAssetAddress]));
		}
		else if (_rateAdjuster == RateAdjuster.UPPER_DEPOSIT) {
			multiplier = ABDK_1.mul(int128(UpperRateThreshold[_underlyingAssetAddress]));
		}
		else if (_rateAdjuster == RateAdjuster.LOW_DEPOSIT) {
			multiplier = ABDK_1.mul(int128(LowerRateThreshold[_underlyingAssetAddress]));
		}
		else {
			multiplier = ABDK_1;
		}

	}

	function getAPYFromOracle(address _capitalHandlerAddress) internal view returns (int128) {
		return ZCBamm(organizer(organizerAddress).ZCBamms(_capitalHandlerAddress)).getAPYFromOracle();
	}

	function getChangedAPYFromOracle(address _capitalHandlerAddress, int128 _rateChange) internal view returns (int128) {
		return getAPYFromOracle(_capitalHandlerAddress).sub(ABDK_1).mul(_rateChange).add(ABDK_1);
	}

	function getRateMultiplier_BaseRate(address _capitalHandlerAddress, address _underlyingAssetAddress, RateAdjuster _rateAdjuster) internal view returns (uint) {
		return getRateMultiplier(_capitalHandlerAddress, _underlyingAssetAddress, _rateAdjuster, getAPYFromOracle(_capitalHandlerAddress));
	}

	function getRateMultiplier_Changed(address _capitalHandlerAddress, address _underlyingAssetAddress, RateAdjuster _rateAdjuster, int128 _rateChange) internal view returns (uint) {
		return getRateMultiplier(_capitalHandlerAddress, _underlyingAssetAddress, _rateAdjuster, getChangedAPYFromOracle(_capitalHandlerAddress, _rateChange));
	}

	function getRateMultiplier(address _capitalHandlerAddress, address _underlyingAssetAddress, RateAdjuster _rateAdjuster, int128 _apy) internal view returns (uint) {
		//ensure that we have been passed a ZCB address if not there is a rate multiplier of 1.0
		int128 yearsRemaining = getYearsRemaining(_capitalHandlerAddress);
		int128 adjApy = _apy.sub(ABDK_1).mul(getRateThresholdMultiplier(_underlyingAssetAddress, _rateAdjuster)).add(ABDK_1);
		if (isDeposited(_rateAdjuster)) {
			int128 temp = _apy.add(MIN_RATE_ADJUSTMENT);
			adjApy = temp > adjApy ? temp : adjApy;
		}
		else if (isBorrowed(_rateAdjuster)) {
			int128 temp = _apy.sub(MIN_RATE_ADJUSTMENT);
			adjApy = temp < adjApy ? temp : adjApy;
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
		if (_deposited == _borrowed) {
			return BONE;
		}
		IOracleContainer orc = IOracleContainer(oracleContainerAddress);
		uint PriceDepositedAsset = orc.getAssetPrice(_deposited);
		uint PriceBorrowededAsset = orc.getAssetPrice(_borrowed);
		return BONE.mul(PriceDepositedAsset).div(PriceBorrowededAsset);
	}

	function crossCollateralizationRatio(address _deposited, address _borrowed, Safety _safety) internal view returns (uint) {
		if (_safety == Safety.UPPER) {
			return uint(int128(UpperCollateralizationRatio[_deposited]).mul(int128(UpperCollateralizationRatio[_borrowed]))).mul(BONE) >> 64;
		}
		return uint(int128(LowerCollateralizationRatio[_deposited]).mul(int128(LowerCollateralizationRatio[_borrowed]))).mul(BONE) >> 64;
	}

	function baseAssetAddresses(address _deposited, address _borrowed) internal view returns (address baseDepositedAsset, address baseBorrowedAsset) {
		organizer org = organizer(organizerAddress);
		baseDepositedAsset = UpperRateThreshold[_deposited] == 0 ? org.capitalHandlerToWrapper(_deposited) : _deposited;
		baseBorrowedAsset = org.capitalHandlerToWrapper(_borrowed);
	}


	function _amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) internal view returns (uint) {
		(address _baseSupplied, address _baseBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		return _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(getRateMultiplier_BaseRate(_assetBorrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW))
			.div(BONE)
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER))
			.div(_assetSupplied == _baseSupplied ? BONE : getRateMultiplier_BaseRate(_assetSupplied, _baseSupplied, RateAdjuster.UPPER_DEPOSIT))
			.div(BONE);
	}


	function _amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) internal view returns (uint) {
		(address _baseSupplied, address _baseBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		return _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(getRateMultiplier_BaseRate(_assetBorrowed, _baseBorrowed, RateAdjuster.LOW_BORROW))
			.div(BONE)
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW))
			.div(_assetSupplied == _baseSupplied ? BONE : getRateMultiplier_BaseRate(_assetSupplied, _baseSupplied, RateAdjuster.LOW_DEPOSIT))
			.div(BONE);
	}



	//-----------------------i-m-p-l-e-m-e-n-t---I-V-a-u-l-t-H-e-a-l-t-h--------------------------


	function satisfiesUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		return _amountSupplied > _amountSuppliedAtUpperLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	function satisfiesLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		return _amountSupplied > _amountSuppliedAtLowerLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	function amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) public override view returns (uint) {
		return _amountSuppliedAtUpperLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	function amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external override view returns (uint) {
		return _amountSuppliedAtLowerLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	function amountBorrowedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external override view returns (uint) {
		(address _baseSupplied, address _baseBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(_assetSupplied == _baseSupplied ? BONE : getRateMultiplier_BaseRate(_assetSupplied, _baseSupplied, RateAdjuster.UPPER_DEPOSIT));
		return term1
			.mul(BONE)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(BONE)
			.div(getRateMultiplier_BaseRate(_assetBorrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
	}

	function amountBorrowedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external override view returns (uint) {
		(address _baseSupplied, address _baseBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(_assetSupplied == _baseSupplied ? BONE : getRateMultiplier_BaseRate(_assetSupplied, _baseSupplied, RateAdjuster.LOW_DEPOSIT));
		return term1
			.mul(BONE)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(BONE)
			.div(getRateMultiplier_BaseRate(_assetBorrowed, _baseBorrowed, RateAdjuster.LOW_BORROW))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW));
	}

	function vaultWithstandsChange(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) public view override returns(bool) {

		(address _baseSupplied, address _baseBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed));
		_amountBorrowed = _amountBorrowed
			.mul(getRateMultiplier_Changed(_assetBorrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW, _borrowRateChange))
			.div(BONE);
		_amountBorrowed = _amountBorrowed
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER))
			.div(_assetSupplied == _baseSupplied ? BONE : getRateMultiplier_Changed(_assetSupplied, _baseSupplied, RateAdjuster.UPPER_DEPOSIT, _suppliedRateChange))
			.mul(_priceMultiplier)
			.div(BONE*TOTAL_BASIS_POINTS);

		return _amountBorrowed < _amountSupplied;
	}

	//---------f-u-n-c-t-i-o-n-s---t-o---b-e---c-a-l-l-e-d---v-i-a---d-e-l-e-g-a-t-e-c-a-l-l------

	//-----------------------a-d-m-i-n---o-p-e-r-a-t-i-o-n-s---------------------------
	function setCollateralizationRatios(address _underlyingAssetAddress, uint120 _upper, uint120 _lower) external onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _underlyingAssetAddress is not a capital handler contract
		require(organizer(organizerAddress).capitalHandlerToWrapper(_underlyingAssetAddress) == address(0));
		UpperCollateralizationRatio[_underlyingAssetAddress] = _upper;
		LowerCollateralizationRatio[_underlyingAssetAddress] = _lower;
	}

	function setRateThresholds(address _underlyingAssetAddress, uint120 _upper, uint120 _lower) external onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _underlyingAssetAddress is not a capital handler contract
		require(organizer(organizerAddress).capitalHandlerToWrapper(_underlyingAssetAddress) == address(0));
		UpperRateThreshold[_underlyingAssetAddress] = _upper;
		LowerRateThreshold[_underlyingAssetAddress] = _lower;
	}

	function setOrganizerAddress(address _organizerAddress) external onlyOwner {
		require(organizerAddress == address(0));
		organizerAddress = _organizerAddress;
	}

	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external onlyOwner {
		maximumShortInterest[_underlyingAssetAddress] = _maximumShortInterest;
	}
}

