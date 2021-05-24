// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

contract IYTammData {

	address public ZCBammAddress;
	uint64 public maturity;
	uint YTreserves;
	uint Ureserves;
	address InfoOracleAddress;
	bytes32 quoteSignature;
	int128 quotedAmountYT;
	uint256 quotedAmountU;
	uint256 quotedTreasuryFee;
	uint public lastRecalibration;
	uint public YTtoLmultiplier;
	uint public SlippageConstant;

	address public FCPaddress;

	uint internal constant SecondsPerYear = 31556926;
	int128 internal constant _2WeeksABDK = int128((2 weeks << 64)/SecondsPerYear);
}