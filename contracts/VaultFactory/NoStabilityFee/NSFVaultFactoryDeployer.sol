// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./NSFVaultFactory.sol";

contract NSFVaultFactoryDeployer {

	event Deploy(
		address addr
	);

	address treasury;
	address delegate1;
	address delegate2;

	/*
		init
	*/
	constructor(
		address _treasury,
		address _delegate1,
		address _delegate2
	) public {
		treasury = _treasury;
		delegate1 = _delegate1;
		delegate2 = _delegate2;
	}

	/*
		@Description: deploy new NSFVaultFactory contract

		@param address _vaultHealthAddress: 1st param to be passed to NSFVaultFactory constructor

		@return address: the address of the new NSFVaultFactory contract
	*/
	function deploy(address _vaultHealthAddress) external returns(address) {
		NSFVaultFactory temp = new NSFVaultFactory(_vaultHealthAddress, treasury, delegate1, delegate2);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}