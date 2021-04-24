pragma solidity >=0.6.0;
import "./FixCapitalPool.sol";

contract FixCapitalPoolDeployer {

	/*
		@Description: deploy new FixCapitalPool contract and transfer ownership

		@param address _aw: address of the wrapper for which to deploy a new fix capital pool
		@param uint64 _maturity: the maturity of the new FixCapitalPool
		@param address _yieldTokenDeployer: address of a YieldTokenDeployer contract
		@param address _owner: the address to transfer ownership of the new FixCapitalPool to

		@return address addr: address of the new FixCapitalPool contract
	*/
	function deploy(
		address _aw,
		uint64 _maturity,
		address _yieldTokenDeployer,
		address _owner
	) public returns (address addr) {

		FixCapitalPool cap = new FixCapitalPool(_aw, _maturity, _yieldTokenDeployer);
		cap.transferOwnership(_owner);
		addr = address(cap);
	}
}