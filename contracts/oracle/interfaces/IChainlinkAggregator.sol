// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

/*
	This interface only has the functions that we will need
	to access elsewhere in the program it does not contain all
	the functions implemented by the chainlink aggregator contracts
*/

interface IChainlinkAggregator {
	function description() external view returns(string memory);
	function decimals() external view returns (uint8);
	function latestAnswer() external view returns (int256);
	function latestRound() external view returns (uint256);
	function getAnswer(uint256 roundId) external view returns (int256);
	function getTimestamp(uint256 roundId) external view returns (uint256);
}
