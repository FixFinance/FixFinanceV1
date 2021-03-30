pragma solidity >=0.6.0 <0.7.0;
import "./Wrappers/NGBwrapper.sol";
import "./CapitalHandler.sol";
import "./amm/ZCBamm/ZCBammDeployer.sol";
import "./amm/YTamm/YTammDeployer.sol";
import "./CapitalHandlerDeployer.sol";
import "./SwapRouter/SwapRouterDeployer.sol";
import "./SwapRouter/SwapRouter.sol";
import "./AmmInfoOracle.sol";

contract organizer {

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

	event CapitalHandlerDeployment(
		address addr
	);

	//acts as a whitelist for capitalHandlers that were deployed using this organiser
	mapping(address => address) public capitalHandlerToWrapper;
	//CapitalHandler => ZCBamm address
	mapping(address => address) public ZCBamms;
	//CapitlHandler => YTamm address
	mapping(address => address) public YTamms;

	address public yieldTokenDeployerAddress;
	address public CapitalHandlerDeployerAddress;
	address public ZCBammDeployerAddress;
	address public YTammDeployerAddress;
	address public SwapRouterAddress;
	address public AmmInfoOracleAddress;
	address public treasuryAddress;

	address internal SwapRouterDeployerAddress;

	/*
		init
	*/
	constructor (
		address _yieldTokenDeployerAddress,
		address _CapitalhandlerDeployerAddress,
		address _ZCBammDeployerAddress,
		address _YTammDeployerAddress,
		address _SwapRouterDeployerAddress,
		address _AmmInfoOracleAddress,
		address _treasuryAddress
	) public {
		yieldTokenDeployerAddress = _yieldTokenDeployerAddress;	
		CapitalHandlerDeployerAddress = _CapitalhandlerDeployerAddress;
		ZCBammDeployerAddress = _ZCBammDeployerAddress;
		YTammDeployerAddress = _YTammDeployerAddress;
		SwapRouterDeployerAddress = _SwapRouterDeployerAddress;
		AmmInfoOracleAddress = _AmmInfoOracleAddress;
		treasuryAddress = _treasuryAddress;
	}

	/*
		@Description: deploy SwapRouter contract,
			this function only need be called once there is no need to redeploy another SwapRouter
	*/
	function DeploySwapRouter() external {
		require(SwapRouterAddress == address(0));
		SwapRouterAddress = SwapRouterDeployer(SwapRouterDeployerAddress).deploy(address(this));		
	}

	/*
		@Description: deploy a new NGBwrapper and transfer ownership to msg.sender
		
		@param address _assetAddress: the NGB asset for which to deploy an NGBwrapper
	*/
	function deployAssetWrapper(address _assetAddress) public {
		NGBwrapper temp = new NGBwrapper(_assetAddress, treasuryAddress, DEFAULT_SBPS_RETAINED);
		temp.transferOwnership(msg.sender);
		emit WrapperDeployment(address(temp), _assetAddress, 0);
	}

	/*
		@Description: deploy a new CapitalHandler instance, whitelist it in capitalHandlerToWrapper mapping

		@param address _wrapperAddress: the address of the IWrapper for which to deploy the CapitalHandler
		@param uint64 _maturity: the maturity of the new CapitalHandler to deploy
	*/
	function deployCapitalHandlerInstance(address _wrapperAddress, uint64 _maturity) public {
		require(_maturity > block.timestamp+(1 weeks), "maturity must be at least 1 weeks away");
		address capitalHandlerAddress = CapitalHandlerDeployer(CapitalHandlerDeployerAddress).deploy(_wrapperAddress, _maturity, yieldTokenDeployerAddress, msg.sender);
		emit CapitalHandlerDeployment(capitalHandlerAddress);
		capitalHandlerToWrapper[capitalHandlerAddress] = _wrapperAddress;
	}

	/*
		@Description: deploy a ZCBamm for a specific capital handler
			only one ZCBamm may only be deployed

		@param address _capitalHandlerAddress: the address of the CapitalHandler for which to deploy a ZCBamm
	*/
	function deployZCBamm(address _capitalHandlerAddress) public {
		require(ZCBamms[_capitalHandlerAddress] == address(0));
		require(capitalHandlerToWrapper[_capitalHandlerAddress] != address(0));
		ZCBamms[_capitalHandlerAddress] = ZCBammDeployer(ZCBammDeployerAddress).deploy(_capitalHandlerAddress, AmmInfoOracleAddress);
	}

	/*
		@Description: deploy a YTamm for a specific capital handler
			only one YTamm may be deployed, a YTamm cannot be deployed until after the ZCBamm for the same
			capital handler has been deployed and published the first rate in its native oracle
	*/
	function deployYTamm(address _capitalHandlerAddress) public {
		require(YTamms[_capitalHandlerAddress] == address(0));
		address ZCBammAddress = ZCBamms[_capitalHandlerAddress];
		require(ZCBammAddress != address(0));
		YTamms[_capitalHandlerAddress] = YTammDeployer(YTammDeployerAddress).deploy(ZCBammAddress, AmmInfoOracleAddress);
	}

}
