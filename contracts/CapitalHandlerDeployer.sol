pragma solidity >=0.6.0;
import "./CapitalHandler.sol";

contract CapitalHandlerDeployer {

	function deploy(
		address _aw,
		uint64 _maturity,
		address _yieldTokenDeployer,
		address _owner
		) public returns (address addr) {

		CapitalHandler cap = new CapitalHandler(_aw, _maturity, _yieldTokenDeployer);
		cap.transferOwnership(_owner);
		addr = address(cap);
	}
}