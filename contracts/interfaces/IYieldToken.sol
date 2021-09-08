// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IERC20.sol";

interface IYieldToken is IERC20 {
	function FixCapitalPoolAddress() external view returns(address);
	function WrapperAddress() external view returns(address);
	function maturity() external view returns(uint);
	function lastUpdate() external view returns(uint);

	function balanceOf_2(address _owner, bool _roundUp) external view returns (uint);
	function transfer_2(address _to, uint256 _value, bool _roundUp) external;
	function approve_2(address _spender, uint256 _value, bool _roundUp) external;
	function transferFrom_2(address _from, address _to, uint256 _value, bool _roundUp) external;

	//only callable by corresponding FixCapitalPool
	function decrementAllowance(address _owner, address _spender, uint _amount) external;
	function setAllowance(address _owner, address _spender, uint _allowance) external;
}