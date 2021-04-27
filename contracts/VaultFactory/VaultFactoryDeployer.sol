pragma solidity >=0.6.0;

import "./VaultFactory.sol";

contract VaultFactoryDeployer {

	event Deploy(
		address addr
	);

	address treasury;
	address delegate;
	address delegate2;

	/*
		init
	*/
	constructor(address _treasury, address _delegate, address _delegate2) public {
		treasury = _treasury;
		delegate = _delegate;
		delegate2 = _delegate2;
	}

	/*
		@Description: deploy new VaultFactory contract

		@param address _vaultHealthAddress: 1st param to be passed to VaultFactory constructor

		@return address: the address of the new VaultFactory contract
	*/
	function deploy(address _vaultHealthAddress) external returns(address) {
		VaultFactory temp = new VaultFactory(_vaultHealthAddress, treasury, delegate, delegate2);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}