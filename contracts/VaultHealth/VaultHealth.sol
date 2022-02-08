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
import "./VaultHealthCoreParent.sol";


contract VaultHealth is IVaultHealth, VaultHealthCoreParent {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	constructor(address _oracleContainerAddress, address _delegate1, address _delegate2) public {
		oracleContainerAddress = _oracleContainerAddress;
		delegate1 = _delegate1;
		delegate2 = _delegate2;
	}

	//-----------------------i-m-p-l-e-m-e-n-t---I-V-a-u-l-t-H-e-a-l-t-h--------------------------


	/*
		@Description: check if a vault is above the upper collateralisation limit

			- Function is Pseudo View function, no state is changed but view flag cannot be added because of delegatecall opcode use

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the upper collateralisation limit
			false otherwise
	*/
	function satisfiesUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override returns (bool) {
		return decodeBool(abi.encodeWithSignature(
			"satisfiesUpperLimit(address,address,uint256,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed
		));
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
	function satisfiesLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external override returns (bool) {
		return decodeBool(abi.encodeWithSignature(
			"satisfiesLowerLimit(address,address,uint256,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed
		));
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
	function YTvaultSatisfiesUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external override returns (bool) {
		return decodeBool(abi.encodeWithSignature(
			"YTvaultSatisfiesUpperLimit(address,address,uint256,int256,uint256)",
			_FCPsupplied,
			_FCPborrowed,
			_amountYield,
			_amountBond,
			_amountBorrowed
		));
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
	function YTvaultSatisfiesLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external override returns (bool) {
		return decodeBool(abi.encodeWithSignature(
			"YTvaultSatisfiesLowerLimit(address,address,uint256,int256,uint256)",
			_FCPsupplied,
			_FCPborrowed,
			_amountYield,
			_amountBond,
			_amountBorrowed
		));
	}

	/*
		@Description: returns value from _amountSuppliedAtUpperLimit() externally
	*/
	function amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external override returns (uint) {
		return decodeUint(abi.encodeWithSignature(
			"amountSuppliedAtUpperLimit(address,address,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountBorrowed
		));
	}

	/*
		@Description: returns value from _amountSuppliedAtLowerLimit() externally
	*/
	function amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external override returns (uint) {
		return decodeUint(abi.encodeWithSignature(
			"amountSuppliedAtLowerLimit(address,address,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountBorrowed
		));
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed for a vault stay above the upper collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault

		@return uint: the maximum amount of borrowed asset that must be borrowed from a vault in order for the vault to stay above the
			upper collateralisation limit
	*/
	function amountBorrowedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external override returns (uint) {
		return decodeUint(abi.encodeWithSignature(
			"amountBorrowedAtUpperLimit(address,address,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied
		));
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed for a vault stay above the lower collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault

		@return uint: the maximum amount of borrowed asset that must be borrowed from a vault in order for the vault to stay above the
			lower collateralisation limit
	*/
	function amountBorrowedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external override returns (uint) {
		return decodeUint(abi.encodeWithSignature(
			"amountBorrowedAtLowerLimit(address,address,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied
		));
	}

	/*
		@Description: returns _YTvaultAmountBorrowedAtUpperLimit externally
	*/
	function YTvaultAmountBorrowedAtUpperLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) external override returns (uint) {
		return decodeUint(abi.encodeWithSignature(
			"YTvaultAmountBorrowedAtUpperLimit(address,address,uint256,int256)",
			_FCPsupplied,
			_FCPborrowed,
			_amountYield,
			_amountBond
		));
	}

	/*
		@Description: returns _YTvaultAmountBorrowedAtLowerLimit externally
	*/
	function YTvaultAmountBorrowedAtLowerLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) external override returns (uint) {
		return decodeUint(abi.encodeWithSignature(
			"YTvaultAmountBorrowedAtLowerLimit(address,address,uint256,int256)",
			_FCPsupplied,
			_FCPborrowed,
			_amountYield,
			_amountBond
		));
	}

	/*
		@Description: based on the state of a vault return info necessary for standard liquidations

			- Function is Pseudo View function, no state is changed but view flag cannot be added because of delegatecall opcode use

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return bool satisfies: true if the vault state satisfies the upper limit, false if it does not
		@return uint amountToLiquidator: the amount of the collateral that shall go to the liquidator if the entire vault is liquidated
		@return uint amountToProtocol: the amount of the collatearl that shall go to the protocol if the entire vault is liquidated
	*/
	function upperLimitLiquidationDetails(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
	) external override returns(
		bool satisfies,
		uint amountToLiquidator,
		uint amountToProtocol
	) {
		(bool success, bytes memory data) = delegate2.delegatecall(abi.encodeWithSignature(
			"upperLimitLiquidationDetails(address,address,uint256,uint256)",
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed
		));
		require(success);
		(satisfies, amountToLiquidator, amountToProtocol) = abi.decode(data, (bool, uint256, uint256));
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
	) public override returns(bool) {
		return decodeBool(abi.encodeWithSignature(
			"vaultWithstandsChange(bool,address,address,uint256,uint256,uint256,int128,int128)",
			_reqSameBase,
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
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
	) external override returns (bool) {
		return decodeBool(abi.encodeWithSignature(
			"YTvaultWithstandsChange(bool,address,address,uint256,int256,uint256,uint256,int128,int128)",
			_reqSameBase,
			_FCPsupplied,
			_FCPborrowed,
			_amountYield,
			_amountBond,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowedRateChange
		));
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
			this may only be done once
	*/
	function setOrganizerAddress(address _organizerAddress) external override {
		(bool success, ) = delegate1.delegatecall(abi.encodeWithSignature(
			"setOrganizerAddress(address)",
			_organizerAddress
		));
		require(success);
	}

	/*
		@Description: admin may set the maximum short interest for bonds of any maturity for a specific asset

		@param address _underlyingAssetAddress: the address of the underlying asset for which to set a short interest cap
		@param uint _maximumShortInterest: the maximum amount of units of the underlying asset that may sold short via ZCBs
	*/
	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external override {
		(bool success, ) = delegate1.delegatecall(abi.encodeWithSignature(
			"setMaximumShortInterest(address,uint256)",
			_underlyingAssetAddress,
			_maximumShortInterest
		));
		require(success);
	}

	/*
		@Description: admin may set the minimum amount by which the rate for an asset is adjusted when calculating
			collalteralization requirements for the upper and lower limits
	
		@param address _underlyingAssetAddress: the address of the wrapper asset for which to set the minimum rate adjustment
		@param uint120 _upperMinimumRateAdjustment: the new upper minimum rate adjustment for _wrapperAsset
		@param uint120 _lowerMinimumRateAdjustment: the new lower minimum rate adjustment for _wrapperAsset
	*/
	function setMinimumRateAdjustments(address _wrapperAddress, uint120 _upperMinimumRateAdjustment, uint120 _lowerMinimumRateAdjustment) external override {
		(bool success, ) = delegate1.delegatecall(abi.encodeWithSignature(
			"setMinimumRateAdjustments(address,uint120,uint120)",
			_wrapperAddress,
			_upperMinimumRateAdjustment,
			_lowerMinimumRateAdjustment
		));
		require(success);
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
