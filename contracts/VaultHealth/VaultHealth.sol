pragma solidity >=0.6.0;
import "../organizer.sol";
import "../helpers/IZCBamm.sol";
import "../helpers/Ownable.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../oracle/interfaces/IOracleContainer.sol";


contract VaultHealth is IVaultHealth, Ownable {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	uint private constant SecondsPerYear = 31556926;

	uint private constant TOTAL_BASIS_POINTS = 10_000;

	int128 private constant ABDK_1 = 1<<64;

	/*
		the RateAdjuster enum holds information about how to change the APY
		when calculating required collateralisation ratios.

		UPPER means that you are checking the upper collateralisation limit
		LOWER means that you are checking the lower collateralisation limit

		DEPOSIT means that you are finding the rate multiplier for a ZCB that has been supplied to a vault
		BORROW means that you are finding the rate multiplier for a ZCB that has been borrowed from a vault

		BASE means that you are not adjusting the APY to find a collateralisation limit
		BASE means that you are finding the rate multiplier to get as best an approximation of market value
			of the ZCBs as possible
	*/
	enum RateAdjuster {
		UPPER_DEPOSIT,
		LOW_DEPOSIT,
		BASE,
		LOW_BORROW,
		UPPER_BORROW
	}

	/*
		the Safety enum holds information about which collateralsation limit is in question

		as you may have inferred
		UPPER means that the upper collateralisation ratio is in use
		LOWER means that the lower collateralisation ratio is in use
	*/
	enum Safety {
		UPPER,
		LOW
	}

	/*
		When a user deposits bonds we take the Maximum of the rate shown in the oracle +
		MIN_RATE_ADJUSTMENT and the rate shown in the oracle adjusted with the
		corresponding rate threshold as the rate for which collateralization requirements
		will be calculated

		When a user borrowes bonds we take the Maximum of the rate shown in the oracle -
		MIN_RATE_ADJUSTMENT and the rate shown in the oracle adjusted with the
		corresponding rate threshold as the rate for which collateralization requirements
		will be calculated
	*/
	int128 constant MIN_RATE_ADJUSTMENT = ABDK_1 / 100;

	/*
		The Collateralisation Ratio mappings hold information about the % which any vault
		containing a asset must be overcollateralised.

		For example if
		UpperCollateralizationRatio[_assetSupplied] == 1.0 and
		UpperCollateralizationRatio[_assetBorrowed] == 1.5

		the total overcollateralisation % required for the vault due to volatility of asset prices
		is (1.0 * 1.5 - 1.0) == 50% for the upper collateralization limit

		these mappings take in an underlying asset, they do not account for overcollateralisation
		required due to rate volatility

		When ZCBs are used in a vault to find the collateralization ratio due to underlying asset
		you must find UpperCollateralzationRatio[org.fixCapitalPoolToWrapper(_ZCBaddress)]

		In ABDK64.64 format
	*/
	mapping(address => uint120) public LowerCollateralizationRatio;

	mapping(address => uint120) public UpperCollateralizationRatio;


	/*
		Because rates are always over 1.0 (meaning the % notation of the rate is always positive)
		the rate thresholds refer to the % change in the rate minus 1.
		All rate thresholds must be above 1.0 as well,to get the resultant threshold adjusted rate for
		borrowing we find 1 + (rate - 1)/threshold
		to get the resultatn threshold adjusted rate for depositing we find
		1 + (rate - 1)*threshold
		For example if there is a rate treshold of 1.25 and the current rate for that asset is 
		3% the rate used when calculating borrow requirements for that asset will be
		(1.03-1) / 1.25 == 3% / 1.25 == 2.4%
		To calculate the rate for deposit calculations for that asset we would do the following
		(1.03-1) * 1.25 == 3% * 1.25 == 3.75%
	*/
	mapping(address => uint120) public LowerRateThreshold;

	mapping(address => uint120) public UpperRateThreshold;

	/*
		Set by contract owner this mapping shows the maximum amount of any underlying asset (at all durations combined)
		that may be shorted via the VaultFactory contract
	*/
	mapping(address => uint) public override maximumShortInterest;

	address organizerAddress;
	address oracleContainerAddress;

	constructor(address _oracleContainerAddress) public {
		oracleContainerAddress = _oracleContainerAddress;
	}

	/*
		@Description: get the amount of of years remaining to maturity for a specific FixCapitalPool
			in ABDK64.64 format
		
		@param address _fixCapitalPoolAddress: the fix capital pool for which to get the years remaining to maturity
			this param could alternatively be the address of a ZCB contract and the same effect would be achived
		@param address _baseAsset: is address of an IWrapper contract, we need this address to call lastUpdate
			to find the latest timestamp for which yield has been finalised

		@return int128: years to maturity in ABDK64.64 format
	*/
	function getYearsRemaining(address _fixCapitalPoolAddress, address _baseAsset) internal view returns (int128) {
		uint maturity = IFixCapitalPool(_fixCapitalPoolAddress).maturity();
		uint lastUpdate = IWrapper(_baseAsset).lastUpdate();
		return maturity > lastUpdate ? int128(((maturity - lastUpdate) << 64) / SecondsPerYear) : -1;
	}

	/*
		@Description: given a RateAdjuster find if it is for a deposited/supplied asset
	*/
	function isDeposited(RateAdjuster ra) internal pure returns(bool) {
		return ra == RateAdjuster.UPPER_DEPOSIT  || ra == RateAdjuster.LOW_DEPOSIT;
	}

	/*
		@Description: given a RateAdjuster find if it is for a borrowed asset
	*/
	function isBorrowed(RateAdjuster ra) internal pure returns(bool) {
		return ra == RateAdjuster.UPPER_BORROW || ra == RateAdjuster.LOW_BORROW;
	}

	/*
		@Description: given an underlying asset and rate adjuster find the rate multiplier
			the rate multiplier is multiplied by the APY to get the effective rate for collateralisation purposes

		@param address _underlyingAssetAddress: the address of the underlying asset for which to find the rate multiplier
			_underlyingAssetAddress is the key in the mapping
		@param RateAdjuster _rateAdjuster: the rate adjuster tells us which mapping to get the multiplier from

		@return int128 multiplier: the multiplier with which to multiply the APY fetched from the rate oracle
	*/
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

	/*
		@Description: fetch the implied rate of a specific FixCapitalPool

		@param address _fixCapitalPool: address of the FixCapitalPool in question

		@return int128: the APY in ABDK64.64 format
	*/
	function getAPYFromOracle(address _fixCapitalPoolAddress) internal view returns (int128) {
		return ZCBamm(organizer(organizerAddress).ZCBamms(_fixCapitalPoolAddress)).getAPYFromOracle();
	}

	/*
		@Description: get APY from oracle adjusted by a multiplier

		@param address _fixCapitalPool: address of the FixCapitalPool in question
		@param int128 _rateChange: multiplier with which to multiply APY
			ABDK64.64 format

		@param int128: APY of FixCapitalPool fetched from oracle and multiplied by a multiplier
	*/
	function getChangedAPYFromOracle(address _fixCapitalPoolAddress, int128 _rateChange) internal view returns (int128) {
		return getAPYFromOracle(_fixCapitalPoolAddress).sub(ABDK_1).mul(_rateChange).add(ABDK_1);
	}

	/*
		@Description: find multiplier for ZCB position for collateralisation purpouses
			this multiplier is to be multiplied with the value of an amount of underlying asset equal to the amount of ZCBs
			to find the value of the ZCBs

		@param address _fixCapitalPool: address of the FixCapitalPool in question
		@param address _underlyingAssetAddress: the underlying asset in question
		@param RateAdjuster _rateAdjuster: the adjuster for which to find the rate multiplier

		@return uint: rate multiplier
	*/
	function getRateMultiplier_BaseRate(address _fixCapitalPoolAddress, address _underlyingAssetAddress, RateAdjuster _rateAdjuster) internal view returns (uint) {
		return getRateMultiplier(_fixCapitalPoolAddress, _underlyingAssetAddress, _rateAdjuster, (1 ether));
	}

	/*
		@Description: find multiplier that discounts value of ZCBs now against face value of ZCBs.
			in other words return ValueNow/ValueAtMaturity
		
		@param address _fixCapitalPool: address of the FixCapitalPool in question
		@param address _underlyingAssetAddress: the underlying asset in question
		@param RateAdjuster _rateAdjuster: the adjuster for which to find the rate multiplier
		@param int128 _rateChange: a change multiplier, multiplied with APY to get changed APY
	*/
	function getRateMultiplier(address _fixCapitalPoolAddress, address _underlyingAssetAddress, RateAdjuster _rateAdjuster, int128 _rateChange) internal view returns (uint) {
		//ensure that we have been passed a ZCB address if not there is a rate multiplier of 1.0
		int128 yearsRemaining = getYearsRemaining(_fixCapitalPoolAddress, _underlyingAssetAddress);
		if (yearsRemaining <= 0) {
			if (IFixCapitalPool(_fixCapitalPoolAddress).inPayoutPhase()) {
				//account for nominal value accrual of ZCBs since maturity
				uint numerator = IWrapper(_underlyingAssetAddress).WrappedAmtToUnitAmt_RoundDown(1 ether);
				uint denominator = IFixCapitalPool(_fixCapitalPoolAddress).maturityConversionRate();
				return numerator.mul(1 ether).div(denominator);
			}
			else {
				return (1 ether);
			}
		}
		int128 startApy = _rateChange == (1 ether) ? getAPYFromOracle(_fixCapitalPoolAddress) : getChangedAPYFromOracle(_fixCapitalPoolAddress, _rateChange);
		int128 adjApy = startApy.sub(ABDK_1).mul(getRateThresholdMultiplier(_underlyingAssetAddress, _rateAdjuster)).add(ABDK_1);
		if (isDeposited(_rateAdjuster)) {
			int128 temp = startApy.add(MIN_RATE_ADJUSTMENT);
			adjApy = temp > adjApy ? temp : adjApy;
		}
		else if (isBorrowed(_rateAdjuster)) {
			int128 temp = startApy.sub(MIN_RATE_ADJUSTMENT);
			adjApy = temp < adjApy ? temp : adjApy;
		}
		if (adjApy <= ABDK_1) return (1 ether);
		/*
			rateMultiplier == 1 / ((adjApy)**yearsRemaining)
			rateMultiplier == 1 / (2**(log_2((adjApy)**yearsRemaining)))
			rateMultiplier == 1 / (2**(yearsRemaining*log_2((adjApy))))
			rateMultiplier == 2**(-1*yearsRemaining*log_2((adjApy)))
			rateMultiplier == adjApy.log_2().mul(yearsRemaining).neg().exp_2()
		*/
		int128 rateMultiplier = adjApy.log_2().mul(yearsRemaining).neg().exp_2();
		if (rateMultiplier >= ABDK_1) return (1 ether);
		//normalize by changing to 1 ether format
		return uint(rateMultiplier).mul(1 ether) >> 64;
	}

	/*
		@Description: find the price of the deposited asset denominated in the borrowed asset
			PriceOfDeposited/PriceOfBorrowed
			inflated by 1 ether

		@param address _deposited: the address of the asset supplied to the vault
		@param address _borrowed: the address of the asset borrowed from the vault
	*/
	function crossAssetPrice(address _deposited, address _borrowed) internal view returns(uint) {
		if (_deposited == _borrowed) {
			return (1 ether);
		}
		IOracleContainer orc = IOracleContainer(oracleContainerAddress);
		uint PriceDepositedAsset = orc.getAssetPrice(_deposited);
		uint PriceBorrowededAsset = orc.getAssetPrice(_borrowed);
		return uint(1 ether).mul(PriceDepositedAsset).div(PriceBorrowededAsset);
	}

	/*
		@Description: each asset has a collateralisation ratio which is due to its price volatility,
			each vault must be over collateralised by a factor of the collateralisation ratio of the borrowed asset * that of the supplied
			this function finds that over collateralisation ratio that must be maintained due to the volatility of an asset

		@param address _deposited: the address of the asset supplied to the vault
		@param address _borrowed: the address of the asset borrowed from the vault
		@param Safety _safety: gives information about which collateralisation ratio mapping to get the values from

		@return uint: cross collateralisation ratio between the asset deposited into the vault and the asset borrowed from the vault
	*/
	function crossCollateralizationRatio(address _deposited, address _borrowed, Safety _safety) internal view returns (uint) {
		if (_safety == Safety.UPPER) {
			return uint(int128(UpperCollateralizationRatio[_deposited]).mul(int128(UpperCollateralizationRatio[_borrowed]))).mul(1 ether) >> 64;
		}
		return uint(int128(LowerCollateralizationRatio[_deposited]).mul(int128(LowerCollateralizationRatio[_borrowed]))).mul(1 ether) >> 64;
	}

	/*
		@Description: if an asset is a ZCB find its wrapper asset address
			do this for both the asset supplied and the asset borrowed from the vault

		@param address _deposited: the address of the asset supplied to the vault
		@param address _borrowed: the address of the asset borrowed from the vault

		@return address baseDepositedAsset: the underlying wrapper for the collateral asset
		@return address baseBorrowedAsset: the underlying wrapper for the borrowed asset
		@return address chDeposited: the address of the FixCapitalPool corresponding to the collateral asset
			it is possible that there is no FixCapitalPool associated with the collateral asset, in this case
			this value will return as address(0)
		@return address chSupplied: the address of the FixCapitalPool corresponding to the borrowed asset
	*/
	function baseAssetAddresses(address _deposited, address _borrowed) internal view returns (
		address baseDepositedAsset,
		address baseBorrowedAsset,
		address chDeposited,
		address chBorrowed
	) {
		organizer org = organizer(organizerAddress);
		if (UpperRateThreshold[_deposited] == 0) {
			chDeposited = IZeroCouponBond(_deposited).FixCapitalPoolAddress();
			baseDepositedAsset = org.fixCapitalPoolToWrapper(chDeposited);
		}
		else {
			baseDepositedAsset = _deposited;
		}
		chBorrowed = IZeroCouponBond(_borrowed).FixCapitalPoolAddress();
		baseBorrowedAsset = org.fixCapitalPoolToWrapper(chBorrowed);
	}

	/*
		@Description: take 2 FixCapitalPool addresses and find their corresponding base asset addresses
	*/
	function bothFCPtoBaseAddresses(address _addr0, address _addr1) internal view returns (address baseAddr0, address baseAddr1) {
		organizer org = organizer(organizerAddress);
		baseAddr0 = org.fixCapitalPoolToWrapper(_addr0);
		baseAddr1 = org.fixCapitalPoolToWrapper(_addr1);
	}


	/*
		@Description: find the amount of supplied asset that is required for a vault stay above the upper collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return uint: the minimum amount of _assetSupplied that must be in the vault in order for the vault to stay above the
			upper collateralisation limit
	*/
	function _amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) internal view returns (uint) {
		(address _baseSupplied, address _baseBorrowed, address chSupplied, address chBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(getRateMultiplier_BaseRate(chBorrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW))
			.div(1 ether)
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
		return _amountBorrowed
			.div(_assetSupplied == _baseSupplied ? (1 ether) : getRateMultiplier_BaseRate(chSupplied, _baseSupplied, RateAdjuster.UPPER_DEPOSIT))
			.div(1 ether);
	}


	/*
		@Description: find the amount of supplied asset that is required for a vault stay above the lower collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return uint: the minimum amount of _assetSupplied that must be in the vault in order for the vault to stay above the
			lower collateralisation limit
	*/
	function _amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) internal view returns (uint) {
		(address _baseSupplied, address _baseBorrowed, address chSupplied, address chBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(getRateMultiplier_BaseRate(chBorrowed, _baseBorrowed, RateAdjuster.LOW_BORROW))
			.div(1 ether)
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW));
		return _amountBorrowed
			.div(_assetSupplied == _baseSupplied ? (1 ether) : getRateMultiplier_BaseRate(chSupplied, _baseSupplied, RateAdjuster.LOW_DEPOSIT))
			.div(1 ether);
	}


	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed from a vault without going under the
			upper collateralization limit

		@param address _FCPsupplied: the address of the FixCapitalPool instance for which a combination of YT & ZCB are being
			supplied to the vault
		@param address _FCPborrowed: the address of the FixCapitalPool instance for which ZCB is being borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond

		@return uint: the maximum amount of ZCB for FixCapitalPool _FCPborrowed for which the vault will not be forced below
			the upper collateralization limit
	*/
	function _YTvaultAmountBorrowedAtUpperLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) internal view returns (uint) {
		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);

		bool positiveBond = _amountBond >= 0;

		//if !positiveBond there are essentially 2 ZCBs being borrowed from the vault with _baseSupplied as the supplied asset
		//thus we change the rate adjuster to borrow if the "supplied" ZCB is negative
		uint ZCBvalue = uint(positiveBond ? _amountBond : -_amountBond)
			.mul(getRateMultiplier_BaseRate(_FCPsupplied, _baseSupplied, positiveBond ? RateAdjuster.UPPER_DEPOSIT : RateAdjuster.UPPER_BORROW))
			.div(1 ether);

		//after rate adjustments find the effective amount of the underlying asset which may be used in collateralisation calculation
		uint compositeSupplied = positiveBond ? _amountYield.add(ZCBvalue) : _amountYield.sub(ZCBvalue);

		return compositeSupplied
			.mul((1 ether)**2)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(1 ether)
			.div(getRateMultiplier_BaseRate(_FCPborrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed from a vault without going under the
			lower collateralization limit

		@param address _FCPsupplied: the address of the FixCapitalPool instance for which a combination of YT & ZCB are being
			supplied to the vault
		@param address _FCPborrowed: the address of the FixCapitalPool instance for which ZCB is being borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond

		@return uint: the maximum amount of ZCB for FixCapitalPool _FCPborrowed for which the vault will not be forced below
			the lower collateralization limit
	*/
	function _YTvaultAmountBorrowedAtLowerLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) internal view returns (uint) {
		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);

		bool positiveBond = _amountBond >= 0;

		//if !positiveBond there are essentially 2 ZCBs being borrowed from the vault with _baseSupplied as the supplied asset
		//thus we change the rate adjuster to borrow if the "supplied" ZCB is negative
		uint ZCBvalue = uint(positiveBond ? _amountBond : -_amountBond)
			.mul(getRateMultiplier_BaseRate(_FCPsupplied, _baseSupplied, positiveBond ? RateAdjuster.LOW_DEPOSIT : RateAdjuster.LOW_BORROW))
			.div(1 ether);

		//after rate adjustments find the effective amount of the underlying asset which may be used in collateralisation calculation
		uint compositeSupplied = positiveBond ? _amountYield.add(ZCBvalue) : _amountYield.sub(ZCBvalue);

		return compositeSupplied
			.mul((1 ether)**2)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(1 ether)
			.div(getRateMultiplier_BaseRate(_FCPborrowed, _baseBorrowed, RateAdjuster.LOW_BORROW))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW));
	}


	//-----------------------i-m-p-l-e-m-e-n-t---I-V-a-u-l-t-H-e-a-l-t-h--------------------------


	/*
		@Description: check if a vault is above the upper collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the upper collateralisation limit
			false otherwise
	*/
	function satisfiesUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		return _amountSupplied > _amountSuppliedAtUpperLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: check if a vault is above the lower collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the lower collateralisation limit
			false otherwise
	*/
	function satisfiesLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override view returns (bool) {
		return _amountSupplied > _amountSuppliedAtLowerLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: check if a YT vault is above the upper collateralisation limit

		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the upper collateralisation limit
			false otherwise
	*/
	function YTvaultSatisfiesUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external override view returns (bool) {
		return _amountBorrowed < _YTvaultAmountBorrowedAtUpperLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: check if a YT vault is above the lower collateralisation limit

		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the lower collateralisation limit
			false otherwise
	*/
	function YTvaultSatisfiesLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external override view returns (bool) {
		return _amountBorrowed < _YTvaultAmountBorrowedAtLowerLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: returns value from _amountSuppliedAtUpperLimit() externally
	*/
	function amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external override view returns (uint) {
		return _amountSuppliedAtUpperLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: returns value from _amountSuppliedAtLowerLimit() externally
	*/
	function amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external override view returns (uint) {
		return _amountSuppliedAtLowerLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed for a vault stay above the upper collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault

		@return uint: the maximum amount of borrowed asset that must be borrowed from a vault in order for the vault to stay above the
			upper collateralisation limit
	*/
	function amountBorrowedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external override view returns (uint) {
		(address _baseSupplied, address _baseBorrowed, address chSupplied, address chBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(_assetSupplied == _baseSupplied ? (1 ether) : getRateMultiplier_BaseRate(chSupplied, _baseSupplied, RateAdjuster.UPPER_DEPOSIT));
		return term1
			.mul(1 ether)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(1 ether)
			.div(getRateMultiplier_BaseRate(chBorrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed for a vault stay above the lower collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault

		@return uint: the maximum amount of borrowed asset that must be borrowed from a vault in order for the vault to stay above the
			lower collateralisation limit
	*/
	function amountBorrowedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external override view returns (uint) {
		(address _baseSupplied, address _baseBorrowed, address chSupplied, address chBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(_assetSupplied == _baseSupplied ? (1 ether) : getRateMultiplier_BaseRate(chSupplied, _baseSupplied, RateAdjuster.LOW_DEPOSIT));
		return term1
			.mul(1 ether)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(1 ether)
			.div(getRateMultiplier_BaseRate(chBorrowed, _baseBorrowed, RateAdjuster.LOW_BORROW))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW));
	}

	/*
		@Description: returns _YTvaultAmountBorrowedAtUpperLimit externally
	*/
	function YTvaultAmountBorrowedAtUpperLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) external view override returns (uint) {
		return _YTvaultAmountBorrowedAtUpperLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: returns _YTvaultAmountBorrowedAtLowerLimit externally
	*/
	function YTvaultAmountBorrowedAtLowerLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) external view override returns (uint) {
		return _YTvaultAmountBorrowedAtLowerLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: ensure that a vault will not be sent into liquidation zone if price changes a specified amount
			and rates change by a multiplier

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault
		@param uint _priceMultiplier: the multiplier by which cross asset price of deposit versus borrowed asset changes
			inflated by 1 ether
		@param int128 _suppliedRateChange: the multiplier by which the rate of the supplied asset will change
			in ABDK64.64 format
		@param int128 _borrowRateChange: the multiplier by which the rate of the borrowed asset will change
			in ABDK64.64 format

		@return bool: returns true if vault will stay above liquidation zone
			false otherwise
	*/
	function vaultWithstandsChange(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) public view override returns(bool) {

		(address _baseSupplied, address _baseBorrowed, address chSupplied, address chBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed));
		_amountBorrowed = _amountBorrowed
			.mul(getRateMultiplier(chBorrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW, _borrowRateChange))
			.div(1 ether);
		_amountBorrowed = _amountBorrowed
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
		_amountBorrowed = _amountBorrowed
			.div(_assetSupplied == _baseSupplied ? (1 ether) : getRateMultiplier(chSupplied, _baseSupplied, RateAdjuster.UPPER_DEPOSIT, _suppliedRateChange));
		_amountBorrowed = _amountBorrowed
			.mul(_priceMultiplier)
			.div((1 ether)*TOTAL_BASIS_POINTS);

		return _amountBorrowed < _amountSupplied;
	}

	/*
		@Description: ensure that a vault will not be sent into liquidation zone if price changes a specified amount
			and rates change by a multiplier

		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault
		@param uint _priceMultiplier: the multiplier by which cross asset price of deposit versus borrowed asset changes
			inflated by 1 ether
		@param int128 _suppliedRateChange: the multiplier by which the rate of the supplied asset will change
			in ABDK64.64 format
		@param int128 _borrowRateChange: the multiplier by which the rate of the borrowed asset will change
			in ABDK64.64 format

		@return bool: returns true if vault will stay above liquidation zone
			false otherwise
	*/
	function YTvaultWithstandsChange(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external view override returns (bool) {
		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);

		//after rate adjustments find the effective amount of the underlying asset which may be used in collateralisation calculation
		uint compositeSupplied;
		{
			bool positiveBond = _amountBond >= 0;

			//if !positiveBond there are essentially 2 ZCBs being borrowed from the vault with _baseSupplied as the supplied asset
			//thus we change the rate adjuster to borrow if the "supplied" ZCB is negative
			uint ZCBvalue = uint(positiveBond ? _amountBond : -_amountBond)
				.mul(getRateMultiplier(_FCPsupplied, _baseSupplied, positiveBond ? RateAdjuster.UPPER_DEPOSIT : RateAdjuster.UPPER_BORROW, _suppliedRateChange));

			compositeSupplied = positiveBond ? _amountYield.add(ZCBvalue) : _amountYield.sub(ZCBvalue);
		}

		compositeSupplied = compositeSupplied
			.mul((1 ether)**2)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul((1 ether)*TOTAL_BASIS_POINTS)
			.div(_priceMultiplier);
		compositeSupplied = compositeSupplied
			.div(getRateMultiplier(_FCPborrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW, _borrowRateChange))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
		return compositeSupplied > _amountBorrowed;
	}

	//-----------------------a-d-m-i-n---o-p-e-r-a-t-i-o-n-s---------------------------

	/*
		@Description: admin may set the values in the CollateralizationRatio mappings
		
		@param address _underlyingAssetAddress: the asset for which to set the a collateralisation ratio
		@param uint128 _upper: the upper collateralisation ratio
			in ABDK64.64 format
		@param uint128 _lower: the upper collateralisation ratio
			in ABDK64.64 format
	*/
	function setCollateralizationRatios(address _underlyingAssetAddress, uint120 _upper, uint120 _lower) external onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _underlyingAssetAddress is not a fix capital pool contract
		require(organizer(organizerAddress).fixCapitalPoolToWrapper(_underlyingAssetAddress) == address(0));
		UpperCollateralizationRatio[_underlyingAssetAddress] = _upper;
		LowerCollateralizationRatio[_underlyingAssetAddress] = _lower;
	}

	/*
		@Description: admin may set the vaules in the RateThreshold mappings

		@param address _underlyingAssetAddress: the asset for which to set the a collateralisation ratio
		@param uint120 _upper: the upper rate threshold multiplier
			in ABDK64.64 format
		@param uint120 _lower: the lower rate threshold multiplier
			in ABDK64.64 format
	*/
	function setRateThresholds(address _underlyingAssetAddress, uint120 _upper, uint120 _lower) external onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _underlyingAssetAddress is not a fix capital pool contract
		require(organizer(organizerAddress).fixCapitalPoolToWrapper(_underlyingAssetAddress) == address(0));
		UpperRateThreshold[_underlyingAssetAddress] = _upper;
		LowerRateThreshold[_underlyingAssetAddress] = _lower;
	}

	/*
		@Description: admin may set the organizer contract address
	*/
	function setOrganizerAddress(address _organizerAddress) external onlyOwner {
		require(organizerAddress == address(0));
		organizerAddress = _organizerAddress;
	}

	/*
		@Description: admin may set the maximum short interest for bonds of any maturity for a specific asset

		@param address _underlyingAssetAddress: the address of the underlying asset for which to set a short interest cap
		@param uint _maximumShortInterest: the maximum amount of units of the underlying asset that may sold short via ZCBs
	*/
	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external onlyOwner {
		maximumShortInterest[_underlyingAssetAddress] = _maximumShortInterest;
	}
}

