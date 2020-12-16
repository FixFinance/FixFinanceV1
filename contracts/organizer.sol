pragma solidity >=0.6.0 <0.7.0;
import "./aaveWrapper.sol";
import "./capitalHandler.sol";

contract organizer {

	address[] public capitalHandlerInstances;

	mapping(address => address) public aTokenWrappers;

	//aToken => maturity of bond => capitalHandler
	mapping(address => mapping(uint64 => address)) public capitalHandlerMapping;

	address public yieldTokenDeployerAddress;
	address public bondMinterAddress;

	constructor (address _yieldTokenDeployerAddress, address _bondMinterAddress) public {
		yieldTokenDeployerAddress = _yieldTokenDeployerAddress;	
		bondMinterAddress = _bondMinterAddress;
	}

	function capitalHandlerInstancesLength() public view returns(uint) {
		return capitalHandlerInstances.length;
	}

	function allCapitalHandlerInstances() public view returns(address[] memory) {
		return capitalHandlerInstances;
	}

	function deployATokenWrapper(address _aTokenAddress) public {
		require(aTokenWrappers[_aTokenAddress] == address(0), "can only make a wrapper if none currently exists");
		aTokenWrappers[_aTokenAddress] = address(new aaveWrapper(_aTokenAddress));
	}

	function deployCapitalHandlerInstance(address _aTokenAddress, uint64 _maturity) public {
		require(_maturity > block.timestamp+(1 weeks), "maturity must be at least 1 weeks away");
		require(capitalHandlerMapping[_aTokenAddress][_maturity] == address(0), "capital handler with these parameters already exists");
		address aaveWrapperAddress = aTokenWrappers[_aTokenAddress];
		require(aaveWrapperAddress != address(0), "deploy a wrapper for this aToken first");
		address capitalHandlerAddress = address(new capitalHandler(aaveWrapperAddress, _maturity, yieldTokenDeployerAddress, bondMinterAddress));
		capitalHandlerInstances.push(capitalHandlerAddress);
		capitalHandlerMapping[_aTokenAddress][_maturity] = capitalHandlerAddress;
	}
}
