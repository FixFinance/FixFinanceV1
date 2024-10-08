// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./DBSFVaultFactory.sol";

contract DBSFVaultFactoryDeployer {

	event Deploy(
		address addr
	);

	address infoOracle;
	address delegate1;
	address delegate2;
	address delegate3;
	address delegate4;
	address delegate5;

	/*
		init
	*/
	constructor(
		address _infoOracle,
		address _delegate1,
		address _delegate2,
		address _delegate3,
		address _delegate4,
		address _delegate5
	) public {
		infoOracle = _infoOracle;
		delegate1 = _delegate1;
		delegate2 = _delegate2;
		delegate3 = _delegate3;
		delegate4 = _delegate4;
		delegate5 = _delegate5;
	}

	/*
		@Description: deploy new DBSFVaultFactory contract

		@param address _vaultHealthAddress: 1st param to be passed to DBSFVaultFactory constructor

		@return address: the address of the new DBSFVaultFactory contract
	*/
	function deploy(address _vaultHealthAddress) external returns(address) {
		DBSFVaultFactory temp = new DBSFVaultFactory(_vaultHealthAddress, infoOracle, delegate1, delegate2, delegate3, delegate4, delegate5);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}