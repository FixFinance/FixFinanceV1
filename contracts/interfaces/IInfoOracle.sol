// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IInfoOracle {
	function MinimumOrderbookFee() external view returns(uint8);
	function TreasuryFeeIsCollected() external view returns(bool);
	function sendTo() external view returns(address);
	function WrapperOrderbookFeeBips(address _wrapperAddr) external view returns(uint8);
	function FCPOrderbookFeeBips(address _fixCapitalPoolAddress) external view returns(uint8);
	function getOrderbookFeeBips(address _fixCapitalPoolAddress) external view returns(uint8);
	function DelegatedControllers(address _contract) external view returns (address delegate);
	//for use by DBSFVaultFactory
	function StabilityFeeAPR(address _vaultFactoryAddress, address _wrapperAddress) external view returns (uint64 stabilityFeeAPR);
	function collateralWhitelist(address _vaultFactoryAddress, address _assetAddress) external view returns (address underlyingAsset);
	function FCPtoWrapper(address _vaultFactoryAddress, address _FCPaddress) external view returns (address wrapperAddress);

	//---------management--------------

	function setDelegatedController(address _contract, address _manager) external;
	function wrapperSetOrderbookFeeConstant(address _wrapper, uint8 _orderbookFeeBips) external;
	function setOrderbookFeeConstant(address _fixCapitalPoolAddress, uint8 _orderbookFeeBips) external;
	//for use by DBSFVaultFactory admins
	function setStabilityFeeAPR(address _vaultFactoryAddress, address _wrapperAddress, uint64 _stabilityFeeAPR) external;
	function whitelistWrapper(address _vaultFactoryAddress, address _wrapperAddress) external;
	function whitelistAsset(address _vaultFactoryAddress, address _assetAddress) external;
	function whitelistFixCapitalPool(address _vaultFactoryAddress, address _FCPaddress) external;

	//---------InfoOracle-Admin--------

	function setMinimumOrderbookFee(uint8 _orderbookFeeBips) external;
	function setTreasuryFeeIsCollected(bool _TreasuryFeeIsCollected) external;

}