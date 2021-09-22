// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./IERC20.sol";

interface ICToken is IERC20 {
    function exchangeRateStored() external view returns (uint);
}