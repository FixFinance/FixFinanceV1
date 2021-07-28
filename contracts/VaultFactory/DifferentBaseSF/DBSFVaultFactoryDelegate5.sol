// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/BigMath.sol";
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
		address treasuryAddr = _treasuryAddress;
		IERC20(_asset).transfer(treasuryAddr, toTreasury);
		IERC20(_asset).transfer(msg.sender, rev - toTreasury);
		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(_asset, IInfoOracle(_infoOracleAddress));
		editSubAccountStandardVault(true, _treasuryAddress, sType, baseFCP, baseWrapper, -int(rev));
		delete _revenue[_asset];
	}

	/*
		@Description: admin may call this function to claim YT liquidation revenue

		@param address _FCP: the address of the FCP contract for which to claim revenue
		@param int _bondIn: the amount of bond to send in to make the transfer position have a
			positive minimum value at maturity
	*/
	function claimYTRevenue(address _FCP, int _bondIn) external {
		require(_bondIn > -1);
		YTPosition memory pos = _YTRevenue[_FCP];
		IFixCapitalPool(_FCP).burnZCBFrom(msg.sender, uint(_bondIn));
		uint yieldToTreasury = pos.amountYield >> 1;
		int bondToTreasury = pos.amountBond.add(_bondIn) / 2;
		IFixCapitalPool(_FCP).transferPosition(_treasuryAddress, yieldToTreasury, bondToTreasury);
		IFixCapitalPool(_FCP).transferPosition(msg.sender, pos.amountYield - yieldToTreasury, (pos.amountBond + _bondIn) - bondToTreasury);
		delete _YTRevenue[_FCP];
	}
}