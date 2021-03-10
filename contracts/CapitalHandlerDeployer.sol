pragma solidity >=0.6.0;
import "./CapitalHandler.sol";

contract CapitalHandlerDeployer {
	event CapitalHandlerDeployment(
		address addr
	);

	function deploy(
		address _aw,
		uint64 _maturity,
		address _yieldTokenDeployer,
		address _bondMinterAddress
		) public returns (address addr) {

		addr = address(new CapitalHandler(_aw, _maturity, _yieldTokenDeployer, _bondMinterAddress));
		emit CapitalHandlerDeployment(addr);
	}
}