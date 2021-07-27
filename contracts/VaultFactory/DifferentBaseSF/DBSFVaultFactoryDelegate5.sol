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
			editSubAccountStandardVault(msg.sender, sType, baseFCP, baseWrapper, -intSupplied);
			editSubAccountStandardVault(_to, sType, baseFCP, baseWrapper, intSupplied);
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
}