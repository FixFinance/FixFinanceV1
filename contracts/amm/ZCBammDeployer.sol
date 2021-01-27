pragma solidity >=0.6.0;
import "./ZCBamm.sol";

contract ZCBammDeployer {

	function deploy(address _CapitalHandlerAddress) external returns (address) {
		return address(new ZCBamm(_CapitalHandlerAddress));
	}
}