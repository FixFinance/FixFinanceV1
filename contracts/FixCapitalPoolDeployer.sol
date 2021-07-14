// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./FixCapitalPool.sol";

contract FixCapitalPoolDeployer {

	/*
		@Description: deploy new FixCapitalPool contract and transfer ownership

		@param address _aw: address of the wrapper for which to deploy a new fix capital pool
		@param uint40 _maturity: the maturity of the new FixCapitalPool
		@param address _yieldTokenDeployer: address of a YieldTokenDeployer contract
		@param address _owner: the address to transfer ownership of the new FixCapitalPool to
		@param address _infoOracleAddress: the address of the FIX infoOracle, this addresss shall
			point to the treasury which shall receive half of all flashloan dividends

		@return address addr: address of the new FixCapitalPool contract
	*/
	function deploy(
		address _aw,
		uint40 _maturity,
		address _yieldTokenDeployer,
		address _owner,
		address _infoOracleAddress
	) public returns (address addr) {

		FixCapitalPool cap = new FixCapitalPool(_aw, _maturity, _yieldTokenDeployer, _infoOracleAddress);
		cap.transferOwnership(_owner);
		addr = address(cap);
	}
}