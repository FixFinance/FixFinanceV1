// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./IWrapper.sol";

interface INGBWrapper is IWrapper {
	function prevRatio() external view returns(uint);
	function lastHarvest() external view returns(uint);
}