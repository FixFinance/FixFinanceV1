// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../../interfaces/IVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./NSFVaultFactoryDelegateParent.sol";

contract NSFVaultFactoryDelegate5 is NSFVaultFactoryDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;
	using SafeERC20 for IERC20;

	/*
		@Description: assign a vault/YTvault to a new owner

		@param uint _index: the index within vaults/YTvaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault/YTvault
		@param bool _isYTVault: true when the vault to transfer is a YTvault, false otherwise
	*/
	function transferVault(uint _index, address _to, bool _isYTVault) external noReentry {
		if (_isYTVault) {
			transferYTVault(_index, _to);
		}
		else {
			transferStandardVault(_index, _to);
		}
	}

	/*
		@Description: assign a vault to a new owner

		@param uint _index: the index within vaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault
	*/
	function transferStandardVault(uint _index, address _to) internal {
		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];
		_vaults[_to].push(vault);
		if (vault.amountSupplied > 0) {
			(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(vault.assetSupplied);
			require(vault.amountSupplied <= uint(type(int256).max));
			int intSupplied = int(vault.amountSupplied);
			editSubAccountStandardVault(true, msg.sender, sType, baseFCP, baseWrapper, -intSupplied);
			//passing claimRewards:true a second time would needlessly waste gas
			editSubAccountStandardVault(false, _to, sType, baseFCP, baseWrapper, intSupplied);
		}
		delete _vaults[msg.sender][_index];
	}

	/*
		@Description: assign a YT vault to a new owner

		@param uint _index: the index within YTvaults[msg.sender] at which the YT vault to transfer is located
		@param address _to: the new owner of the YT vault
	*/
	function transferYTVault(uint _index, address _to) internal {
		require(_YTvaults[msg.sender].length > _index);
		YTVault memory vault = _YTvaults[msg.sender][_index];
		require(vault.yieldSupplied <= uint(type(int256).max));
		address baseWrapper = address(IFixCapitalPool(vault.FCPsupplied).wrapper());
		editSubAccountYTVault(true, msg.sender, vault.FCPsupplied, baseWrapper, -int(vault.yieldSupplied), vault.bondSupplied.neg());
		editSubAccountYTVault(false, _to, vault.FCPsupplied, baseWrapper, int(vault.yieldSupplied), vault.bondSupplied);
		_YTvaults[_to].push(vault);
		delete _YTvaults[msg.sender][_index];
	}

	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their vault(s) were liquidated

		@param address _asset: the address of the asset for which to claim rebated collateral
	*/
	function claimRebate(address _asset) external {
		uint amt = _liquidationRebates[msg.sender][_asset];
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset);
		editSubAccountStandardVault(false, msg.sender, sType, baseFCP, baseWrapper, amt.toInt().neg());
		delete _liquidationRebates[msg.sender][_asset];
		IERC20(_asset).safeTransfer(msg.sender, amt);
	}

	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their YT vault(s) were liquidated
	
		@param address _FCP: the address of the FCP contract for which to claim the rebate
	*/
	function claimYTRebate(address _FCP) external {
		YTPosition memory position = _YTLiquidationRebates[msg.sender][_FCP];
		address baseWrapper = address(IFixCapitalPool(_FCP).wrapper());
		editSubAccountYTVault(false, msg.sender, _FCP, baseWrapper, position.amountYield.toInt().neg(), position.amountBond.neg());
		delete _YTLiquidationRebates[msg.sender][_FCP];
		IFixCapitalPool(_FCP).transferPosition(msg.sender, position.amountYield, position.amountBond);
	}

	/*
		@Description: admin may call this function to allow a specific wrapped asset to be provided as collateral

		@param address _wrapperAddress: address of the wrapper asset to whitelist
	*/
	function whitelistWrapper(address _wrapperAddress) internal {
		IWrapper(_wrapperAddress).registerAsDistributionAccount();
		_wrapperToUnderlyingAsset[_wrapperAddress] = IWrapper(_wrapperAddress).underlyingAssetAddress();
	}

	/*
		@Description: admin may call this function to allow a non wrapped asset to be provided as collateral

		@param address _asset: address of the asset that will be allows to be provided as collateral
	*/
	function whitelistAsset(address _assetAddress) internal {
		//all non wrapped assets have a pair value of address(1) in the _wrapperToUnderlyingAsset mapping
		_wrapperToUnderlyingAsset[_assetAddress] = address(1);
	}

	/*
		@Description: admin may call this function to allow a specific ZCB to be provided as collateral

		@param address _fixCapitalPoolAddress: address of the ZCB to whitelist
	*/
	function whitelistFixCapitalPool(address _fixCapitalPoolAddress) internal {
		IWrapper wrapper = IFixCapitalPool(_fixCapitalPoolAddress).wrapper();
		wrapper.registerAsDistributionAccount();
		_fixCapitalPoolToWrapper[_fixCapitalPoolAddress] = address(wrapper);
	}

	/*
		@Description: admin may call this function to set the percentage of excess collateral that is retained
			by vault owners in the event of a liquidation

		@param uint _rebateBips: the percentage (in basis points) of excess collateral that is retained
			by vault owners in the event of a liquidation
	*/
	function setLiquidationRebate(uint _rebateBips) internal {
		require(_rebateBips <= TOTAL_BASIS_POINTS);
		_liquidationRebateBips = _rebateBips;
	}

	/*
		@Description: admin may call this function to claim liquidation revenue

		@address _asset: the address of the asset for which to claim revenue
	*/
	function claimRevenue(address _asset) internal {
		uint rev = _revenue[_asset];
		uint toTreasury = rev >> 1;
		IInfoOracle iorc = IInfoOracle(_infoOracleAddress);
		address treasuryAddr = iorc.sendTo();
		if (iorc.TreasuryFeeIsCollected()) {
			IERC20(_asset).safeTransfer(treasuryAddr, toTreasury);
			IERC20(_asset).safeTransfer(msg.sender, rev - toTreasury);
		}
		else {
			IERC20(_asset).safeTransfer(msg.sender, rev);
		}
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset);

		if (sType == SUPPLIED_ASSET_TYPE.WASSET || sType == SUPPLIED_ASSET_TYPE.ZCB) {

			uint ownerSubAcctAmt = _revenueOwnerSubAcct[_asset];
			uint treasurySubAcctAmt = rev.sub(ownerSubAcctAmt);

			if (treasurySubAcctAmt > 0) {
				editSubAccountStandardVault(true, treasuryAddr, sType, baseFCP, baseWrapper, treasurySubAcctAmt.toInt().neg());
			}
			if (ownerSubAcctAmt > 0) {
				editSubAccountStandardVault(false, msg.sender, sType, baseFCP, baseWrapper, ownerSubAcctAmt.toInt().neg());
			}
		}
		delete _revenue[_asset];
		delete _revenueOwnerSubAcct[_asset];
	}

	/*
		@Description: admin may call this function to claim YT liquidation revenue

		@param address _FCP: the address of the FCP contract for which to claim revenue
		@param int _bondIn: the amount of bond to send in to make the transfer position have a
			positive minimum value at maturity
	*/
	function claimYTRevenue(address _FCP, int _bondIn) internal {
		require(_bondIn > -1);
		YTPosition memory pos = _YTRevenue[_FCP];
		IFixCapitalPool(_FCP).burnZCBFrom(msg.sender, uint(_bondIn));
		uint yieldToTreasury = pos.amountYield >> 1;
		int bondToTreasury = pos.amountBond.add(_bondIn) / 2;
		address treasuryAddr = IInfoOracle(_infoOracleAddress).sendTo();
		IFixCapitalPool(_FCP).transferPosition(treasuryAddr, yieldToTreasury, bondToTreasury);
		IFixCapitalPool(_FCP).transferPosition(msg.sender, pos.amountYield - yieldToTreasury, (pos.amountBond + _bondIn) - bondToTreasury);
		delete _YTRevenue[_FCP];
	}

	function manage(address _addr, int _num, MANAGE_METHOD _mm) external onlyOwner {
		if (_mm == MANAGE_METHOD.WHITELIST_WRAPPER) {
			whitelistWrapper(_addr);
		}
		else if (_mm == MANAGE_METHOD.WHITELIST_ASSET) {
			whitelistAsset(_addr);
		}
		else if (_mm == MANAGE_METHOD.WHITELIST_FCP) {
			whitelistFixCapitalPool(_addr);
		}
		else if (_mm == MANAGE_METHOD.SET_LIQ_REBATE) {
			setLiquidationRebate(_num.toUint());
		}
		else if (_mm == MANAGE_METHOD.CLAIM_REVENUE) {
			claimRevenue(_addr);
		}
		else if (_mm == MANAGE_METHOD.CLAIM_YT_REVENUE) {
			claimYTRevenue(_addr, _num);
		}
	}

}
