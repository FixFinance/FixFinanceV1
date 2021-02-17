pragma solidity >=0.6.0;
import "./YTamm.sol";

contract YTammDeployer {

	function deploy(address _ZCBammAddress, address _feeOracleAddress, uint _YTtoLmultiplier) external returns (address) {
		return address(new YTamm(_ZCBammAddress, _feeOracleAddress, _YTtoLmultiplier));
	}
}