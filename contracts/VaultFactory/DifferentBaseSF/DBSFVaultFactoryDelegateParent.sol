// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/BigMath.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./DBSFVaultFactoryData.sol";

contract DBSFVaultFactoryDelegateParent is DBSFVaultFactoryData {
	using SafeMath for uint;
	using SignedSafeMath for int;

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
		@param IInfoOracle _info: the contract that is this contract's InfoOracle

		@return address whitelistAddr: the address returned from the collateralWhitelist mapping in the IInfoOracle contract
			when the supplied asset is passed
		@return SUPPLIED_ASSET_TYPE suppliedType: the type of collateral that the supplied asset is
		@return address baseFCP: the base FCP contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
		@return address baseWrapper: the base wrapper contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
	*/
	function suppliedAssetInfo(
		address _suppliedAsset,
		IInfoOracle _info
	) internal view returns(
		address whitelistAddr,
		SUPPLIED_ASSET_TYPE suppliedType,
		address baseFCP,
		address baseWrapper
	) {
		whitelistAddr = _info.collateralWhitelist(address(this), _suppliedAsset);
		if (whitelistAddr == address(0)) {
			//is likely a ZCB, ensure it is actuall a ZCB and is whitelisted
			baseFCP = IZeroCouponBond(_suppliedAsset).FixCapitalPoolAddress();
			baseWrapper = _info.FCPtoWrapper(address(this), baseFCP);
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
		@Description: ensure that a vault will not be sent into the liquidation zone if the cross asset price
			and the borrow and supplied asset rates change a specific amount

		@param Vault memory vault: contains the state of the vault which to check
		@param uint _priceMultiplier: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the cross asset price
			of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the supplied
			asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the borrow
			asset decreases by a factor of _borrowRateChange
			(in ABDK format)
		@param IInfoOracle _info: reference to the IInfoOracle that is connected to this DBSFVaultFactory

		@return bool: true if vault is not sent into liquidation zone from changes,
			false otherwise
		@return SUPPLIED_ASSET_TYPE suppliedType: the type of collateral that the supplied asset is
		@return address baseFCP: the base FCP contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
		@return address baseWrapper: the base wrapper contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
	*/
	function vaultWithstandsChange(
		Vault memory vault,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange,
		IInfoOracle _info
	) internal view returns (
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
		uint _borrowAmtToPass;
		{
			address whitelistAddr;
			(whitelistAddr, suppliedType, baseFCP, baseWrapper) = suppliedAssetInfo(vault.assetSupplied, _info);
			(_suppliedAddrToPass, _suppliedAmtToPass, _borrowAmtToPass) = passInfoToVaultManagerPassWhitelistAddr(vault, whitelistAddr);
		}

		address pass2 = vault.assetBorrowed;
		uint pass5 = _priceMultiplier;
		int128 pass6 = _suppliedRateChange;
		int128 pass7 = _borrowRateChange;
		withstands = vaultHealthContract.vaultWithstandsChange(
			false,
			_suppliedAddrToPass,
			pass2,
			_suppliedAmtToPass,
			_borrowAmtToPass,
			pass5,
			pass6,
			pass7
		);
	}

	/*
		@Description: returns only the bool from the vaultWithstandsChange function
			uses SLOAD to get the IInofOracle contract to pass
	*/
	function simpleVaultWithstandsChange(
		Vault memory vault,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) internal view returns(bool withstands) {
		(withstands, , , ) = vaultWithstandsChange(vault, _priceMultiplier, _suppliedRateChange, _borrowRateChange, IInfoOracle(_infoOracleAddress));
	}

	/*
		@Description: ensure that short interst rasing by a specific amount does not push an asset over the debt ceiling

		@param address _fixCapitalPoolAddress: address of the ZCB for which to raise short interst
		@param uint _amount: amount ny which to raise short interst
	*/
	function raiseShortInterest(address _fixCapitalPoolAddress, uint _amount) internal {
		address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
		uint temp = _shortInterestAllDurations[underlyingAssetAddress].add(_amount);
		require(vaultHealthContract.maximumShortInterest(underlyingAssetAddress) >= temp);
		_shortInterestAllDurations[underlyingAssetAddress] = temp;
	}

	/*
		@Description: decrease short interest

		@param address _fixCapitalPoolAddress: address of the ZCB for which to decrease short interest
		@param uint _amount: the amount by which to decrease short interest
	*/
	function lowerShortInterest(address _fixCapitalPoolAddress, uint _amount) internal {
		if (_amount > 0) {
			address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
			_shortInterestAllDurations[underlyingAssetAddress] = _shortInterestAllDurations[underlyingAssetAddress].sub(_amount);
		}
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
		uint toTreasury = _amount - retainedSurplus;
		_liquidationRebates[_vaultOwner][_asset] += retainedSurplus;
		_revenue[_asset] += toTreasury;
		IInfoOracle iorc = IInfoOracle(_infoOracleAddress);
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset, iorc);
		require(toTreasury <= uint(type(int256).max));
		editSubAccountStandardVault(_claimRewards, _vaultOwner, sType, baseFCP, baseWrapper, -int(toTreasury));
		//passing claimRewards:true a second time would needlessly waste gas
		editSubAccountStandardVault(false, iorc.sendTo(), sType, baseFCP, baseWrapper, int(toTreasury));
	}

	/*
		@Description: when stability fee is encured pay out to holders

		@param address _ZCBaddr: the ZCB for which to distribute the stability fee
		@param address _FCPaddr: the FCP which corresponds to the ZCB which the stability fee is paid in
		@param uint _amount: the amount of ZCB which has been collected from the stability fee
	*/
	function claimStabilityFee(address _ZCBaddr, address _FCPaddr, uint _amount) internal {
		if (_amount > 0) {
			IFixCapitalPool(_FCPaddr).mintZCBTo(address(this), _amount);
			_revenue[_ZCBaddr] += _amount;
		}
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
		@Description: find the multiplier which is multiplied with amount borrowed (when vault was opened)
			to find the current liability

		@param uint64 _timestampOpened: the time at which the vault was opened
		@param uint64 _stabilityFeeAPR: the annual rate which must be paid for stability fees

		@return uint: the stability rate debt multiplier
			inflated by (1 ether)
	*/
	function getStabilityFeeMultiplier(uint64 _timestampOpened, uint64 _stabilityFeeAPR) internal view returns(uint) {
		if (_stabilityFeeAPR == 0 || _stabilityFeeAPR == NO_STABILITY_FEE || _timestampOpened == block.timestamp)
			return (1 ether);
		int128 yearsOpen = int128((uint(block.timestamp - _timestampOpened) << 64) / BigMath.SecondsPerYear);
		if (yearsOpen == 0)
			return (1 ether);
		int128 stabilityFeeMultiplier = BigMath.Pow(int128(uint(_stabilityFeeAPR) << 32), yearsOpen);
		return uint(stabilityFeeMultiplier).mul(1 ether) >> 64;
	}

	/*
		@Description: find the new amount of ZCBs which is a vault's obligation

		@param uint _amountBorrowed: the Vault's previous obligation in ZCBs at _timestampOpened
		@param uint64 _timestampOpened: the time at which the vault was opened
		@param uint64 _stabilityFeeAPR: the annual rate which must be paid for stability fees

		@return uint: the stability rate debt multiplier
			inflated by (1 ether)
	*/
	function stabilityFeeAdjAmountBorrowed(uint _amountBorrowed, uint64 _timestampOpened, uint64 _stabilityFeeAPR) internal view returns (uint) {
		uint ratio = getStabilityFeeMultiplier(_timestampOpened, _stabilityFeeAPR);
		return ratio.mul(_amountBorrowed) / (1 ether);
	}

	/*
		@Description: ensure that we pass the address of the underlying asset of wrapper assets to
			the vault health contract rather than the address of the wrapper asset
			also ensure that we adjust the amount from the wrapped amount to the non wrapped amount
			if necessary
		@param Vault memory _vault: the vault for which to find the info to pass to the vault health contract
		@param address _whitelistAddr: the output of the collateralWhitelist mapping when the supplied asset is passed
		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint sAmt: the amount for amountSupplied to pass to the vault health contract
		@return uint bAmt: the amounf for amountBorrowed to pass to the vault health contract
	*/
	function passInfoToVaultManagerPassWhitelistAddr(Vault memory _vault, address _whitelistAddr) internal view returns (address addr, uint sAmt, uint bAmt) {
		addr = _whitelistAddr;
		if (addr == address(0) || addr == address(1)) {
			addr = _vault.assetSupplied;
			sAmt = _vault.amountSupplied;
		}
		else {
			sAmt = IWrapper(_vault.assetSupplied).WrappedAmtToUnitAmt_RoundDown(_vault.amountSupplied);
		}
		if (_vault.stabilityFeeAPR == 0 || _vault.stabilityFeeAPR == NO_STABILITY_FEE || _vault.timestampOpened == block.timestamp) {
			bAmt = _vault.amountBorrowed;
		}
		else {
			bAmt = stabilityFeeAdjAmountBorrowed(_vault.amountBorrowed, _vault.timestampOpened, _vault.stabilityFeeAPR);
		}
	}

	/*
		@Description: ensure that we pass the address of the underlying asset of wrapper assets to
			the vault health contract rather than the address of the wrapper asset
			also ensure that we adjust the amount from the wrapped amount to the non wrapped amount
			if necessary

		@param Vault memory _vault: the vault for which to find the info to pass to the vault health contract

		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint sAmt: the amount for amountSupplied to pass to the vault health contract
		@return uint bAmt: the amounf for amountBorrowed to pass to the vault health contract
	*/
	function passInfoToVaultManager(Vault memory _vault) internal view returns (address addr, uint sAmt, uint bAmt) {
		address whitelistAddr = IInfoOracle(_infoOracleAddress).collateralWhitelist(address(this), _vault.assetSupplied);
		(addr, sAmt, bAmt) = passInfoToVaultManagerPassWhitelistAddr(_vault, whitelistAddr);
	}

	/*
		@Description: given a fix capital pool and a balance from the balanceYield mapping
			convert the value from wrapped amount to unit amount
			note that when opening a YTValut this function should NOT be called because it bypasses checking with the
			FCP whitelist in order to avoid an extra SLOAD opcode, rather when opening a YTVault wrappedToUnitAmount
			should be called and the address of InfoOracle.FCPtoWrapper(addr(this), FCP) should be passed as the wrapper address
			also return the address of the base wrapper contract

		@param address _FCP: the address of the FCP contract
		@param uint _amountYield: the wrapper amount to convert to unit amount

		@return uint unitAmountYield: _amountYield of FCP wrapped yield converted to unit amount
		@return address baseWrapper: the base wrapper of the FCP contract
	*/
	function getUnitValueYieldAndWrapper(address _FCP, uint _amountYield) internal view returns(uint unitAmountYield, address baseWrapper) {
		baseWrapper = address(IFixCapitalPool(_FCP).wrapper());
		unitAmountYield = wrappedToUnitAmount(baseWrapper, _amountYield);
	}

	/*
		@Description: given a fix capital pool and a balance from the balanceYield mapping
			convert the value from wrapped amount to unit amount
			note that when opening a YTValut this function should NOT be called because it bypasses checking with the
			FCP whitelist in order to avoid an extra SLOAD opcode, rather when opening a YTVault wrappedToUnitAmount
			should be called and the address of InfoOracle.FCPtoWrapper(addr(this), FCP) should be passed as the wrapper address

		@param address _FCP: the address of the FCP contract
		@param uint _amountYield: the wrapper amount to convert to unit amount

		@return uint unitAmountYield: _amountYield of FCP wrapped yield converted to unit amount
	*/
	function getUnitValueYield(address _FCP, uint _amountYield) internal view returns (uint unitAmountYield) {
		(unitAmountYield, ) = getUnitValueYieldAndWrapper(_FCP, _amountYield);
	}

	/*
		@Description: given a YTVault and change multipliers ensure that if a change of the multipliers would not
			result in the YTVault being in danger of liquidation

		@param YTVault memory vault: the YTVault for which to ensure will not be liquidated
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
	*/
	function YTvaultWithstandsChange(YTVault memory vault, uint _priceMultiplier, int128 _suppliedRateChange, int128 _borrowRateChange) internal view returns (bool) {
		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, vault.bondSupplied > 0);
		return vaultHealthContract.YTvaultWithstandsChange(
			false,
			vault.FCPsupplied,
			vault.FCPborrowed,
			getUnitValueYield(vault.FCPsupplied, vault.yieldSupplied),
			vault.bondSupplied,
			stabilityFeeAdjAmountBorrowed(vault.amountBorrowed, vault.timestampOpened, vault.stabilityFeeAPR),
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		);
	}

	/*
		@Description: given an address of an IWrapper contract convert a wrapped amount to unit amount
			useful for finding what values to pass to VaultHealth

		@param address _wrapperAddress: the address of the IWrapper contract
		@param uint _amountWrapped: the wrapper amount to convert to unit amount

		@return uint unitAmountYield: _amountWrapped of the IWrapper contract's wrapped amount converted to unit amount
	*/
	function wrappedToUnitAmount(address _wrapperAddress, uint _amountWrapped) internal view returns (uint unitAmountYield) {
		require(_wrapperAddress != address(0));
		unitAmountYield = IWrapper(_wrapperAddress).WrappedAmtToUnitAmt_RoundDown(_amountWrapped);
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
		YTVaults must have at least MIN_YIELD_SUPPLIED yield supplied
		This ensures that there are no problems liquidating vaults

		if a user wishes to have no yield supplied to a vault said user
		should use a normal vault and not use a YTvault
	*/
	uint internal constant MIN_YIELD_SUPPLIED = 1e6;
}