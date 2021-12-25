// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/BigMath.sol";
import "../../libraries/SafeERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./DBSFVaultFactoryDelegateParent.sol";

contract DBSFVaultFactoryDelegate5 is DBSFVaultFactoryDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;
	using SafeERC20 for IERC20;

	/*
		@Description: assign a vault/YTvault to a new owner

		@param uint _index: the index within vaults/YTvaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault/YTvault
		@param bool _isYTVault: true when the vault to transfer is a YTvault, false otherwise
	*/
	function transferVault(uint _index, address _to, bool _isYTVault) external {
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
			(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(vault.assetSupplied, IInfoOracle(_infoOracleAddress));
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
		editSubAccountYTVault(true, msg.sender, vault.FCPsupplied, baseWrapper, -int(vault.yieldSupplied), vault.bondSupplied.mul(-1));
		editSubAccountYTVault(false, _to, vault.FCPsupplied, baseWrapper, int(vault.yieldSupplied), vault.bondSupplied);
		_YTvaults[_to].push(vault);
		delete _YTvaults[msg.sender][_index];
	}

	//--------------------admin-------------------

	/*
		@Description: admin may call this function to claim liquidation revenue

		@address _asset: the address of the asset for which to claim revenue
	*/
	function claimRevenue(address _asset) external {
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
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset, iorc);

		if (sType == SUPPLIED_ASSET_TYPE.WASSET || sType == SUPPLIED_ASSET_TYPE.ZCB) {

			uint ownerSubAcctAmt = _revenueOwnerSubAcct[_asset];
			uint treasurySubAcctAmt = rev.sub(ownerSubAcctAmt);

			if (treasurySubAcctAmt > 0) {
				editSubAccountStandardVault(true, treasuryAddr, sType, baseFCP, baseWrapper, treasurySubAcctAmt.toInt().mul(-1));
			}
			if (ownerSubAcctAmt > 0) {
				editSubAccountStandardVault(false, msg.sender, sType, baseFCP, baseWrapper, ownerSubAcctAmt.toInt().mul(-1));
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
	function claimYTRevenue(address _FCP, int _bondIn) external {
		require(_bondIn > -1);
		IInfoOracle iorc = IInfoOracle(_infoOracleAddress);
		IWrapper wrp = IFixCapitalPool(_FCP).wrapper();
		YTPosition memory pos = _YTRevenue[_FCP];
		address sendTo = iorc.sendTo();
		IFixCapitalPool(_FCP).burnZCBFrom(msg.sender, uint(_bondIn));
		if (iorc.TreasuryFeeIsCollected()) {
			uint yieldToTreasury = pos.amountYield >> 1;
			int bondToTreasury = pos.amountBond.add(_bondIn) / 2;
			IFixCapitalPool(_FCP).transferPosition(sendTo, yieldToTreasury, bondToTreasury);
			IFixCapitalPool(_FCP).transferPosition(msg.sender, pos.amountYield - yieldToTreasury, pos.amountBond.add(_bondIn) - bondToTreasury);
		}
		else {
			IFixCapitalPool(_FCP).transferPosition(msg.sender, pos.amountYield, pos.amountBond.add(_bondIn));
		}

		YTPosition memory ownerSubAcctPos = _YTRevenueOwnerSubAcct[_FCP];
		YTPosition memory treasurySubAcctPos = YTPosition(
			pos.amountYield.sub(ownerSubAcctPos.amountYield),
			pos.amountBond.sub(ownerSubAcctPos.amountBond)
		);

		if (ownerSubAcctPos.amountYield != 0 || ownerSubAcctPos.amountBond != 0) {
			int changeYield = ownerSubAcctPos.amountYield.toInt().mul(-1);
			int changeBond = ownerSubAcctPos.amountBond.mul(-1);
			editSubAccountYTVault(true, msg.sender, _FCP, address(wrp), changeYield, changeBond);
		}
		if (treasurySubAcctPos.amountYield != 0 || treasurySubAcctPos.amountBond != 0) {
			int changeYield = treasurySubAcctPos.amountYield.toInt().mul(-1);
			int changeBond = treasurySubAcctPos.amountBond.mul(-1);
			editSubAccountYTVault(true, sendTo, _FCP, address(wrp), changeYield, changeBond);
		}

		delete _YTRevenue[_FCP];
		delete _YTRevenueOwnerSubAcct[_FCP];
	}


	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their vault(s) were liquidated

		@param address _asset: the address of the asset for which to claim rebated collateral
	*/
	function claimRebate(address _asset) external {
		uint amt = _liquidationRebates[msg.sender][_asset];
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset, IInfoOracle(_infoOracleAddress));
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
}