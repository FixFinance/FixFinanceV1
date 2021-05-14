// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./DBSFVaultFactory.sol";

contract DBSFVaultFactoryDeployer {

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
		@Description: deploy new DBSFVaultFactory contract

		@param address _vaultHealthAddress: 1st param to be passed to DBSFVaultFactory constructor

		@return address: the address of the new DBSFVaultFactory contract
	*/
	function deploy(address _vaultHealthAddress) external returns(address) {
		DBSFVaultFactory temp = new DBSFVaultFactory(_vaultHealthAddress, treasury, delegate1, delegate2);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}