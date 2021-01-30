pragma solidity >=0.6.0;

interface ISwapRouter {
	function ATknToZCB(address _capitalHandlerAddress, uint _amount) external;

	function ATknToYT(address _capitalHandlerAddress, int128 _amount, uint _maxATkn) external;
/*
	function LiquidateAllToATkn(address _capitalHandler) external;

	function SwapZCBtoYT(address _capitalHandlerAddress, uint _amountYT) external;

	function SwapYTtoZCB(address _capitalHandlerAddress, uint _amountYT) external;

	function SwapZCBtoU(address _capitalHandlerAddress, uint _amountYT) external;

	function SwapUtoZCB(address _capitalHandlerAddress, uint _amountYT) external;
*/
}