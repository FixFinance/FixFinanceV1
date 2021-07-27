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
			suppliedType = SUPPLIED_ASSET_TYPE.WASSET;
		}
	}
}