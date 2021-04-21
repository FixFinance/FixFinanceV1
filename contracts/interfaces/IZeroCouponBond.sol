pragma solidity >=0.6.0;

import "./IERC20.sol";

interface IZeroCouponBond is IERC20 {
	function CapitalHandlerAddress() external view returns(address);
	function maturity() external view returns(uint);

	//only callable by corresponding CapitalHandler
	function decrementAllowance(address _owner, address _spender, uint _amount) external;
}