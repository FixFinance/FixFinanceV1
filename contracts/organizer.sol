pragma solidity >=0.6.0 <0.7.0;
import "./AaveWrapper.sol";
import "./CapitalHandler.sol";
import "./amm/ZCBamm.sol";
import "./amm/YTamm.sol";
import "./amm/ZCBammDeployer.sol";
import "./amm/YTammDeployer.sol";
import "./CapitalHandlerDeployer.sol";
import "./SwapRouterDeployer.sol";
import "./SwapRouter.sol";
import "./FeeOracle.sol";

contract organizer {

	address[] public capitalHandlerInstances;

	mapping(address => address) public assetWrappers;

	//underlyingAsset => maturity of bond => capitalHandler
	mapping(address => mapping(uint64 => address)) public capitalHandlerMapping;
	mapping(address => address) public capitalHandlerToUnderlyingAsset;

	mapping(address => address) public YTamms;
	mapping(address => address) public ZCBamms;

	address public yieldTokenDeployerAddress;
	address public bondMinterAddress;
	address public CapitalHandlerDeployerAddress;
	address public ZCBammDeployerAddress;
	address public YTammDeployerAddress;
	address internal SwapRouterDeployerAddress;
	address public SwapRouterAddress;
	address public FeeOracleAddress;

	constructor (
		address _yieldTokenDeployerAddress,
		address _bondMinterAddress,
		address _CapitalhandlerDeployerAddress,
		address _ZCBammDeployerAddress,
		address _YTammDeployerAddress,
		address _SwapRouterDeployerAddress,
		address _feeOracleAddress
		) public {
		yieldTokenDeployerAddress = _yieldTokenDeployerAddress;	
		bondMinterAddress = _bondMinterAddress;
		CapitalHandlerDeployerAddress = _CapitalhandlerDeployerAddress;
		ZCBammDeployerAddress = _ZCBammDeployerAddress;
		YTammDeployerAddress = _YTammDeployerAddress;
		SwapRouterDeployerAddress = _SwapRouterDeployerAddress;
		FeeOracleAddress = _feeOracleAddress;
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
		require(capitalHandlerMapping[_aTokenAddress][_maturity] == address(0), "capital handler with these parameters already exists");
		address aaveWrapperAddress = assetWrappers[_aTokenAddress];
		require(aaveWrapperAddress != address(0), "deploy a wrapper for this aToken first");
		address capitalHandlerAddress = CapitalHandlerDeployer(CapitalHandlerDeployerAddress).deploy(aaveWrapperAddress, _maturity, yieldTokenDeployerAddress, bondMinterAddress);
		capitalHandlerInstances.push(capitalHandlerAddress);
		capitalHandlerMapping[_aTokenAddress][_maturity] = capitalHandlerAddress;
		capitalHandlerToUnderlyingAsset[capitalHandlerAddress] = _aTokenAddress;
	}

	function deployZCBamm(address _capitalHandlerAddress) public {
		require(ZCBamms[_capitalHandlerAddress] == address(0));
		require(capitalHandlerToUnderlyingAsset[_capitalHandlerAddress] != address(0));
		ZCBamms[_capitalHandlerAddress] = ZCBammDeployer(ZCBammDeployerAddress).deploy(_capitalHandlerAddress, FeeOracleAddress);
	}

	function deployYTamm(address _capitalHandlerAddress) public {
		require(YTamms[_capitalHandlerAddress] == address(0));
		address ZCBammAddress = ZCBamms[_capitalHandlerAddress];
		require(ZCBammAddress != address(0));
		YTamms[_capitalHandlerAddress] = YTammDeployer(YTammDeployerAddress).deploy(ZCBammAddress, FeeOracleAddress);
	}

}
