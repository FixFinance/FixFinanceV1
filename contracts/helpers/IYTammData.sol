pragma solidity >=0.6.0;

contract IYTammData {

	address public ZCBammAddress;
	uint64 public maturity;
	uint YTreserves;
	uint Ureserves;
	address AmmInfoOracleAddress;
	bytes32 quoteSignature;
	int128 quotedAmountYT;
	uint256 quotedAmountU;
	uint256 quotedTreasuryFee;
	uint public lastRecalibration;
	uint public YTtoLmultiplier;
	uint public SlippageConstant;
}