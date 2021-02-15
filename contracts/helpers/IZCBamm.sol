pragma solidity >=0.6.0;

import "./doubleAssetYieldEnabledToken.sol";

abstract contract IZCBamm is doubleAssetYieldEnabledToken {
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

	uint8 private constant LENGTH_RATE_SERIES = 31;

	function forceRateDataUpdate() external virtual;
	function maturity() external virtual view returns (uint64);
	function anchor() external virtual view returns (uint);
	function firstMint(uint128 _Uin, uint128 _ZCBin) external virtual;
	function mint(uint _amount, uint _maxUin, uint _maxZCBin) external virtual;
	function burn(uint _amount) external virtual;
	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _out);
	function SwapToSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _in);
	function SwapFromSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _minAmtOut) external virtual returns(uint _out);
	function SwapToSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _maxAmtIn) external virtual returns(uint _in);
	function ReserveQuoteFromSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _out);
	function ReserveQuoteToSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _out);
	function TakeQuote(uint _amountIn, uint _amountOut, bool _ZCBin) external virtual;
	function getRateFromOracle() external virtual view returns (int128 rate);
	function getAPYFromOracle() external virtual view returns (int128 APY);
	function getImpliedRateData() external virtual view returns (
		int128[LENGTH_RATE_SERIES] memory _impliedRates,
		uint[LENGTH_RATE_SERIES] memory _timestamps
	);
}