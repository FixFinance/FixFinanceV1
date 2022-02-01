// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../helpers/Ownable.sol";
import "../interfaces/IOrderbookExchange.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IOrganizer.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../oracle/interfaces/IOracleContainer.sol";
import "./VaultHealthData.sol";


contract VaultHealth is IVaultHealth, VaultHealthData {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

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
			multiplier = ABDK_1.div(int128(upperRateThreshold[_underlyingAssetAddress]));
		}
		else if (_rateAdjuster == RateAdjuster.LOW_BORROW) {
			multiplier = ABDK_1.div(int128(lowerRateThreshold[_underlyingAssetAddress]));
		}
		else if (_rateAdjuster == RateAdjuster.UPPER_DEPOSIT) {
			multiplier = ABDK_1.mul(int128(upperRateThreshold[_underlyingAssetAddress]));
		}
		else if (_rateAdjuster == RateAdjuster.LOW_DEPOSIT) {
			multiplier = ABDK_1.mul(int128(lowerRateThreshold[_underlyingAssetAddress]));
		}
		else {
			multiplier = ABDK_1;
		}

	}

	/*
		@Description: find the total implied yield between now and maturity for a given FCP
			we use this function rather than finding apy and exponentiating to the number of years because we can
			avoid 1 call to log and 1 call to exp when APY is calculated
			instead we find the rate based on the anchor time period and exponetiate to the power of the number
			of anchor time periods to maturity

		@param address _fixCapitalPoolAddress: address of the FCP for which to find total yield until maturity

		@return int128: the market implied total yield of the FCP up to maturity, fetched from oracle
	*/
	function getYieldToMaturityFromOracle(address _fixCapitalPoolAddress) internal view returns (int128) {
		uint ytm = IOrderbookExchange(IOrganizer(organizerAddress).Orderbooks(_fixCapitalPoolAddress)).impliedYieldToMaturity();
		uint converted = ytm.mul(1**64).div(1 ether);
		require(converted <= uint(type(int128).max));
		return int128(converted);
	}

	/*
		@Description: fetch the implied rate of a specific FixCapitalPool

		@param address _fixCapitalPool: address of the FixCapitalPool in question

		@return int128: the APY in ABDK64.64 format
	*/
	function getAPYFromOracle(address _fixCapitalPoolAddress) internal view returns (int128) {
		return IOrderbookExchange(IOrganizer(organizerAddress).Orderbooks(_fixCapitalPoolAddress)).getAPYFromOracle();
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
		return getRateMultiplier(_fixCapitalPoolAddress, _underlyingAssetAddress, _rateAdjuster, ABDK_1);
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
			return getYieldSinceMaturity(_fixCapitalPoolAddress, _underlyingAssetAddress);
		}
		return rateToRateMultiplier(getAPYFromOracle(_fixCapitalPoolAddress), yearsRemaining, _underlyingAssetAddress, _rateAdjuster, _rateChange);
	}


	/*
		@Description: given a startingAPY for a FCP fetched from the oracle and some other info get a rate multiplier

		@param int128 _startAPY: the apy given by the oracle
		@param int128: _yearsRemaining: the time in years until the FCP matures
		@param address _baseWrapperAddress: the wrapper corresponding to the FCP
		@param RateAdjuster _rateAdjuster: the adjuster for which to find the rate multiplier
		@param int128 _rateChange: a change multiplier, multiplied with APY to get changed APY
	*/
	function rateToRateMultiplier(
		int128 _startAPY,
		int128 _yearsRemaining,
		address _baseWrapperAddress,
		RateAdjuster _rateAdjuster,
		int128 _rateChange
	) internal view returns (uint) {
		_startAPY = _startAPY.sub(ABDK_1).mul(_rateChange).add(ABDK_1);
		int128 adjApy = _startAPY.sub(ABDK_1).mul(getRateThresholdMultiplier(_baseWrapperAddress, _rateAdjuster)).add(ABDK_1);
		if (isDeposited(_rateAdjuster)) {
			int128 temp = _startAPY
				.add(int128(
					_rateAdjuster == RateAdjuster.UPPER_DEPOSIT ?
						upperMinimumRateAdjustment[_baseWrapperAddress]
							:
						lowerMinimumRateAdjustment[_baseWrapperAddress]
				));
			adjApy = temp > adjApy ? temp : adjApy;
		}
		else if (isBorrowed(_rateAdjuster)) {
			int128 temp = _startAPY
				.sub(int128(
					_rateAdjuster == RateAdjuster.UPPER_BORROW ?
						upperMinimumRateAdjustment[_baseWrapperAddress]
							:
						lowerMinimumRateAdjustment[_baseWrapperAddress]
				));
			adjApy = temp < adjApy ? temp : adjApy;
		}
		if (adjApy <= ABDK_1) return (1 ether);
		/*
			rateMultiplier == 1 / ((adjApy)**_yearsRemaining)
			rateMultiplier == ((adjApy)**-_yearsRemaining)
		*/
		int128 rateMultiplier = BigMath.Pow(adjApy, _yearsRemaining.neg());
		if (rateMultiplier >= ABDK_1) return (1 ether);
		//normalize by changing to 1 ether format
		return uint(rateMultiplier).mul(1 ether) >> 64;
	}

	/*
		@Description: given a matured FCP find the appreciation in unit terms of the ZCBs since maturity

		@param address _fixCapitalPoolAddress: the address of the FCP contract for which to find the yield since maturity
		@param address _underlyingAssetAddress: the wrapper corresponding to the FCP

		@return uint: the yield inflated by (1 ether) of ZCBs corresponding to the FCP since maturity
	*/
	function getYieldSinceMaturity(address _fixCapitalPoolAddress, address _underlyingAssetAddress) internal view returns (uint) {
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

	/*
		@Description: given two FCPs of the same base wrapper find the implied market rate between the maturities of the FCPs

		@param address _supplied: the address of the FCP for which ZCB &/ YT are being provided as collateral
		@param address _borrowed: the address of the FCP for which ZCB is being borrowed
		@param int128 _ytmSupplied: years til maturity (ytm) for the supplied FCP, ABDK format
		@param int128 _ytmBorrowed: years til maturity (ytm) for the borrowed FCP, ABDK format

		@return int128 spreadAPY: the implied matket rate for the time spread between the two maturities, ABDK format
		@return int128 spreadTime: the magnitude in years of the time between the two maturities, ABDK format
	*/
	function impliedAPYBetweenMaturities(address _supplied, address _borrowed, int128 _ytmSupplied, int128 _ytmBorrowed) internal view returns (int128 spreadAPY, int128 spreadTime) {
		int128 totalYieldSupplied = getYieldToMaturityFromOracle(_supplied);
		int128 totalYieldBorrowed = getYieldToMaturityFromOracle(_borrowed);
		int128 yieldSpread;
		if (_ytmSupplied > _ytmBorrowed) {
			spreadTime = _ytmSupplied.sub(_ytmBorrowed);
			if (totalYieldBorrowed  >= totalYieldSupplied) {
				/*
					there is an inefficiency in the market that says there is negative yield between maturities
					which is impossible so we override it and say that there is no yield between maturities
				*/
				return (ABDK_1, spreadTime);
			}
			yieldSpread = totalYieldSupplied.div(totalYieldBorrowed);
		}
		else {
			spreadTime = _ytmBorrowed.sub(_ytmSupplied);
			if (totalYieldBorrowed <= totalYieldSupplied) {
				/*
					there is an inefficiency in the market that says there is negative yield between maturities
					which is impossible so we override it and say that there is no yield between maturities
				*/
				return (ABDK_1, spreadTime);
			}
			yieldSpread = totalYieldBorrowed.div(totalYieldSupplied);
		}
		/*
			yieldSpread == spreadAPY**spreadTime
			log(yieldSpread) == spreadTime*log(spreadAPY)
			log(yieldSpread)/spreadTime == log(spreadAPY)
			spreadAPY == exp(log(yieldSpread)/spreadTime)
		*/
		spreadAPY = yieldSpread.log_2().div(spreadTime).exp_2();
	}


	/*
		@Description: given both the supplied and borrowed assets find the composite rate multiplier for the vault

		@param bool _positiveSupplied: true if and only if a positve number of ZCB corresponding to the supplied FCP has been supplied
		@param bool _upperSafety: true if the safety level for which to calculate the rate multiplier is Safety.UPPER
			false otherwise
		@param address _supplied: the asset or FCP that is being supplied as collateral to the vault
		@param address _baseSupplied: the wrapper corresponding to the asset that has been supplied
		@param address _borrowed: the address of the FCP at which ZCB is being borrowed
		@param address _baseBorrowed: the wrapper corresponding to the borrowed FCP
		@param int128 _suppliedRateChange: a change multiplier, multiplied with the APY of the supplied
			to get changed APY for the supplied
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed

		@return uint: the combined rate multiplier given the supplied asset and the borrowed asset
		@return bool: true if: supplied+borrowed assets are both zcbs on the same wrapper asset and
				the maturity of the supplied is before the maturity of the borrowed,
			false otherwise
	*/
	function combinedRateMultipliers(
		bool _positiveSupplied,
		bool _upperSafety,
		address _supplied,
		address _baseSupplied,
		address _borrowed,
		address _baseBorrowed,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) internal view returns (uint, bool) {
		uint suppliedMultiplier;
		uint borrowedMultiplier;
		if (_baseSupplied == _baseBorrowed && _positiveSupplied) {
			require(_supplied != _borrowed);
			if (_supplied != _baseSupplied) { //supplied is zcb
				int128 ytmSupplied = getYearsRemaining(_supplied, _baseSupplied);
				if (ytmSupplied > 0) { //supplied zcb has yet to reach maturity
					//find implied market rate between maturity dates and calculate
					bool _ups = _upperSafety; //prevent stack too deep
					int128 ytmBorrowed = getYearsRemaining(_borrowed, _baseBorrowed);
					(int128 spreadAPY, int128 spreadTime) = impliedAPYBetweenMaturities(_supplied, _borrowed, ytmSupplied, ytmBorrowed);
					address _bs = _baseSupplied; //prevent stack too deep
					if (ytmBorrowed > ytmSupplied) {
						int128 src = _suppliedRateChange; // prevent stack too deep
						return (rateToRateMultiplier(spreadAPY, spreadTime, _bs, (_ups ? RateAdjuster.UPPER_BORROW : RateAdjuster.LOW_BORROW), src), true);
					}
					else {
						int128 brc = _borrowedRateChange; // prevent stack too deep
						uint rm = rateToRateMultiplier(spreadAPY, spreadTime, _bs, (_ups ? RateAdjuster.UPPER_DEPOSIT : RateAdjuster.LOW_DEPOSIT), brc);
						return (uint((1 ether)**2).div(rm), false);
					}
				}
				else { //supplied zcb has matured
					suppliedMultiplier = getYieldSinceMaturity(_supplied, _baseSupplied);
				}
			}
			else { //supplied is a wrapped asset
				suppliedMultiplier = (1 ether);
			}
			borrowedMultiplier = getRateMultiplier(_borrowed, _baseBorrowed, (_upperSafety ? RateAdjuster.UPPER_BORROW : RateAdjuster.LOW_BORROW) , _borrowedRateChange);
		}
		else { //base assets are different or supplied is negative, do not calculate time spread
			if (_supplied != _baseSupplied) { //supplied is zcb
				RateAdjuster raSupplied = (_upperSafety ?
					(_positiveSupplied ? RateAdjuster.UPPER_DEPOSIT : RateAdjuster.UPPER_BORROW)
						:
					(_positiveSupplied ? RateAdjuster.LOW_DEPOSIT : RateAdjuster.LOW_BORROW));
				suppliedMultiplier = getRateMultiplier(_supplied, _baseSupplied, raSupplied , _suppliedRateChange);
			}
			else {
				suppliedMultiplier = (1 ether);
			}
			RateAdjuster raBorrowed = (_upperSafety ? RateAdjuster.UPPER_BORROW : RateAdjuster.LOW_BORROW);
			borrowedMultiplier = getRateMultiplier(_borrowed, _baseBorrowed, raBorrowed , _borrowedRateChange);
		}
		return (suppliedMultiplier.mul(1 ether).div(borrowedMultiplier), false);
	}

	/*
		@Description: return only the uint value that is returned by combiendRateMultipliers
	*/
	function combinedRateMultipliers_onlyMultiplier(
		bool _positiveSupplied,
		bool _upperSafety,
		address _supplied,
		address _baseSupplied,
		address _borrowed,
		address _baseBorrowed,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) internal view returns (uint multiplier) {
		(multiplier, ) = combinedRateMultipliers(
			_positiveSupplied,
			_upperSafety,
			_supplied,
			_baseSupplied,
			_borrowed,
			_baseBorrowed,
			_suppliedRateChange,
			_borrowedRateChange
		);
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
		if (_deposited == _borrowed) {
			return (1 ether);
		}
		if (_safety == Safety.UPPER) {
			return uint(int128(upperCollateralizationRatio[_deposited]).mul(int128(upperCollateralizationRatio[_borrowed]))).mul(1 ether) >> 64;
		}
		return uint(int128(lowerCollateralizationRatio[_deposited]).mul(int128(lowerCollateralizationRatio[_borrowed]))).mul(1 ether) >> 64;
	}

	/*
		@Description: if an asset is a ZCB find its wrapper asset address
			do this for both the asset supplied and the asset borrowed from the vault

		@param address _deposited: the address of the asset supplied to the vault
		@param address _borrowed: the address of the asset borrowed from the vault

		@return address baseDepositedAsset: the underlying wrapper for the collateral asset
		@return address baseBorrowedAsset: the underlying wrapper for the borrowed asset
		@return address fcpDeposited: the address of the FixCapitalPool corresponding to the collateral asset
			it is possible that there is no FixCapitalPool associated with the collateral asset, in this case
			this value will return as address(0)
		@return address fcpSupplied: the address of the FixCapitalPool corresponding to the borrowed asset
	*/
	function baseAssetAddresses(address _deposited, address _borrowed) internal view returns (
		address baseDepositedAsset,
		address baseBorrowedAsset,
		address fcpDeposited,
		address fcpBorrowed
	) {
		IOrganizer org = IOrganizer(organizerAddress);
		if (upperRateThreshold[_deposited] == 0) { //deposited is ZCB
			fcpDeposited = IZeroCouponBond(_deposited).FixCapitalPoolAddress();
			baseDepositedAsset = org.fixCapitalPoolToWrapper(fcpDeposited);
		}
		else {
			fcpDeposited = _deposited;
			baseDepositedAsset = _deposited;
		}
		fcpBorrowed = IZeroCouponBond(_borrowed).FixCapitalPoolAddress();
		baseBorrowedAsset = org.fixCapitalPoolToWrapper(fcpBorrowed);
	}

	/*
		@Description: take 2 FixCapitalPool addresses and find their corresponding base asset addresses
	*/
	function bothFCPtoBaseAddresses(address _addr0, address _addr1) internal view returns (address baseAddr0, address baseAddr1) {
		IOrganizer org = IOrganizer(organizerAddress);
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
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER))
			.div(1 ether);
		return _amountBorrowed
			.div(combinedRateMultipliers_onlyMultiplier(true, true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));
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
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW))
			.div(1 ether);
		return _amountBorrowed
			.div(combinedRateMultipliers_onlyMultiplier(true, false, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));
	}

	/*
		@Description: find the maximum amount borrowed for a YT vault at the upper limit
			this function handles the case where the YT vault is not based on a time/rate spread
			this means that either the _baseSupplied != _baseBorrowed || _amountBond <= 0 || _FCPsupplied is past maturity

		@param address _FCPsupplied: the FCP corresponding to the YT vault's collateral
		@param address _baseSupplied: the wrapper corresponding to _FCPsupplied
		@param address _FCPborrowed: the FCP corresponding to the ZCB of the YT vault's debt
		@param address _baseBorrowed: the wrapper corresponding to _FCPborrowed
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			if _amountYield is unit amounts of collateral in the underlying, add _amountBond to _amountYield to get the amt of ZCB collateral
			amtZCB - amtYT == _amountBond
		@param int128 _suppliedRateChange: a change multiplier, multiplied with the APY of the supplied
			to get changed APY for the supplied
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed
	*/
	function YTvaultAmtBorrowedUL_0(
		address _FCPsupplied,
		address _baseSupplied,
		address _FCPborrowed,
		address _baseBorrowed,
		uint _amountYield,
		int _amountBond,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) internal view returns (uint) {
		bool positiveBond = _amountBond >= 0;

		//if !positiveBond there are essentially 2 ZCBs being borrowed from the vault with _baseSupplied as the supplied asset
		//thus we change the rate adjuster to borrow if the "supplied" ZCB is negative
		uint ZCBvalue = uint(positiveBond ? _amountBond : -_amountBond)
			.mul(getRateMultiplier(_FCPsupplied, _baseSupplied, positiveBond ? RateAdjuster.UPPER_DEPOSIT : RateAdjuster.UPPER_BORROW, _suppliedRateChange))
			.div(1 ether);

		//after rate adjustments find the effective amount of the underlying asset which may be used in collateralisation calculation
		uint compositeSupplied = positiveBond ? _amountYield.add(ZCBvalue) : _amountYield.sub(ZCBvalue);

		//wierd hack to prevent stack too deep
		compositeSupplied = compositeSupplied
			.mul((1 ether)**2)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed));
		return compositeSupplied
			.mul(1 ether)
			.div(getRateMultiplier(_FCPborrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW, _borrowedRateChange))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
	}

	/*
		@Description: find the maximum amount borrowed for a YT vault at the upper limit
			this function handles the case where the YT vault is based on a time/rate spread
			this means that _baseSupplied == _baseBorrowed && _amountBond > 0 && _FCPsupplied is not past maturity

		@param address _FCPsupplied: the FCP corresponding to the YT vault's collateral
		@param address _baseSupplied: the wrapper corresponding to _FCPsupplied
		@param address _FCPborrowed: the FCP corresponding to the ZCB of the YT vault's debt
		@param address _baseBorrowed: the wrapper corresponding to _FCPborrowed
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			if _amountYield is unit amounts of collateral in the underlying, add _amountBond to _amountYield to get the amt of ZCB collateral
			amtZCB - amtYT == _amountBond
		@param int128 _suppliedRateChange: a change multiplier, multiplied with the APY of the supplied
			to get changed APY for the supplied
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed
	*/
	function YTvaultAmtBorrowedUL_1(
		address _FCPsupplied,
		address _baseSupplied,
		address _FCPborrowed,
		address _baseBorrowed,
		uint _amountYield,
		int _amountBond,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) internal view returns (uint) {
		require(_amountBond > 0);
		uint maxBorrowAgainstYield = _amountYield
			.mul((1 ether)**2)
			.div(getRateMultiplier(_FCPborrowed, _baseBorrowed, RateAdjuster.UPPER_BORROW, _borrowedRateChange));
		(uint rmSpread, bool flip) = combinedRateMultipliers(true, true, _FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _suppliedRateChange, _borrowedRateChange);
		uint maxBorrowAgainstBond;
		if (flip) {
			maxBorrowAgainstBond = uint(_amountBond)
				.mul((1 ether)**2)
				.div(rmSpread);
		}
		else {
			maxBorrowAgainstBond = uint(_amountBond)
				.mul(rmSpread);
		}

		return (maxBorrowAgainstYield + maxBorrowAgainstBond).div(1 ether);
	}

	/*
		@Description: find the maximum amount borrowed for a YT vault at the upper limit
			this function handles the case where the FCP of the assets supplied to the YT vault
			is the same FCP for which ZCB is being borrowed from the vault

		@param address _FCP: the FCP corresponding to the supplied & borrowed assets
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			if _amountYield is unit amounts of collateral in the underlying, add _amountBond to _amountYield to get the amt of ZCB collateral
			amtZCB - amtYT == _amountBond
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed
	*/
	function YTvaultAmtBorrowedUL_2(
		address _FCP,
		uint _amountYield,
		int _amountBond,
		int128 _borrowedRateChange
	) internal view returns (uint) {
		bool positiveBond = _amountBond > 0;
		address base = IOrganizer(organizerAddress).fixCapitalPoolToWrapper(_FCP);
		uint totalToBorrowAgainst  = _amountYield
			.mul(1 ether)
			.div(getRateMultiplier(_FCP, base, RateAdjuster.UPPER_BORROW, _borrowedRateChange));
		return positiveBond ? totalToBorrowAgainst.add(uint(_amountBond)) : totalToBorrowAgainst.sub(uint(-_amountBond));
	}

	/*
		@Description: find the maximum amount borrowed for a YT vault at the lower limit
			this function handles the case where the YT vault is not based on a time/rate spread
			this means that either the _baseSupplied != _baseBorrowed || _amountBond <= 0 || _FCPsupplied is past maturity

		@param address _FCPsupplied: the FCP corresponding to the YT vault's collateral
		@param address _baseSupplied: the wrapper corresponding to _FCPsupplied
		@param address _FCPborrowed: the FCP corresponding to the ZCB of the YT vault's debt
		@param address _baseBorrowed: the wrapper corresponding to _FCPborrowed
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			if _amountYield is unit amounts of collateral in the underlying, add _amountBond to _amountYield to get the amt of ZCB collateral
			amtZCB - amtYT == _amountBond
		@param int128 _suppliedRateChange: a change multiplier, multiplied with the APY of the supplied
			to get changed APY for the supplied
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed
	*/
	function YTvaultAmtBorrowedLL_0(
		address _FCPsupplied,
		address _baseSupplied,
		address _FCPborrowed,
		address _baseBorrowed,
		uint _amountYield,
		int _amountBond,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) internal view returns (uint) {
		bool positiveBond = _amountBond >= 0;

		//if !positiveBond there are essentially 2 ZCBs being borrowed from the vault with _baseSupplied as the supplied asset
		//thus we change the rate adjuster to borrow if the "supplied" ZCB is negative
		uint ZCBvalue = uint(positiveBond ? _amountBond : -_amountBond)
			.mul(getRateMultiplier(_FCPsupplied, _baseSupplied, positiveBond ? RateAdjuster.LOW_DEPOSIT : RateAdjuster.LOW_BORROW, _suppliedRateChange))
			.div(1 ether);

		//after rate adjustments find the effective amount of the underlying asset which may be used in collateralisation calculation
		uint compositeSupplied = positiveBond ? _amountYield.add(ZCBvalue) : _amountYield.sub(ZCBvalue);

		//wierd hack to prevent stack too deep
		compositeSupplied = compositeSupplied
			.mul((1 ether)**2)
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed));
		return compositeSupplied
			.mul(1 ether)
			.div(getRateMultiplier(_FCPborrowed, _baseBorrowed, RateAdjuster.LOW_BORROW, _borrowedRateChange))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW));
	}

	/*
		@Description: find the maximum amount borrowed for a YT vault at the lower limit
			this function handles the case where the YT vault is based on a time/rate spread
			this means that _baseSupplied == _baseBorrowed && _amountBond > 0 && _FCPsupplied is not past maturity

		@param address _FCPsupplied: the FCP corresponding to the YT vault's collateral
		@param address _baseSupplied: the wrapper corresponding to _FCPsupplied
		@param address _FCPborrowed: the FCP corresponding to the ZCB of the YT vault's debt
		@param address _baseBorrowed: the wrapper corresponding to _FCPborrowed
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			if _amountYield is unit amounts of collateral in the underlying, add _amountBond to _amountYield to get the amt of ZCB collateral
			amtZCB - amtYT == _amountBond
		@param int128 _suppliedRateChange: a change multiplier, multiplied with the APY of the supplied
			to get changed APY for the supplied
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed
	*/
	function YTvaultAmtBorrowedLL_1(
		address _FCPsupplied,
		address _baseSupplied,
		address _FCPborrowed,
		address _baseBorrowed,
		uint _amountYield,
		int _amountBond,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) internal view returns (uint) {
		require(_amountBond > 0);
		uint maxBorrowAgainstYield = _amountYield
			.mul((1 ether)**2)
			.div(getRateMultiplier(_FCPborrowed, _baseBorrowed, RateAdjuster.LOW_BORROW, _borrowedRateChange));
		(uint rmSpread, bool flip) = combinedRateMultipliers(true, false, _FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _suppliedRateChange, _borrowedRateChange);
		uint maxBorrowAgainstBond;
		if (flip) {
			maxBorrowAgainstBond = uint(_amountBond)
				.mul((1 ether)**2)
				.div(rmSpread);
		}
		else {
			maxBorrowAgainstBond = uint(_amountBond)
				.mul(rmSpread);
		}

		return (maxBorrowAgainstYield + maxBorrowAgainstBond).div(1 ether);
	}

	/*
		@Description: find the maximum amount borrowed for a YT vault at the upper limit
			this function handles the case where the FCP of the assets supplied to the YT vault
			is the same FCP for which ZCB is being borrowed from the vault

		@param address _FCP: the FCP corresponding to the supplied & borrowed assets
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			if _amountYield is unit amounts of collateral in the underlying, add _amountBond to _amountYield to get the amt of ZCB collateral
			amtZCB - amtYT == _amountBond
		@param int128 _borrowedRateChange: a change multiplier, multiplied with the APY of the borrowed
			to get changed APY for the borrowed
	*/
	function YTvaultAmtBorrowedLL_2(
		address _FCP,
		uint _amountYield,
		int _amountBond,
		int128 _borrowedRateChange
	) internal view returns (uint) {
		bool positiveBond = _amountBond > 0;
		address base = IOrganizer(organizerAddress).fixCapitalPoolToWrapper(_FCP);
		uint totalToBorrowAgainst  = _amountYield
			.mul(1 ether)
			.div(getRateMultiplier(_FCP, base, RateAdjuster.LOW_BORROW, _borrowedRateChange));
		return positiveBond ? totalToBorrowAgainst.add(uint(_amountBond)) : totalToBorrowAgainst.sub(uint(-_amountBond));
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
		if (_FCPsupplied == _FCPborrowed) {
			return YTvaultAmtBorrowedUL_2(_FCPsupplied, _amountYield, _amountBond, ABDK_1);
		}

		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);

		bool positiveBond = _amountBond > 0;
		if (positiveBond && _baseSupplied == _baseBorrowed && getYearsRemaining(_FCPsupplied, _baseSupplied) > 0) {
			return YTvaultAmtBorrowedUL_1(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, ABDK_1, ABDK_1);
		}
		else {
			return YTvaultAmtBorrowedUL_0(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, ABDK_1, ABDK_1);
		}
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
		if (_FCPsupplied == _FCPborrowed) {
			return YTvaultAmtBorrowedLL_2(_FCPsupplied, _amountYield, _amountBond, ABDK_1);
		}

		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);

		bool positiveBond = _amountBond > 0;
		if (positiveBond && _baseSupplied == _baseBorrowed && getYearsRemaining(_FCPsupplied, _baseSupplied) > 0) {
			return YTvaultAmtBorrowedLL_1(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, ABDK_1, ABDK_1);
		}
		else {
			return YTvaultAmtBorrowedLL_0(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, ABDK_1, ABDK_1);
		}
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
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(1 ether)
			.mul(combinedRateMultipliers_onlyMultiplier(true, true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));
		return term1
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
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
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(1 ether)
			.mul(combinedRateMultipliers_onlyMultiplier(true, false, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));
		return term1
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
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

		@param bool _reqSameBase: if true require that base wrapper of supplied and borrowed are the same
		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault
		@param uint _priceMultiplier: the multiplier by which cross asset price of deposit versus borrowed asset changes
			inflated by TOTAL_BASIS_POINTS
		@param int128 _suppliedRateChange: the multiplier by which the rate of the supplied asset will change
			in ABDK64.64 format
		@param int128 _borrowRateChange: the multiplier by which the rate of the borrowed asset will change
			in ABDK64.64 format

		@return bool: returns true if vault will stay above liquidation zone
			false otherwise
	*/
	function vaultWithstandsChange(
		bool _reqSameBase,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) public view override returns(bool) {

		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);
		require(!_reqSameBase || _baseSupplied == _baseBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed));
		_amountBorrowed = _amountBorrowed
			.div(combinedRateMultipliers_onlyMultiplier(true, true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, _suppliedRateChange, _borrowRateChange));
		_amountBorrowed = _amountBorrowed
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
		_amountBorrowed = _amountBorrowed
			.mul(_priceMultiplier)
			.div((1 ether)*TOTAL_BASIS_POINTS);

		return _amountBorrowed < _amountSupplied;
	}

	/*
		@Description: ensure that a vault will not be sent into liquidation zone if price changes a specified amount
			and rates change by a multiplier

		@param bool _reqSameBase: if true require that base wrapper of supplied and borrowed are the same
		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault
		@param uint _priceMultiplier: the multiplier by which cross asset price of deposit versus borrowed asset changes
			inflated by TOTAL_BASIS_POINTS
		@param int128 _suppliedRateChange: the multiplier by which the rate of the supplied asset will change
			in ABDK64.64 format
		@param int128 _borrowedRateChange: the multiplier by which the rate of the borrowed asset will change
			in ABDK64.64 format

		@return bool: returns true if vault will stay above liquidation zone
			false otherwise
	*/
	function YTvaultWithstandsChange(
		bool _reqSameBase,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) external view override returns (bool) {
		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);
		require(!_reqSameBase || _baseSupplied == _baseBorrowed);

		bool positiveBond = _amountBond >= 0;
		uint maxBorrowed;
		if (!positiveBond && _baseSupplied == _baseBorrowed && getYearsRemaining(_FCPsupplied, _baseSupplied) > 0) {
			maxBorrowed = YTvaultAmtBorrowedUL_1(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, _suppliedRateChange, _borrowedRateChange);
		}
		else {
			maxBorrowed = YTvaultAmtBorrowedUL_0(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, _suppliedRateChange, _borrowedRateChange);
		}
		//account for price multiplier
		uint adjMaxBorrowed = maxBorrowed.mul(TOTAL_BASIS_POINTS).div(_priceMultiplier);
		return _amountBorrowed < adjMaxBorrowed;
	}

	//-----------------------a-d-m-i-n---o-p-e-r-a-t-i-o-n-s---------------------------

	/*
		@Description: admin may set the values in the CollateralizationRatio mappings
		
		@param address _wrapperAddress: the wrapper asset for which to set the a collateralisation ratio
		@param uint128 _upper: the upper collateralisation ratio
			in ABDK64.64 format
		@param uint128 _lower: the upper collateralisation ratio
			in ABDK64.64 format
	*/
	function setCollateralizationRatios(address _wrapperAddress, uint120 _upper, uint120 _lower) external override onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _wrapperAddress is not a fix capital pool contract
		require(IOrganizer(organizerAddress).fixCapitalPoolToWrapper(_wrapperAddress) == address(0));
		upperCollateralizationRatio[_wrapperAddress] = _upper;
		lowerCollateralizationRatio[_wrapperAddress] = _lower;
	}

	/*
		@Description: admin may set the vaules in the RateThreshold mappings

		@param address _wrapperAddress: the wrapper asset for which to set the a collateralisation ratio
		@param uint120 _upper: the upper rate threshold multiplier
			in ABDK64.64 format
		@param uint120 _lower: the lower rate threshold multiplier
			in ABDK64.64 format
	*/
	function setRateThresholds(address _wrapperAddress, uint120 _upper, uint120 _lower) external override onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _wrapperAddress is not a fix capital pool contract
		require(IOrganizer(organizerAddress).fixCapitalPoolToWrapper(_wrapperAddress) == address(0));
		upperRateThreshold[_wrapperAddress] = _upper;
		lowerRateThreshold[_wrapperAddress] = _lower;
	}

	/*
		@Description: admin may set the organizer contract address
	*/
	function setOrganizerAddress(address _organizerAddress) external override onlyOwner {
		require(organizerAddress == address(0));
		organizerAddress = _organizerAddress;
	}

	/*
		@Description: admin may set the maximum short interest for bonds of any maturity for a specific asset

		@param address _underlyingAssetAddress: the address of the underlying asset for which to set a short interest cap
		@param uint _maximumShortInterest: the maximum amount of units of the underlying asset that may sold short via ZCBs
	*/
	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external override onlyOwner {
		maximumShortInterest[_underlyingAssetAddress] = _maximumShortInterest;
	}

	/*
		@Description: admin may set the minimum amount by which the rate for an asset is adjusted when calculating
			collalteralization requirements for the upper and lower limits
	
		@param address _underlyingAssetAddress: the address of the wrapper asset for which to set the minimum rate adjustment
		@param uint120 _upperMinimumRateAdjustment: the new upper minimum rate adjustment for _wrapperAsset
		@param uint120 _lowerMinimumRateAdjustment: the new lower minimum rate adjustment for _wrapperAsset
	*/
	function setMinimumRateAdjustments(address _wrapperAddress, uint120 _upperMinimumRateAdjustment, uint120 _lowerMinimumRateAdjustment) external override onlyOwner {
		upperMinimumRateAdjustment[_wrapperAddress] = _upperMinimumRateAdjustment;
		lowerMinimumRateAdjustment[_wrapperAddress] = _lowerMinimumRateAdjustment;
	}

	//--------V-I-E-W---D-A-T-A-------------

	function MaximumShortInterest(address _underlyingAssetAddress) external view override returns (uint) {
		return maximumShortInterest[_underlyingAssetAddress];
	}

	function UpperCollateralizationRatio(address _wrapperAddress) external view override returns(uint120) {
		return upperCollateralizationRatio[_wrapperAddress];
	}

	function LowerCollateralizationRatio(address _wrapperAddress) external view override returns(uint120) {
		return lowerCollateralizationRatio[_wrapperAddress];
	}

	function UpperRateThreshold(address _wrapperAddress) external view override returns(uint120) {
		return upperRateThreshold[_wrapperAddress];
	}

	function LowerRateThreshold(address _wrapperAddress) external view override returns(uint120) {
		return lowerRateThreshold[_wrapperAddress];
	}

	function UpperMinimumRateAdjustment(address _wrapperAddress) external view override returns (uint120) {
		return upperMinimumRateAdjustment[_wrapperAddress];
	}

	function LowerMinimumRateAdjustment(address _wrapperAddress) external view override returns (uint120) {
		return lowerMinimumRateAdjustment[_wrapperAddress];
	}
}
