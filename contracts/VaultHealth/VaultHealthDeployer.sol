// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./VaultHealth.sol";

contract VaultHealthDeployer {

	address delegate1;
	address delegate2;

	constructor(address _delegate1, address _delegate2) public {
		delegate1 = _delegate1;
		delegate2 = _delegate2;
	}

	event Deploy(
		address addr
	);

	/*
		@Description: depoy a new VaultHealth contract

		@param address _oracleContainerAddress: the address that shall be passed as the first
			param to the VaultHealth contructor

		@returns address: the address of the newly deployed VaultHealth contract
	*/
	function deploy(address _oracleContainerAddress) external returns(address) {
		VaultHealth temp = new VaultHealth(_oracleContainerAddress, delegate1, delegate2);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}