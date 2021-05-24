// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../helpers/Ownable.sol";
import "../interfaces/IERC20.sol";
import "../libraries/SafeMath.sol";
import "./interfaces/IOracleContainer.sol";
import "./interfaces/IChainlinkAggregator.sol";

contract OracleContainer is Ownable, IOracleContainer {
	using SafeMath for uint;

	string constant ConcatWith = " / ETH";

	address immutable aETH;

	mapping(string => address) internal PairInfo;
	mapping(address => string) internal Phrases;

	constructor(address _aETH) public {
		aETH = _aETH;
	}

	function addAggregators(address[] memory _facades) public onlyOwner {
		uint length = _facades.length;
		for (uint i = 0; i < length; i++) {
			address facade = _facades[i];
			string memory description = IChainlinkAggregator(facade).description();
			require(PairInfo[description] == address(0));
			PairInfo[description] = facade;
		}
	}

	function AddAToken(address _aTokenAddress, string calldata claim) external onlyOwner {
		require(abi.encodePacked(Phrases[_aTokenAddress]).length == 0);
		Phrases[_aTokenAddress] = claim;
	}

	function BaseAggregatorAddress(string calldata _phrase) external view override returns (address addr) {
		addr = PairInfo[_phrase];
	}

	function AssetPhrase(address _aTokenAddress) external view override returns (string memory phrase) {
		phrase = Phrases[_aTokenAddress];
	}

	/*
		For the purpose of this project we are only worried about this function
	*/
	function phraseToLatestPrice(string calldata _phrase) external view override returns (uint spot, uint8 decimals) {
		address baseAggregatorAddress = PairInfo[_phrase];
		require(baseAggregatorAddress != address(0));
		//we can safely assume that the spot will never be negative and that a conversion to uint will be safe.
		spot = uint(IChainlinkAggregator(baseAggregatorAddress).latestAnswer());
		decimals = IChainlinkAggregator(baseAggregatorAddress).decimals();
	}

	function getAssetPrice(address _assetAddress) external view override returns (uint) {
		if (_assetAddress == aETH) return (1 ether);
		address baseAggregatorAddress = PairInfo[toFullPhrase(Phrases[_assetAddress])];
		require(baseAggregatorAddress != address(0));
		//we can safely assume that the spot will never be negative and that a conversion to uint will be safe.
		uint spot = uint(IChainlinkAggregator(baseAggregatorAddress).latestAnswer());
		require(int(spot) >= 0);
		uint decimals = IChainlinkAggregator(baseAggregatorAddress).decimals();
		return uint(1 ether).mul(spot).div(10**decimals);
	}

	function toFullPhrase(string memory phrase) internal pure returns (string memory) {
		return string(abi.encodePacked(phrase, ConcatWith));
	}

	function removeFirstCharacter(string memory str) internal pure returns (string memory) {
		uint length = bytes(str).length;
		require(length > 1);
		return substring(str, 1, length);
	}

	function stringEquals(string memory a, string memory b) internal pure returns (bool) {
		if(bytes(a).length != bytes(b).length) {
			return false;
		} else {
			return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
		}
   	}

	function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
	    bytes memory strBytes = bytes(str);
	    bytes memory result = new bytes(endIndex-startIndex);
	    for(uint i = startIndex; i < endIndex; i++) {
	        result[i-startIndex] = strBytes[i];
	    }
	    return string(result);
	}
}