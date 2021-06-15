// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IOrganizer {
	function fixCapitalPoolToWrapper(address _FCPaddress) external view returns (address wrapperAddress);
	function ZCBamms(address _FCPaddress) external view returns (address ZCBammAddress);
	function YTamms(address _FCPaddress) external view returns (address YTammAddress);
	function wrapperIsVerified(address _wrapperAddress) external view returns (bool isVerified);

	function ZCB_YT_DeployerAddress() external view returns(address);
	function FixCapitalPoolDeployerAddress() external view returns(address);
	function ZCBammDeployerAddress() external view returns(address);
	function YTammDeployerAddress() external view returns(address);
	function SwapRouterAddress() external view returns(address);
	function InfoOracleAddress() external view returns(address);

	function DeploySwapRouter() external;
	function deployNGBWrapper(address _underlyingAssetAddress) external;
	function deployFixCapitalPoolInstance(address _wrapperAddress, uint64 _maturity) external;
	function deployZCBamm(address _fixCapitalPoolAddress) external;
	function deployYTamm(address _fixCapitalPoolAddress) external;

	//---------admin---------------
	function setVerified(address _wrapperAddress, bool _setTo) external;

}