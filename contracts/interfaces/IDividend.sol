pragma solidity >=0.4.21 <0.7.0;

interface  IDividend {
	/*
		@Description: allows users to claim their share of the total dividends of the contract based on their portion of totalYield compared to the total supply
	*/
	function claimDividend(address _to) external;
	function contractClaimDividend() external;
}