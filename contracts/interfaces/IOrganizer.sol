// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IOrganizer {
	event WrapperDeployment(
		address indexed wrapperAddress,
		address indexed underlyingAddress,
		address indexed owner,
		uint wrapperType
	);

	event FixCapitalPoolDeployment(
		address indexed FCPaddress,
		address indexed BaseWrapperAddress,
		address indexed owner,
		uint40 maturity
	);

	event OrderbookDeployment(
		address indexed OrderbookAddress,
		address indexed BaseFCPaddress
	);

	function fixCapitalPoolToWrapper(address _FCPaddress) external view returns (address wrapperAddress);
	function Orderbooks(address _FCPaddress) external view returns (address OrderbookAddress);
	function wrapperIsVerified(address _wrapperAddress) external view returns (bool isVerified);

	function NGBwrapperDeployerAddress() external view returns(address);
	function ZCB_YT_DeployerAddress() external view returns(address);
	function FixCapitalPoolDeployerAddress() external view returns(address);
	function OrderbookDeployerAddress() external view returns(address);
	function QuickDepositorAddress() external view returns(address);
	function InfoOracleAddress() external view returns(address);
	function WrapperDeployers(uint _index) external view returns(address deployerAddress);

	function deployNGBWrapper(address _underlyingAssetAddress) external;
	function deployWrapper(uint _deployerIndex, address _underlyingAssetAddress) external;
	function deployFixCapitalPoolInstance(address _wrapperAddress, uint40 _maturity) external;
	function deployOrderbook(address _fixCapitalPoolAddress) external;

	//---------admin---------------
	function setVerified(address _wrapperAddress, bool _setTo) external;
	function whitelistWrapperDeployer(address _wrapperDeployerAddress) external;
	function delistWrapperDeployer(uint _index) external;
}