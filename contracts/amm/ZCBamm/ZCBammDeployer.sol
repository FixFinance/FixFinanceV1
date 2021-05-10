// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
import "./ZCBamm.sol";

contract ZCBammDeployer {

	/*
		@Description: create a new ZCBamm contract

		@param address _ZCBammAddress: used as 1st param in creation of ZCBamm contract
		@param address _feeOracleAddress: used as 2nd param in creation of ZCBamm contract

		@return address: the address of the new ZCBamm contract
	*/
	function deploy(address _FixCapitalPoolAddress, address _feeOracleAddress) external returns (address) {
		return address(new ZCBamm(_FixCapitalPoolAddress, _feeOracleAddress));
	}
}