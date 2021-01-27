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

	function maturity() external virtual view returns (uint64);
	function anchor() external virtual view returns (uint);
	function firstMint(uint128 _Uin, uint128 _ZCBin) external virtual;
	function mint(uint _amount, uint _maxUin, uint _maxZCBin) external virtual;
	function burn(uint _amount) external virtual;
	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) external virtual;
	function SwapToSpecificTokens(int128 _amount, bool _ZCBout) external virtual;
	function getRateFromOracle() external virtual view returns (int128 rate);
	function getAPYFromOracle() external virtual view returns (int128 APY);
	function getImpliedRateData() external virtual view returns (
		int128 impliedRate0,
		int128 impliedRate1,
		int128 impliedRate2,
		uint height0,
		uint height1,
		uint height2
	);
}