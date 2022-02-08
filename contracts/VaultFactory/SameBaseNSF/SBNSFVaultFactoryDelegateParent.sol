// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../helpers/Ownable.sol";
import "../../helpers/nonReentrant.sol";
import "./SBNSFVaultFactoryData.sol";

contract SBNSFVaultFactoryDelegateParent is SBNSFVaultFactoryData, nonReentrant {
	using SafeMath for uint;
	using SignedSafeMath for int;

	/*
		YTVaults must have at least MIN_YIELD_SUPPLIED yield supplied
		This ensures that there are no problems liquidating vaults

		if a user wishes to have no yield supplied to a vault said user
		should use a normal vault and not use a YTvault
	*/
	uint internal constant MIN_YIELD_SUPPLIED = 1e6;

	/*
		@Description: ensure that short interst rasing by a specific amount does not push an asset over the debt ceiling

		@param address _fixCapitalPoolAddress: address of the ZCB for which to raise short interst
		@param uint _amount: amount ny which to raise short interst
	*/
	function raiseShortInterest(address _fixCapitalPoolAddress, uint _amount) internal {
		address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
		uint temp = _shortInterestAllDurations[underlyingAssetAddress].add(_amount);
		require(vaultHealthContract.MaximumShortInterest(underlyingAssetAddress) >= temp);
		_shortInterestAllDurations[underlyingAssetAddress] = temp;
	}

	/*
		@Description: decrease short interest

		@param address _fixCapitalPoolAddress: address of the ZCB for which to decrease short interest
		@param uint _amount: the amount by which to decrease short interest
	*/
	function lowerShortInterest(address _fixCapitalPoolAddress, uint _amount) internal {
		address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
		_shortInterestAllDurations[underlyingAssetAddress] = _shortInterestAllDurations[underlyingAssetAddress].sub(_amount);
	}
	
	/*
		@Description: distribute surplus appropriately between vault owner and contract owner
			this function is called by other liquidation management functions

		@param address _vaultOwner: the owner of the vault that has between liquidated
		@param address _asset: the address of the asset for which surplus has been acquired
		@param uint _amount: the amount of surplus
		@param address _claimRewards: pass true to enter the claimRewards modifier in NGBwrapper
			for either msg.sender or the _FCPaddr, depending on if _FCPaddr == address(0)
	*/
	function distributeSurplus(address _vaultOwner, address _asset, uint _amount, bool _claimRewards) internal {
		uint retainedSurplus = _amount.mul(_liquidationRebateBips) / TOTAL_BASIS_POINTS;
		uint fee = _amount - retainedSurplus;
		_liquidationRebates[_vaultOwner][_asset] += retainedSurplus;
		_revenue[_asset] = _revenue[_asset].add(fee);
		IInfoOracle iorc = IInfoOracle(_infoOracleAddress);
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset);
		editSubAccountStandardVault(_claimRewards, _vaultOwner, sType, baseFCP, baseWrapper, fee.toInt().neg());
		address feeRecipientSubAcct;
		if (iorc.TreasuryFeeIsCollected()) {
			feeRecipientSubAcct = iorc.sendTo();
		}
		else {
			feeRecipientSubAcct = owner;
			_revenueOwnerSubAcct[_asset] = _revenueOwnerSubAcct[_asset].add(fee);
		}
		//passing claimRewards:true a second time would needlessly waste gas
		editSubAccountStandardVault(false, feeRecipientSubAcct, sType, baseFCP, baseWrapper, fee.toInt());
	}

	/*
		@Description: when a bidder is outbid return their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the FCP corresponding to the ZCB that the bidder
			posted with their bid in
		@param uint _amount: the amount of _asset that was posted by the bidder
	*/
	function refundBid(address _bidder, address _FCPaddr, uint _amount) internal {
		IFixCapitalPool(_FCPaddr).mintZCBTo(_bidder, _amount);
	}

	/*
		@Description: when a bidder makes a bid collect collateral for their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the FCP corresponding to the ZCB that the bidder
			posted with their bid in
		@param uint _amount: the amount of _asset that the bidder is required to post
	*/
	function collectBid(address _bidder, address _FCPaddr, uint _amount) internal {
		IFixCapitalPool(_FCPaddr).burnZCBFrom(_bidder, _amount);
	}

	/*
		@Description: ensure that we pass the address of the underlying asset of wrapper assets to
			the vault health contract rather than the address of the wrapper asset
			also ensure that we adjust the amount from the wrapped amount to the non wrapped amount
			if necessary, also pass the _wrapperAddr to prevent use of an extra SLOAD

		@param address _suppliedAsset: the address of the asset that is supplied as collateral
		@param uint _suppliedAmount: the amount of the supplied asset that is being used as collateral
		@param address _whitelistAddr: the address returned when the supplied asset address is unsed
			as the key in the wrapper to underlying asset mapping

		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint amt: the amount for amountSupplied to pass to the vault health contract
	*/
	function passInfoToVaultManagerPassWhitelistAddr(address _suppliedAsset, uint _suppliedAmount, address _whitelistAddr) internal view returns (address addr, uint amt) {
		if (_whitelistAddr == address(0) || _whitelistAddr == address(1)) {
			addr = _suppliedAsset;
			amt = _suppliedAmount;
		}
		else {
			amt = IWrapper(_suppliedAsset).WrappedAmtToUnitAmt_RoundDown(_suppliedAmount);
			addr = _whitelistAddr;
		}
	}

	/*
		@Description: ensure that we pass the address of the underlying asset of wrapper assets to
			the vault health contract rather than the address of the wrapper asset
			also ensure that we adjust the amount from the wrapped amount to the non wrapped amount
			if necessary

		@param address _suppliedAsset: the address of the asset that is supplied as collateral
		@param uint _suppliedAmount: the amount of the supplied asset that is being used as collateral

		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint amt: the amount for amountSupplied to pass to the vault health contract
	*/
	function passInfoToVaultManager(address _suppliedAsset, uint _suppliedAmount) internal view returns (address addr, uint amt) {
		address whitelistAddr = _wrapperToUnderlyingAsset[_suppliedAsset];
		return passInfoToVaultManagerPassWhitelistAddr(_suppliedAsset, _suppliedAmount, whitelistAddr);
	}

	/*
		@Description: ensure that a vault will not be sent into the liquidation zone if the cross asset price
			and the borrow and supplied asset rates change a specific amount

		@param Vault memory vault: the state of the vault which to check
		@param uint _priceMultiplier: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the cross asset price
			of vault.assetBorrowed to vault.assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the supplied
			asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the borrow
			asset decreases by a factor of _borrowRateChange
			(in ABDK format)

		@return bool: true if vault is not sent into liquidation zone from changes,
			false otherwise
	*/
	function vaultWithstandsChange(
		Vault memory vault,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) internal returns (
		bool withstands,
		SUPPLIED_ASSET_TYPE suppliedType,
		address baseFCP,
		address baseWrapper
	) {

		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_suppliedRateChange >= ABDK_1);
		require(_borrowRateChange <= ABDK_1);

		address _suppliedAddrToPass;
		uint _suppliedAmtToPass;
		{
			address whitelistAddr;
			(whitelistAddr, suppliedType, baseFCP, baseWrapper) = suppliedAssetInfo(vault.assetSupplied);
			(_suppliedAddrToPass, _suppliedAmtToPass) = passInfoToVaultManagerPassWhitelistAddr(vault.assetSupplied, vault.amountSupplied, whitelistAddr);
		}

		withstands = vaultHealthContract.vaultWithstandsChange(
			true,
			_suppliedAddrToPass,
			vault.assetBorrowed,
			_suppliedAmtToPass,
			vault.amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		);
	}

	/*
		@Description: edit a sub account registered with the DBSFVaultFactory
			when there is a change to a standard vault

		@param bool _claimRewards: pass true to enter the claimRewards modifier upon wrapper.editSubAccountPosition
		@param address _vaultOwner: the owner of the vault that has been changed
		@param SUPPLIED_ASSET_TYPE sType: the type of collateral supplied to the vault
		@param address _baseFCP: if the sType is ZCB the address of the base FCP contract of the ZCB should be passed
			otherwise address(0) is passed
		@param address _baseWrapper: if the sType is ZCB the address of base wrapper contract of the ZCB should be passed
			if the sType is WASSET the address of the collateral asset of the vault should be passed
			otherwise address(0) is passed
		@param int _changeAmt: the change of the yield or ZCB in the sub account
	*/
	function editSubAccountStandardVault(
		bool _claimRewards,
		address _vaultOwner,
		SUPPLIED_ASSET_TYPE sType,
		address _baseFCP,
		address _baseWrapper,
		int _changeAmt
	) internal {
		if (sType == SUPPLIED_ASSET_TYPE.WASSET) {
			IWrapper(_baseWrapper).editSubAccountPosition(_claimRewards, _vaultOwner, address(0), _changeAmt, 0);
		}
		else if (sType == SUPPLIED_ASSET_TYPE.ZCB) {
			IWrapper(_baseWrapper).editSubAccountPosition(_claimRewards, _vaultOwner, _baseFCP, 0, _changeAmt);
		}
	}

	/*
		@Description: edit a sub acount registered with the DBSFVaultFactory
			when there is a change in a YT Vault

		@param bool _claimRewards: pass true to enter the claimRewards modifier upon wrapper.editSubAccountPosition
		@param address _vaultOwner: the owner of the YT vault that has been changed
		@param address _FCP: the address of the FCP contract from which collateral is being supplied to the YT vault
		@param address _baseWrapper: the base wrapper address of the FCP contract with address _FCP
		@param int _changeYield: the change in the yield amount of collateral supplied
			finalYield - initialYield
		@param int _changeBond: the change in the bond amount of collateral supplied
			finalBond - initialBond
	*/
	function editSubAccountYTVault(
		bool _claimRewards,
		address _vaultOwner,
		address _FCP,
		address _baseWrapper,
		int _changeYield,
		int _changeBond
	) internal {
		IWrapper(_baseWrapper).editSubAccountPosition(_claimRewards, _vaultOwner, _FCP, _changeYield, _changeBond);
	}

	/*
		@Description: given a supplied asset find its type

		@param address _suppliedAsset: the address of the supplied asset

		@return address whitelistAddr: the address returned from the collateralWhitelist mapping in the IInfoOracle contract
			when the supplied asset is passed
		@return SUPPLIED_ASSET_TYPE suppliedType: the type of collateral that the supplied asset is
		@return address baseFCP: the base FCP contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
		@return address baseWrapper: the base wrapper contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
	*/

	function suppliedAssetInfo(
		address _suppliedAsset
	) internal view returns(
		address whitelistAddr,
		SUPPLIED_ASSET_TYPE suppliedType,
		address baseFCP,
		address baseWrapper
	) {
		whitelistAddr = _wrapperToUnderlyingAsset[_suppliedAsset];
		if (whitelistAddr == address(0)) {
			//is likely a ZCB, ensure it is actuall a ZCB and is whitelisted
			baseFCP = IZeroCouponBond(_suppliedAsset).FixCapitalPoolAddress();
			baseWrapper = _fixCapitalPoolToWrapper[baseFCP];
			require(baseWrapper != address(0));
			suppliedType = SUPPLIED_ASSET_TYPE.ZCB;
		}
		else if (whitelistAddr == address(1)) {
			suppliedType = SUPPLIED_ASSET_TYPE.ASSET;
		}
		else {
			baseWrapper = _suppliedAsset;
			suppliedType = SUPPLIED_ASSET_TYPE.WASSET;
		}
	}

	/*
		@Description: check if a vault is above the upper or lower collateralization limit
			return valuable info found while finding if the limit was satisfied

		@param address _assetSupplied: the asset used as collateral
			this asset may be a ZCB or any other asset that is whitelisted
		@param address _assetBorrowed: the ZCB that is borrowed from the new vault
`		@param uint _amountSupplied: the amount of _assetSupplied posed as collateral
		@param uint _amountBorrowed: the amount of _assetBorrowed borrowed
		@param bool _upper: true if we are to check the upper collateralization limit, false otherwise

		@return bool satisfies: true if vault satisfies the limit, false otherwise
		@return SUPPLIED_ASSET_TYPE sType: the type of collateral supplied to the vault
		@return address baseFCP: the base FCP of the collateral supplied to the vault
		@return address baseWrapper: the base wrapper of the collateral supplied to the vault
	*/
	function satisfiesLimitRetAllData(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		bool _upper
	) internal returns (
		bool satisfies,
		SUPPLIED_ASSET_TYPE sType,
		address baseFCP,
		address baseWrapper
	) {

		address whitelistAddr;
		(whitelistAddr, sType, baseFCP, baseWrapper) = suppliedAssetInfo(_assetSupplied);
		(address _suppliedAddrToPass, uint _suppliedAmtToPass) = passInfoToVaultManagerPassWhitelistAddr(_assetSupplied, _amountSupplied, whitelistAddr);

		satisfies = ( _upper ?
			vaultHealthContract.satisfiesUpperLimit(_suppliedAddrToPass, _assetBorrowed, _suppliedAmtToPass, _amountBorrowed)
				:
			vaultHealthContract.satisfiesLowerLimit(_suppliedAddrToPass, _assetBorrowed, _suppliedAmtToPass, _amountBorrowed)
		);
	}


	/*
		@Description: check if a vault is above the upper or lower collateralization limit

		@param address _assetSupplied: the asset used as collateral
			this asset may be a ZCB or any other asset that is whitelisted
		@param address _assetBorrowed: the ZCB that is borrowed from the new vault
`		@param uint _amountSupplied: the amount of _assetSupplied posed as collateral
		@param uint _amountBorrowed: the amount of _assetBorrowed borrowed
		@param bool _upper: true if we are to check the upper collateralization limit, false otherwise

		@return bool: true if vault satisfies the limit, false otherwise
	*/
	function satisfiesLimit(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		bool _upper
	) internal returns (bool satisfies) {
		(satisfies, , , ) = satisfiesLimitRetAllData(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, _upper);
	}

	/*
		@Description: distribute surplus appropriately between vault owner and contract owner
			this function is called by other liquidation management functions

		@param address _vaultOwner: the owner of the vault that has between liquidated
		@param address _FCPaddr: the address of the fix capital pool for which to distribte surplus
		@param uint _yieldAmount: value to add to rebate.amountYield
		@param int _bondAmount: value to add to rebate.amountBond
		@param address _baseWrapper: the base wrapper of the FCP
	*/
	function distributeYTSurplus(
		address _vaultOwner,
		address _FCPaddr,
		uint _yieldAmount,
		int _bondAmount,
		address _baseWrapper
	) internal {
		YTPosition storage rebate = _YTLiquidationRebates[_vaultOwner][_FCPaddr];
		YTPosition storage revenue = _YTRevenue[_FCPaddr];
		uint _rebateBips = _liquidationRebateBips;
		uint yieldRebate = _yieldAmount * _rebateBips / TOTAL_BASIS_POINTS;
		int bondRebate = _bondAmount * int(_rebateBips) / int(TOTAL_BASIS_POINTS);
		rebate.amountYield = rebate.amountYield.add(yieldRebate);
		rebate.amountBond = rebate.amountBond.add(bondRebate);
		uint yieldRevenue = _yieldAmount - yieldRebate;
		int bondRevenue = _bondAmount - bondRebate;
		revenue.amountYield = revenue.amountYield.add(yieldRevenue);
		revenue.amountBond = revenue.amountBond.add(bondRevenue);
		editSubAccountYTVault(true, _vaultOwner, _FCPaddr, _baseWrapper, yieldRevenue.toInt().neg(), bondRevenue.neg());
		IInfoOracle iorc = IInfoOracle(_infoOracleAddress);
		address feeRecipientSubAcct;
		if (iorc.TreasuryFeeIsCollected()) {
			feeRecipientSubAcct = iorc.sendTo();
		}
		else {
			feeRecipientSubAcct = owner;
			address copyFCPaddr = _FCPaddr;
			_YTRevenueOwnerSubAcct[copyFCPaddr].amountYield = _YTRevenueOwnerSubAcct[copyFCPaddr].amountYield.add(yieldRevenue);
			_YTRevenueOwnerSubAcct[copyFCPaddr].amountBond = _YTRevenueOwnerSubAcct[copyFCPaddr].amountBond.add(bondRevenue);
		}
		editSubAccountYTVault(false, feeRecipientSubAcct, _FCPaddr, _baseWrapper, yieldRevenue.toInt(), bondRevenue);
	}

	/*
		@Description: given a fix capital pool and a balance from the balanceYield mapping
			convert the value from wrapped amount to unit amount
	*/
	function getUnitValueYield(address _FCP, uint _amountYield) internal view returns (uint unitAmountYield) {
		address wrapperAddr = _fixCapitalPoolToWrapper[_FCP];
		require(wrapperAddr != address(0));
		unitAmountYield = IWrapper(wrapperAddr).WrappedAmtToUnitAmt_RoundDown(_amountYield);
	}

	/*
		@Description: given an amount of wrapped token and a FCP contract which is based on the same wrapper
			convert an amount of wrapped token into the current amount of ZCB that is a subasset of the wrapped token

		@param address _FCP: the address of the FCP contract for which to find the amount of ZCB
		@param uint _amountWrapped: the amount of wrapped token for which to find the amount of ZCB as a subasset

		@return uint amountZCB: the amount of ZCB contained in specific amount of wrapped asset
		@return address baseWrapper: the base wrapper of the FCP contract
	*/
	function getZCBcontainedInWrappedAmt(address _FCP, uint _amountWrapped) internal view returns(uint amountZCB, address baseWrapper) {
		if (IFixCapitalPool(_FCP).inPayoutPhase()) {
			uint conversionRate = IFixCapitalPool(_FCP).maturityConversionRate();
			amountZCB = conversionRate.mul(_amountWrapped) / (1 ether);
			baseWrapper = address(IFixCapitalPool(_FCP).wrapper());
		}
		else {
			baseWrapper = address(IFixCapitalPool(_FCP).wrapper());
			require(baseWrapper != address(0));
			amountZCB = IWrapper(baseWrapper).WrappedAmtToUnitAmt_RoundDown(_amountWrapped);
		}
	}

	/*
		@Description: ensure that args for YTvaultWithstandsChange() never increase vault health
			all multipliers should have either no change on vault health or decrease vault health
			we make this a function and not a modifier because we will not always have the
			necessary data ready before execution of the functions in which we want to use this

		@param uint _priceMultiplier: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the cross asset price
			of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1 if _positiveBondSupplied otherwise < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the supplied
			asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the borrow
			asset decreases by a factor of _borrowRateChange
			(in ABDK format)
		@param bool _positiveBondSupplied: (ZCB supplied to vault > YT supplied to vault)
	*/
	function validateYTvaultMultipliers(
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange,
		bool _positiveBondSupplied
	) internal pure {
		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_borrowRateChange <= ABDK_1);
		require(
			(_suppliedRateChange == ABDK_1) ||
			(_positiveBondSupplied ? _suppliedRateChange > ABDK_1 : _suppliedRateChange < ABDK_1)
		);
	}

	/*
		@Description: if a YTVault has the same FCPborrowed and FCPsupplied pay back as much debt as possible
			with the zcb contained as collateral in the vault
			this can only be done where FCPborrowed == FCPsupplied because the ZCB that is collateral is the
			same ZCB as the debt, this will not be true for any other type of Vault or YTVault
			return info fetched during execution so that it is not needed to be fetched again

		@param address _owner: the owner of the YTVault for which to pay back debt
		@param uint _index: the index of the YTVault swithin YTvaults[_owner]
		@param YTVault memory _vault: this parameter will be modified if debt is paid back
			when this function is finished executing all member variables of _vault will == the member variables of
			the storage vault which _vault is a copy of

		@return address baseWrapperSupplied: the base wrapper of the FCP of the supplied collateral
	*/
	function autopayYTVault(address _owner, uint _index, YTVault memory _vault) internal returns(address baseWrapperSupplied) {
		if (_vault.FCPborrowed == _vault.FCPsupplied) {
			uint unitValueYield;
			(unitValueYield, baseWrapperSupplied) = getZCBcontainedInWrappedAmt(_vault.FCPborrowed, _vault.yieldSupplied);
			uint difference = _vault.bondSupplied >= 0 ? unitValueYield.add(uint(_vault.bondSupplied)) : unitValueYield.sub(uint(-_vault.bondSupplied));
			difference = difference > _vault.amountBorrowed ? _vault.amountBorrowed : difference;
			if (difference > 0) {
				_vault.bondSupplied -= int(difference);
				_vault.amountBorrowed -= difference;
				_YTvaults[_owner][_index].bondSupplied = _vault.bondSupplied;
				_YTvaults[_owner][_index].amountBorrowed = _vault.amountBorrowed;
			}
		}
		else {
			baseWrapperSupplied = address(IFixCapitalPool(_vault.FCPsupplied).wrapper());
		}
	}

}