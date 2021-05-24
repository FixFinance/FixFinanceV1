// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./OracleContainer.sol";

contract OracleDeployer {

	event Deploy(
		address addr
	);

	function deploy(address _WETH) external returns(address) {
		OracleContainer temp = new OracleContainer(_WETH);
		temp.transferOwnership(msg.sender);
		emit Deploy(address(temp));
		return address(temp);
	}

}