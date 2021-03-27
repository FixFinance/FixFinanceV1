pragma solidity >=0.6.0;

import "./MarginManager.sol";

contract MarginManagerDeployer {

	event Deploy(
		address addr
	);

	address delegate;

	/*
		init
	*/
	constructor(address _delegate) public {
		delegate = _delegate;
	}

	/*
		@Description: deploy new MarginManager contract

		@param address _vaultHealthAddress: 1st param to be passed to MarginManager constructor

		@return address: the address of the new MarginManager contract
	*/
	function deploy(address _vaultHealthAddress) external returns(address) {
		MarginManager temp = new MarginManager(_vaultHealthAddress, delegate);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}
}