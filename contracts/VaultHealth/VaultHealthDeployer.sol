pragma solidity >=0.6.0;

import "./VaultHealth.sol";

contract VaultHealthDeployer {

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
		VaultHealth temp = new VaultHealth(_oracleContainerAddress);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}