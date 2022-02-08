// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../helpers/Ownable.sol";
import "../interfaces/IOrderbookExchange.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IOrganizer.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../oracle/interfaces/IOracleContainer.sol";
import "./VaultHealthData.sol";


contract VaultHealthCoreParent is VaultHealthData {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	address delegate1;
	address delegate2;

	function reqSuccess(bytes memory encodedWithSig) internal returns(bytes memory data) {
		bool success;
		(success, data) = delegate2.delegatecall(encodedWithSig);
		require(success);
	}

	function decodeBool(bytes memory encodedWithSig) internal returns(bool) {
		bytes memory data = reqSuccess(encodedWithSig);
		return abi.decode(data, (bool));
	}

	function decodeUint(bytes memory encodedWithSig) internal returns(uint) {
		bytes memory data = reqSuccess(encodedWithSig);
		return abi.decode(data, (uint));
	}

}