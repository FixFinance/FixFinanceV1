// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./interfaces/IOrganizer.sol";
import "./interfaces/IWrapperDeployer.sol";
import "./FixCapitalPool/FixCapitalPoolDeployer.sol";
import "./QuickDepositor/QuickDepositorDeployer.sol";
import "./Orderbook/OrderbookDeployer.sol";
import "./helpers/Ownable.sol";
import "./InfoOracle.sol";

contract Organizer is Ownable, IOrganizer {
	//acts as a whitelist for fixCapitalPools that were deployed using this organiser
	mapping(address => address) public override fixCapitalPoolToWrapper;
	//FixCapitalPool => Orderbook address
	mapping(address => address) public override Orderbooks;
	//IWrapper => isVerified
	mapping(address => bool) public override wrapperIsVerified;

	address public override NGBwrapperDeployerAddress;
	address public override ZCB_YT_DeployerAddress;
	address public override FixCapitalPoolDeployerAddress;
	address public override OrderbookDeployerAddress;
	address public override QuickDepositorAddress;
	address public override InfoOracleAddress;

	address[] public override WrapperDeployers;

	/*
		init
	*/
	constructor (
		address _NGBwrapperDeployerAddress,
		address _ZCB_YT_DeployerAddress,
		address _fixCapitalPoolDeployerAddress,
		address _OrderbookDeployerAddress,
		address _QuickDepositorDeployerAddress,
		address _InfoOracleAddress
	) public {
		NGBwrapperDeployerAddress = _NGBwrapperDeployerAddress;
		WrapperDeployers.push(_NGBwrapperDeployerAddress);
		ZCB_YT_DeployerAddress = _ZCB_YT_DeployerAddress;	
		FixCapitalPoolDeployerAddress = _fixCapitalPoolDeployerAddress;
		OrderbookDeployerAddress = _OrderbookDeployerAddress;
		QuickDepositorAddress = QuickDepositorDeployer(_QuickDepositorDeployerAddress).deploy(address(this));
		InfoOracleAddress = _InfoOracleAddress;
	}

	/*
		@Description: deploy a new NGBwrapper and transfer ownership to msg.sender
		
		@param address _underlyingAssetAddress: the NGB asset for which to deploy an NGBwrapper
	*/
	function deployNGBWrapper(address _underlyingAssetAddress) external override {
		address wrapperAddress = IWrapperDeployer(NGBwrapperDeployerAddress).deploy(_underlyingAssetAddress, msg.sender);
		wrapperIsVerified[wrapperAddress] = true;
		emit WrapperDeployment(wrapperAddress, _underlyingAssetAddress, msg.sender, 0);
	}

	/*
		@Description: deploy a new IWrapper contract from a specific IWrapperDeployer contract
			transfer ownership to msg.sender

		@param uint _deployerIndex: the index of the IWrapperDeployer contract within the WrapperDeployers array
		@param address _underlyingAssetAddress: the underlying asset for which to deploy a wrapper
	*/
	function deployWrapper(uint _deployerIndex, address _underlyingAssetAddress) external override {
		require(WrapperDeployers.length > _deployerIndex, "invalid WrapperDeployers index");
		address deployerAddress = WrapperDeployers[_deployerIndex];
		require(deployerAddress != address(0), "Selected WrapperDeployer has been delisted");
		address wrapperAddress = IWrapperDeployer(deployerAddress).deploy(_underlyingAssetAddress, msg.sender);
		wrapperIsVerified[wrapperAddress] = true;
		emit WrapperDeployment(wrapperAddress, _underlyingAssetAddress, msg.sender, _deployerIndex);
	}


	/*
		@Description: deploy a new FixCapitalPool instance, whitelist it in fixCapitalPoolToWrapper mapping

		@param address _wrapperAddress: the address of the IWrapper for which to deploy the FixCapitalPool
		@param uint40 _maturity: the maturity of the new FixCapitalPool to deploy
	*/
	function deployFixCapitalPoolInstance(address _wrapperAddress, uint40 _maturity) external override {
		require(_maturity > block.timestamp+(1 weeks), "maturity must be at least 1 weeks away");
		require(wrapperIsVerified[_wrapperAddress], "base wrapper must be verified");
		address fixCapitalPoolAddress = FixCapitalPoolDeployer(FixCapitalPoolDeployerAddress).deploy(
			_wrapperAddress,
			_maturity,
			ZCB_YT_DeployerAddress,
			msg.sender,
			InfoOracleAddress
		);
		emit FixCapitalPoolDeployment(fixCapitalPoolAddress, _wrapperAddress, msg.sender, _maturity);
		fixCapitalPoolToWrapper[fixCapitalPoolAddress] = _wrapperAddress;
	}

	/*
		@Description: deploy an OrderbookExchange contract
			only one orderbook exchange can be deployed for a specific FCP contract

		@param address _fixCapitalPoolAddress: the address of the FixCapitalPool for which to deploy an OrderbookExchange contract
	*/
	function deployOrderbook(address _fixCapitalPoolAddress) external override {
		require(Orderbooks[_fixCapitalPoolAddress] == address(0));
		address orderbookAddr = OrderbookDeployer(OrderbookDeployerAddress).deploy(_fixCapitalPoolAddress);
		Orderbooks[_fixCapitalPoolAddress] = orderbookAddr;
		emit OrderbookDeployment(orderbookAddr, _fixCapitalPoolAddress);
	}

	//-----------------------------a-d-m-i-n-----------------------------

	/*
		@Description: owner of this contract may override is verified for a specific address
			this is useful in the case that a unique IWrapper contract that is not an NGBwrapper
			is deployed and qualifys to be verified or if the underlying asset behind a verified
			IWrapper is shown to contain malicious code

		@param address _wrapperAddress: the addres of the IWrapper contract for which to set isVerified
		@param bool _setTo: true to verify wrapper, false to unverify wrapper
	*/
	function setVerified(address _wrapperAddress, bool _setTo) external override onlyOwner {
		wrapperIsVerified[_wrapperAddress] = _setTo;
	}

	/*
		@Description: whitelist an IWrapperDeployer contract to deploy new wrapper contracts that shall be whitelisted

		@param address _wrapperDeployerAddress: the address of the IWrapperDeployer contract to whitelist
	*/
	function whitelistWrapperDeployer(address _wrapperDeployerAddress) external override onlyOwner {
		require(IWrapperDeployer(_wrapperDeployerAddress).InfoOracleAddress() == InfoOracleAddress);
		WrapperDeployers.push(_wrapperDeployerAddress);
	}

	/*
		@Description: revoke whitelist status of an IWrapperDeployer contract

		@param uint _index: the index within the WrapperDeployers array at which the IWrapperDeployer to delist is located
	*/
	function delistWrapperDeployer(uint _index) external override onlyOwner {
		require(WrapperDeployers.length > _index);
		WrapperDeployers[_index] = address(0);
	}
}
