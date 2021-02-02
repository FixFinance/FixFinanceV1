pragma solidity >=0.6.0;
import "./SwapRouter.sol";

contract SwapRouterDeployer {

	function deploy(address _organzierAddress) external returns(address) {
		return address(new SwapRouter(_organzierAddress));
	}

}

