// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IOrganizer {
	event WrapperDeployment(
		address wrapperAddress,
		address underlyingAddress,
		uint8 wrapperType
	);

	event FixCapitalPoolDeployment(
		address addr
	);
	function fixCapitalPoolToWrapper(address _FCPaddress) external view returns (address wrapperAddress);
	function ZCBamms(address _FCPaddress) external view returns (address ZCBammAddress);
	function YTamms(address _FCPaddress) external view returns (address YTammAddress);
	function Orderbooks(address _FCPaddress) external view returns (address OrderbookAddress);
	function wrapperIsVerified(address _wrapperAddress) external view returns (bool isVerified);

	function NGBwrapperDeployerAddress() external view returns(address);
	function ZCB_YT_DeployerAddress() external view returns(address);
	function FixCapitalPoolDeployerAddress() external view returns(address);
	function ZCBammDeployerAddress() external view returns(address);
	function YTammDeployerAddress() external view returns(address);
	function OrderbookDeployerAddress() external view returns(address);
	function QuickDepositorAddress() external view returns(address);
	function SwapRouterAddress() external view returns(address);
	function InfoOracleAddress() external view returns(address);

	function DeploySwapRouter() external;
	function deployNGBWrapper(address _underlyingAssetAddress) external;
	function deployFixCapitalPoolInstance(address _wrapperAddress, uint40 _maturity) external;
	function deployZCBamm(address _fixCapitalPoolAddress) external;
	function deployYTamm(address _fixCapitalPoolAddress) external;
	function deployOrderbook(address _fixCapitalPoolAddress) external;

	//---------admin---------------
	function setVerified(address _wrapperAddress, bool _setTo) external;

}