pragma solidity >=0.6.0;

interface ISwapRouter {
	function UnitToZCB(address _fixCapitalPoolAddress, uint _amount, uint _minZCBout) external;
	function UnitToYT(address _fixCapitalPoolAddress, int128 _amount, uint _maxATkn) external;
	function LiquidateAllToUnderlying(address _fixCapitalPoolAddress, uint _minUout, bool _unwrap) external;
	function LiquidateSpecificToUnderlying(address _fixCapitalPoolAddress, uint _amountZCB, uint _amountYT, uint _minUout, bool _unwrap) external;
	function SwapZCBtoYT(address _fixCapitalPoolAddress, uint _amountYT, uint _maxZCBin) external;
	function SwapYTtoZCB(address _fixCapitalPoolAddress, uint _amountYT, uint _minZCBout) external;
	function SwapZCBtoYT_ZCBamm(address _fixCapitalPoolAddress, uint _amountYT, uint _maxZCBin) external;
	function SwapYTtoZCB_ZCBamm(address _fixCapitalPoolAddress, uint _amountYT, uint _minZCBout) external;
	function SwapUtoYT_ZCBamm(address _fixCapitalPoolAddress, uint _amountYT, int128 _Uin) external;
	function SwapYTtoU_ZCBamm(address _fixCapitalPoolAddress, uint _amountYT, uint _minUout) external;
}