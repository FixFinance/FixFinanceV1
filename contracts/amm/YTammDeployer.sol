pragma solidity >=0.6.0;
import "./YTamm.sol";

contract YTammDeployer {

	/*
		@Description: create a new YTamm contract

		@param address _ZCBammAddress: used as 1st param in creation of YTamm contract
		@param address _feeOracleAddress: used as 2nd param in creation of YTamm contract

		@return address: the address of the new YTamm contract
	*/
	function deploy(address _ZCBammAddress, address _feeOracleAddress) external returns (address) {
		return address(new YTamm(_ZCBammAddress, _feeOracleAddress));
	}
}