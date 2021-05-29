// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./interfaces/IOrganizer.sol";
import "./Wrappers/NGBwrapper.sol";
import "./FixCapitalPool.sol";
import "./amm/ZCBamm/ZCBammDeployer.sol";
import "./amm/YTamm/YTammDeployer.sol";
import "./FixCapitalPoolDeployer.sol";
import "./SwapRouter/SwapRouterDeployer.sol";
import "./SwapRouter/SwapRouter.sol";
import "./helpers/Ownable.sol";
import "./InfoOracle.sol";

contract Organizer is Ownable, IOrganizer {

	/*
		100 sbps (super basis points) is 1 bip (basis point)
		1.0 == 100% == 10_000 bips == 1_000_000 sbps

		DEFAULT_SBPS_RETAINED represents the default value (in super basis points) of
		1.0 - annualWrapperFee
		if SBPSRetained == 999_000 == 1_000_000 - 1000, the annual wrapper fee is 1000sbps or 0.1%
	*/
	uint32 private constant DEFAULT_SBPS_RETAINED = 999_000;

	event WrapperDeployment(
		address wrapperAddress,
		address underlyingAddress,
		uint8 wrapperType
	);

	event FixCapitalPoolDeployment(
		address addr
	);

	//acts as a whitelist for fixCapitalPools that were deployed using this organiser
	mapping(address => address) public override fixCapitalPoolToWrapper;
	//FixCapitalPool => ZCBamm address
	mapping(address => address) public override ZCBamms;
	//FixCapitalPool => YTamm address
	mapping(address => address) public override YTamms;
	//IWrapper => isVerified
	mapping(address => bool) public override wrapperIsVerified;

	address public override yieldTokenDeployerAddress;
	address public override FixCapitalPoolDeployerAddress;
	address public override ZCBammDeployerAddress;
	address public override YTammDeployerAddress;
	address public override SwapRouterAddress;
	address public override InfoOracleAddress;

	address internal SwapRouterDeployerAddress;

	/*
		init
	*/
	constructor (
		address _yieldTokenDeployerAddress,
		address _fixCapitalPoolDeployerAddress,
		address _ZCBammDeployerAddress,
		address _YTammDeployerAddress,
		address _SwapRouterDeployerAddress,
		address _InfoOracleAddress
	) public {
		yieldTokenDeployerAddress = _yieldTokenDeployerAddress;	
		FixCapitalPoolDeployerAddress = _fixCapitalPoolDeployerAddress;
		ZCBammDeployerAddress = _ZCBammDeployerAddress;
		YTammDeployerAddress = _YTammDeployerAddress;
		SwapRouterDeployerAddress = _SwapRouterDeployerAddress;
		InfoOracleAddress = _InfoOracleAddress;
	}

	/*
		@Description: deploy SwapRouter contract,
			this function only need be called once there is no need to redeploy another SwapRouter
	*/
	function DeploySwapRouter() external override {
		require(SwapRouterAddress == address(0));
		SwapRouterAddress = SwapRouterDeployer(SwapRouterDeployerAddress).deploy(address(this));		
	}

	/*
		@Description: deploy a new NGBwrapper and transfer ownership to msg.sender
		
		@param address _underlyingAssetAddress: the NGB asset for which to deploy an NGBwrapper
	*/
	function deployNGBWrapper(address _underlyingAssetAddress) external override {
		NGBwrapper temp = new NGBwrapper(_underlyingAssetAddress, InfoOracleAddress, DEFAULT_SBPS_RETAINED);
		temp.transferOwnership(msg.sender);
		wrapperIsVerified[address(temp)] = true;
		emit WrapperDeployment(address(temp), _underlyingAssetAddress, 0);
	}

	/*
		@Description: deploy a new FixCapitalPool instance, whitelist it in fixCapitalPoolToWrapper mapping

		@param address _wrapperAddress: the address of the IWrapper for which to deploy the FixCapitalPool
		@param uint64 _maturity: the maturity of the new FixCapitalPool to deploy
	*/
	function deployFixCapitalPoolInstance(address _wrapperAddress, uint64 _maturity) external override {
		require(_maturity > block.timestamp+(1 weeks), "maturity must be at least 1 weeks away");
		address fixCapitalPoolAddress = FixCapitalPoolDeployer(FixCapitalPoolDeployerAddress).deploy(
			_wrapperAddress,
			_maturity,
			yieldTokenDeployerAddress,
			msg.sender,
			InfoOracleAddress
		);
		emit FixCapitalPoolDeployment(fixCapitalPoolAddress);
		fixCapitalPoolToWrapper[fixCapitalPoolAddress] = _wrapperAddress;
	}

	/*
		@Description: deploy a ZCBamm for a specific fix capital pool
			only one ZCBamm may only be deployed

		@param address _fixCapitalPoolAddress: the address of the FixCapitalPool for which to deploy a ZCBamm
	*/
	function deployZCBamm(address _fixCapitalPoolAddress) external override {
		require(ZCBamms[_fixCapitalPoolAddress] == address(0));
		require(fixCapitalPoolToWrapper[_fixCapitalPoolAddress] != address(0));
		ZCBamms[_fixCapitalPoolAddress] = ZCBammDeployer(ZCBammDeployerAddress).deploy(_fixCapitalPoolAddress, InfoOracleAddress);
	}

	/*
		@Description: deploy a YTamm for a specific fix capital pool
			only one YTamm may be deployed, a YTamm cannot be deployed until after the ZCBamm for the same
			fix capital pool has been deployed and published the first rate in its native oracle
	*/
	function deployYTamm(address _fixCapitalPoolAddress) external override {
		require(YTamms[_fixCapitalPoolAddress] == address(0));
		address ZCBammAddress = ZCBamms[_fixCapitalPoolAddress];
		require(ZCBammAddress != address(0));
		YTamms[_fixCapitalPoolAddress] = YTammDeployer(YTammDeployerAddress).deploy(ZCBammAddress, InfoOracleAddress);
	}

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
}