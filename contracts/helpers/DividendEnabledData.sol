pragma solidity >=0.6.0;

import "../interfaces/IWrapper.sol";

contract DividendEnabledData {
	address public ZCBaddress;
	address public YTaddress;

	IWrapper wrapper;

	//the amount of LP shares that are eldigeble to claim interest generated by their funds
	uint public activeTotalSupply;

	uint public lastWithdraw;
	//total amount of smallest denomination units of coin in this smart contract
	uint internal internalTotalSupply;
	//each user's balance of coins
	mapping(address => uint) internal internalBalanceOf;
	//the amount of funds each address has allowed other addresses to spend on the first address's behalf
	//holderOfFunds => spender => amountOfFundsAllowed
	mapping(address => mapping(address => uint)) internal internalAllowance;

    /*
		every time lastWithdraw is updated another value is pushed to contractBalanceAsset1 as contractBalanceAsset2
		thus the length of contractBalanceAsset1 and contractBalanceAsset2 are always the same
		lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	*/
	//lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	mapping(address => uint) lastClaim;
	//U dividends (unit amount) + ZCBdividends *may be negative*
	int[] public contractZCBDividend;
	//increase in wrapped amount of balanceYield
	uint[] public contractYieldDividend;

	//most recent value in non supply normalized dividend integrals
	uint internal totalZCBDividend;
	uint internal totalYTDividend;
	//the total amount of dividends claimed from this contract
	uint internal ZCBdividendOut;
	uint internal YTdividendOut;

}