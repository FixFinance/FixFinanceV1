pragma solidity >=0.6.0;
import "./CapitalHandler.sol";

contract CapitalHandlerDeployer {

	/*
		@Description: deploy new CapitalHandler contract and transfer ownership

		@param address _aw: address of the wrapper for which to deploy a new capital handler
		@param uint64 _maturity: the maturity of the new CapitalHandler
		@param address _yieldTokenDeployer: address of a YieldTokenDeployer contract
		@param address _owner: the address to transfer ownership of the new CapitalHandler to

		@return address addr: address of the new CapitalHandler contract
	*/
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