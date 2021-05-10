// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

interface IOracleContainer {
	function phraseToLatestPrice(string calldata _phrase) external view returns (uint spot, uint8 decimals);
	function getAssetPrice(address _assetAddress) external view returns (uint);

	function BaseAggregatorAddress(string calldata _phrase) external view returns (address);
	function AssetPhrase(address _aTokenAddress) external view returns (string memory phrase);
}