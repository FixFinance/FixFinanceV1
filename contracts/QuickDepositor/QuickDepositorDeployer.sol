// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./QuickDepositor.sol";

contract QuickDepositorDeployer {

	function deploy(address _organzierAddress) external returns(address) {
		return address(new QuickDepositor(_organzierAddress));
	}

}