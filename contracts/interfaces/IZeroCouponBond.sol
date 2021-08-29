// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./IERC20.sol";

interface IZeroCouponBond is IERC20 {
	function FixCapitalPoolAddress() external view returns(address);
	function WrapperAddress() external view returns(address);
	function maturity() external view returns(uint);
	function lastUpdate() external view returns(uint);

	//only callable by corresponding FixCapitalPool
	function decrementAllowance(address _owner, address _spender, uint _amount) external;
    function setAllowance(address _owner, address _spender, uint _allowance) external;
}