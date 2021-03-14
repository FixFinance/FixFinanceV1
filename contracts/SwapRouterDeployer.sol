pragma solidity >=0.6.0;
import "./SwapRouter.sol";

contract SwapRouterDeployer {

	address delegateAddress;

	constructor(address _delegateAddress) public {
		delegateAddress = _delegateAddress;
	}

	function deploy(address _organzierAddress) external returns(address) {
		return address(new SwapRouter(_organzierAddress, delegateAddress));
	}

}

