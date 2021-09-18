// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./IERC20.sol";

interface ICToken is IERC20 {
	function balanceOfUnderlying(address _owner) external returns (uint);
    function exchangeRateStored() external view returns (uint);
	function underlying() external view returns (address);
}