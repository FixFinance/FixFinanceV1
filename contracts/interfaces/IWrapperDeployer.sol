// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IWrapperDeployer {
	function deploy(address _underlyingAssetAddress, address _owner) external returns(address wrapperAddress);
	function InfoOracleAddress() external view returns(address);
}