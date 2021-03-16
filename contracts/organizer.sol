pragma solidity >=0.6.0 <0.7.0;
import "./AaveWrapper.sol";
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

	event CapitalHandlerDeployment(
		address addr
	);

	address[] public capitalHandlerInstances;

	mapping(address => address) public assetWrappers;

	mapping(address => address) public capitalHandlerToUnderlyingAsset;

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

	function capitalHandlerInstancesLength() public view returns(uint) {
		return capitalHandlerInstances.length;
	}

	function allCapitalHandlerInstances() public view returns(address[] memory) {
		return capitalHandlerInstances;
	}

	function deployAssetWrapper(address _assetAddress) public {
		require(assetWrappers[_assetAddress] == address(0), "can only make a wrapper if none currently exists");
		assetWrappers[_assetAddress] = address(new AaveWrapper(_assetAddress));
	}

	function deployCapitalHandlerInstance(address _aTokenAddress, uint64 _maturity) public {
		require(_maturity > block.timestamp+(1 weeks), "maturity must be at least 1 weeks away");
		address aaveWrapperAddress = assetWrappers[_aTokenAddress];
		require(aaveWrapperAddress != address(0), "deploy a wrapper for this aToken first");
		address capitalHandlerAddress = CapitalHandlerDeployer(CapitalHandlerDeployerAddress).deploy(aaveWrapperAddress, _maturity, yieldTokenDeployerAddress, msg.sender);
		emit CapitalHandlerDeployment(capitalHandlerAddress);
		capitalHandlerInstances.push(capitalHandlerAddress);
		capitalHandlerToUnderlyingAsset[capitalHandlerAddress] = _aTokenAddress;
	}

	function deployZCBamm(address _capitalHandlerAddress) public {
		require(ZCBamms[_capitalHandlerAddress] == address(0));
		require(capitalHandlerToUnderlyingAsset[_capitalHandlerAddress] != address(0));
		ZCBamms[_capitalHandlerAddress] = ZCBammDeployer(ZCBammDeployerAddress).deploy(_capitalHandlerAddress, AmmInfoOracleAddress);
	}

	function deployYTamm(address _capitalHandlerAddress) public {
		require(YTamms[_capitalHandlerAddress] == address(0));
		address ZCBammAddress = ZCBamms[_capitalHandlerAddress];
		require(ZCBammAddress != address(0));
		YTamms[_capitalHandlerAddress] = YTammDeployer(YTammDeployerAddress).deploy(ZCBammAddress, AmmInfoOracleAddress);
	}

}
