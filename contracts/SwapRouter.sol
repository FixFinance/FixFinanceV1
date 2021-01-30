pragma solidity >=0.6.0;
import "./helpers/IZCBamm.sol";
import "./helpers/IYTamm.sol";
import "./interfaces/ICapitalHandler.sol";
import "./interfaces/IYieldToken.sol";
import "./interfaces/IAaveWrapper.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/IERC20.sol";
import "./organizer.sol";

contract SwapRouter is ISwapRouter {
	organizer org;

	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

	constructor(address _organizerAddress) public {
		org = organizer(_organizerAddress);
	}

	function ATknToZCB(address _capitalHandlerAddress, uint _amount) external override {
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		organizer _org = org;
		IERC20 aToken = IERC20(_org.capitalHandlerToAToken(_capitalHandlerAddress));
		IAaveWrapper aw = IAaveWrapper(_org.aTokenWrappers(address(aToken)));
		IZCBamm amm = IZCBamm(_org.ZCBamms(_capitalHandlerAddress));
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());

		aToken.transferFrom(msg.sender, address(this), _amount);
		aToken.approve(address(aw), _amount);
		uint _amountWrapped = aw.deposit(address(this), _amount);
		aw.approve(_capitalHandlerAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		ch.approve(address(amm), _amount);
		yt.approve(address(amm), _amountWrapped);
		uint _amountToSwap = aw.WrappedTokenToAToken_RoundUp(_amountWrapped);
		require(_amountToSwap <= uint(MAX));
		uint _out = amm.SwapFromSpecificTokens(int128(_amountToSwap), false);
		ch.transfer(msg.sender, _out);
	}

/*
	function WrappedATknToYT(address _capitalHandlerAddress, uint _amount) external {}

	function LiquidateAllToATkn(address _capitalHandler) external {}

	function SwapZCBtoYT(address _capitalHandlerAddress, uint _amountYT) external {}

	function SwapYTtoZCB(address _capitalHandlerAddress, uint _amountYT) external {}

	function SwapZCBtoU(address _capitalHandlerAddress, uint _amountYT) external {}

	function SwapUtoZCB(address _capitalHandlerAddress, uint _amountYT) external {}
*/
}
