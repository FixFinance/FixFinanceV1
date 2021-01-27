pragma solidity >=0.6.0;

import "./doubleAssetYieldEnabledToken.sol";

abstract contract IYTamm is doubleAssetYieldEnabledToken {
	function ZCBammAddress() external virtual view returns (address);
	function maturity() external virtual view returns (uint64);
	function anchor() external virtual view returns (uint);
	function firstMint(uint128 _Uin) external virtual;
	function mint(uint _amount, uint _maxUin, uint _maxYTin) external virtual;
	function burn(uint _amount) external virtual;
	function SwapFromSpecificYT(int128 _amount) external virtual;
	function SwapToSpecificYT(int128 _amount) external virtual;
}
