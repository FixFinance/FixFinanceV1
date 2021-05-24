// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./SwapRouter.sol";

contract SwapRouterDeployer {

	address delegateAddress;

	/*
		Init
	*/
	constructor(address _delegateAddress) public {
		delegateAddress = _delegateAddress;
	}

	/*
		@Description: deploy a new Swap Router contract

		@param address _organizerAddress: the address of the organizer contract for which
			to deploy a SwapRouter contract

		@return address: the address of the newly deployed SwapRouter contract
	*/
	function deploy(address _organzierAddress) external returns(address) {
		return address(new SwapRouter(_organzierAddress, delegateAddress));
	}

}

