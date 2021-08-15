// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./OrderbookExchange.sol";

contract OrderbookDeployer {

	address treasuryAddress;
	address infoOracleAddress;
	address delegate1;
	address delegate2;
	address delegate3;

	constructor(
		address _treasuryAddress,
		address _infoOracleAddress,
		address _delegate1,
		address _delegate2,
		address _delegate3
	) public {
		treasuryAddress = _treasuryAddress;
		infoOracleAddress = _infoOracleAddress;
		delegate1 = _delegate1;
		delegate2 = _delegate2;
		delegate3 = _delegate3;
	}

	function deploy(address _fixCapitalPoolAddress) external returns(address) {
		return address(new OrderbookExchange(
			treasuryAddress,
			_fixCapitalPoolAddress,
			infoOracleAddress,
			delegate1,
			delegate2,
			delegate3
		));
	}
}