pragma solidity >=0.6.0;
import "./YTamm.sol";

contract YTammDeployer {

	function deploy(address _ZCBammAddress, uint32 _YTtoLmultiplier) external returns (address) {
		return address(new YTamm(_ZCBammAddress, _YTtoLmultiplier));
	}
}