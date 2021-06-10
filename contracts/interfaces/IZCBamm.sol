// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IERC20.sol";

interface IZCBamm is IERC20 {
	event Mint(
		address user,
		uint amount
	);
	event Burn(
		address user,
		uint amount
	);
	event Swap(
		address user,
		uint amountZCB,
		uint amountU,
		bool ZCBin
	);
	function ZCBaddress() external view returns(address);
	function YTaddress() external view returns(address);
	function FCPaddress() external view returns(address);
	function forceRateDataUpdate() external;
	function maturity() external view returns (uint64);
	function anchor() external view returns (uint);
	function nextAnchor() external view returns (uint);
	function firstMint(uint128 _Uin, uint128 _ZCBin) external;
	function mint(uint _amount, uint _maxUin, uint _maxZCBin) external;
	function burn(uint _amount) external;
	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) external returns(uint _out);
	function SwapToSpecificTokens(int128 _amount, bool _ZCBin) external returns(uint _in);
	function SwapFromSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _minAmtOut) external returns(uint _out);
	function SwapToSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _maxAmtIn) external returns(uint _in);
	function ReserveQuoteFromSpecificTokens(int128 _amount, bool _ZCBin) external returns(uint _out);
	function ReserveQuoteToSpecificTokens(int128 _amount, bool _ZCBin) external returns(uint _out);
	function TakeQuote(uint _amountIn, uint _amountOut, bool _ZCBin, bool _ToSpecific) external;
	function recalibrate(uint lowerBoundAnchor, uint upperBoundAnchor) external;
	function inflatedTotalSupply() external view returns (uint);
	function getRateFromOracle() external view returns (int128 rate);
	function getAPYFromOracle() external view returns (int128 APY);
	function impliedYieldToMaturity() external view returns (int128 yield);
	function impliedYieldOverYears(int128 _years) external view returns (int128 yield);
	function getImpliedRateData() external view returns (
		int128[31] memory _impliedRates,
		uint[31] memory _timestamps
	);
	function getReserves() external view returns (
		uint _Ureserves,
		uint _ZCBreserves,
		uint _TimeRemaining
	);
}