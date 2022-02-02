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
import "./VaultHealthParent.sol";


contract VaultHealth is IVaultHealth, VaultHealthParent {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	address delegate1;

	constructor(address _oracleContainerAddress, address _delegate1) public {
		oracleContainerAddress = _oracleContainerAddress;
		delegate1 = _delegate1;
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
		@param uint120 _upper: the upper collateralisation ratio
			in ABDK64.64 format
		@param uint120 _lower: the upper collateralisation ratio
			in ABDK64.64 format
		@param uint120 _liqBonus: the bonus % of collateral given to the liquidator upon liquidation
		@param uint120 _liqProtocolFee: the fee collected for the protocol on liquidations
	*/
	function setCollateralizationRatios(address _wrapperAddress, uint120 _upper, uint120 _lower, uint120 _liqBonus, uint120 _liqProtocolFee) external override {
		(bool success, ) = delegate1.delegatecall(abi.encodeWithSignature(
			"setCollateralizationRatios(address,uint120,uint120,uint120,uint120)",
			_wrapperAddress,
			_upper,
			_lower,
			_liqBonus,
			_liqProtocolFee
		));
		require(success);
	}

	/*
		@Description: admin may set the vaules in the RateThreshold mappings

		@param address _wrapperAddress: the wrapper asset for which to set the a collateralisation ratio
		@param uint120 _upper: the upper rate threshold multiplier
			in ABDK64.64 format
		@param uint120 _lower: the lower rate threshold multiplier
			in ABDK64.64 format
	*/
	function setRateThresholds(address _wrapperAddress, uint120 _upper, uint120 _lower) external override {
		(bool success, ) = delegate1.delegatecall(abi.encodeWithSignature(
			"setRateThresholds(address,uint120,uint120)",
			_wrapperAddress,
			_upper,
			_lower
		));
		require(success);
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

	function LiquidatorBonus(address _assetAddress) external view override returns (uint120) {
		return liquidatorBonus[_assetAddress];
	}

	function ProtocolLiqFee(address _assetAddress) external view override returns (uint120) {
		return protocolLiqFee[_assetAddress];
	}
}
