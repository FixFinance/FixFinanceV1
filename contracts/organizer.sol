pragma solidity >=0.6.0 <0.7.0;
import "./NGBwrapper.sol";
import "./CapitalHandler.sol";
import "./amm/ZCBamm.sol";
import "./amm/YTamm.sol";
import "./amm/ZCBammDeployer.sol";
import "./amm/YTammDeployer.sol";
import "./CapitalHandlerDeployer.sol";
import "./SwapRouter/SwapRouterDeployer.sol";
import "./SwapRouter/SwapRouter.sol";
import "./AmmInfoOracle.sol";

contract organizer {

	event WrapperDeployment(
		address wrapperAddress,
		address underlyingAddress
	);

	event CapitalHandlerDeployment(
		address addr
	);

	//acts as a whitelist for capitalHandlers that were deployed using this organiser
	mapping(address => address) public capitalHandlerToWrapper;
	mapping(address => address) public YTamms;
	mapping(address => address) public ZCBamms;

	address public yieldTokenDeployerAddress;
	address public CapitalHandlerDeployerAddress;
	address public ZCBammDeployerAddress;
	address public YTammDeployerAddress;
	address internal SwapRouterDeployerAddress;
	address public SwapRouterAddress;
	address public AmmInfoOracleAddress;

	constructor (
		address _yieldTokenDeployerAddress,
		address _CapitalhandlerDeployerAddress,
		address _ZCBammDeployerAddress,
		address _YTammDeployerAddress,
		address _SwapRouterDeployerAddress,
		address _AmmInfoOracleAddress
		) public {
		yieldTokenDeployerAddress = _yieldTokenDeployerAddress;	
		CapitalHandlerDeployerAddress = _CapitalhandlerDeployerAddress;
		ZCBammDeployerAddress = _ZCBammDeployerAddress;
		YTammDeployerAddress = _YTammDeployerAddress;
		SwapRouterDeployerAddress = _SwapRouterDeployerAddress;
		AmmInfoOracleAddress = _AmmInfoOracleAddress;
	}

	function DeploySwapRouter() external {
		require(SwapRouterAddress == address(0));
		SwapRouterAddress = SwapRouterDeployer(SwapRouterDeployerAddress).deploy(address(this));		
	}

	function deployAssetWrapper(address _assetAddress) public {
		NGBwrapper temp = new NGBwrapper(_assetAddress);
		temp.transferOwnership(msg.sender);
		emit WrapperDeployment(address(temp), _assetAddress);
	}

	function deployCapitalHandlerInstance(address _wrapperAddress, uint64 _maturity) public {
		require(_maturity > block.timestamp+(1 weeks), "maturity must be at least 1 weeks away");
		address capitalHandlerAddress = CapitalHandlerDeployer(CapitalHandlerDeployerAddress).deploy(_wrapperAddress, _maturity, yieldTokenDeployerAddress, msg.sender);
		emit CapitalHandlerDeployment(capitalHandlerAddress);
		capitalHandlerToWrapper[capitalHandlerAddress] = _wrapperAddress;
	}

	function deployZCBamm(address _capitalHandlerAddress) public {
		require(ZCBamms[_capitalHandlerAddress] == address(0));
		require(capitalHandlerToWrapper[_capitalHandlerAddress] != address(0));
		ZCBamms[_capitalHandlerAddress] = ZCBammDeployer(ZCBammDeployerAddress).deploy(_capitalHandlerAddress, AmmInfoOracleAddress);
	}

	function deployYTamm(address _capitalHandlerAddress) public {
		require(YTamms[_capitalHandlerAddress] == address(0));
		address ZCBammAddress = ZCBamms[_capitalHandlerAddress];
		require(ZCBammAddress != address(0));
		YTamms[_capitalHandlerAddress] = YTammDeployer(YTammDeployerAddress).deploy(ZCBammAddress, AmmInfoOracleAddress);
	}

}
