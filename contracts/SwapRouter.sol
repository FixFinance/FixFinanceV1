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

	uint private constant MinBalance = 0x1000;

	uint private constant RoudingBuffer = 0x10;

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

	function ATknToYT(address _capitalHandlerAddress, int128 _amountYT, uint _maxATkn) external override {
		_amountYT++;	//account for rounding error when transfering funds out of YTamm
		require(_amountYT > 0);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		organizer _org = org;
		IERC20 aToken = IERC20(_org.capitalHandlerToAToken(_capitalHandlerAddress));
		IAaveWrapper aw = IAaveWrapper(_org.aTokenWrappers(address(aToken)));
		IYTamm amm = IYTamm(_org.YTamms(_capitalHandlerAddress));
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());

		uint _amtATkn = amm.ReserveQuoteToYT(_amountYT);
		//remove possibility for problems due to rounding error
		uint _amtTransfer = _amtATkn + 100;
		require(_amtTransfer <= _maxATkn, "Required AToken in is Greater than _maxATkn");

		aToken.transferFrom(msg.sender, address(this), _amtTransfer);
		aToken.approve(address(aw), _amtTransfer);
		uint _amountWrapped = aw.deposit(address(this), _amtTransfer);
		aw.approve(_capitalHandlerAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		ch.approve(address(amm), _amtTransfer);
		yt.approve(address(amm), _amountWrapped);
		amm.TakeQuote(_maxATkn, int128(_amountYT), false);
		yt.transfer(msg.sender, yt.balanceOf(address(this)));
	}

	function LiquidateAllToUnderlying(address _capitalHandlerAddress, uint _minUfromZCB, uint _minUfromYT, uint _minTotalUout, bool _unwrap) external override {
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		organizer _org = org;
		IZCBamm zAmm = IZCBamm(_org.ZCBamms(_capitalHandlerAddress));
		IYTamm yAmm = IYTamm(_org.YTamms(_capitalHandlerAddress));

		uint _balanceZCB = ch.balanceOf(msg.sender);
		uint _balanceYT = yt.balanceOf_2(msg.sender, false);
		uint _Uout;
		if (_balanceZCB > MinBalance && _balanceZCB < uint(MAX)) {
			ch.transferFrom(msg.sender, address(this), _balanceZCB);
			ch.approve(address(zAmm), _balanceZCB);
			uint temp = zAmm.SwapFromSpecificTokens(int128(_balanceZCB), true);
			require(temp >= _minUfromZCB);
			_Uout += temp;
		}
		if (_balanceYT > MinBalance && _balanceYT < uint(MAX)) {
			yt.transferFrom_2(msg.sender, address(this), _balanceYT, false);
			yt.approve_2(address(yAmm), _balanceYT, false);
			uint temp = yAmm.SwapFromSpecificYT(int128(_balanceYT));
			require(temp >= _minUfromYT);
			_Uout += temp;
		}
		require(_Uout >= _minTotalUout);
		ch.withdrawAll(msg.sender, _unwrap);
	}

	function SwapZCBtoYT(address _capitalHandlerAddress, uint _amountYT, uint _maxZCBin) external override {
		require(_amountYT < uint(MAX));
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		organizer _org = org;
		IZCBamm zAmm = IZCBamm(_org.ZCBamms(_capitalHandlerAddress));
		IYTamm yAmm = IYTamm(_org.YTamms(_capitalHandlerAddress));

		//force rate update so that rate is not updated upon zAmm call thus invalidating the quote in the yAmm
		zAmm.forceRateDataUpdate();

		uint _amtU = yAmm.ReserveQuoteToYT(int128(_amountYT+RoudingBuffer));
		uint _amtZCB = zAmm.ReserveQuoteToSpecificTokens(int128(_amtU+RoudingBuffer), true);
		require(_amtZCB <= _maxZCBin);
		ch.transferFrom(msg.sender, address(this), _amtZCB);
		ch.approve(address(zAmm), _amtZCB);
		zAmm.TakeQuote(_amtZCB, _amtU+RoudingBuffer, true);
		//approvals for before yAmm swap
		ch.approve(address(yAmm), _amtU);
		yt.approve_2(address(yAmm), _amtU, true);
		yAmm.TakeQuote(_amtU, int128(_amountYT+RoudingBuffer), false);
		yt.transfer(msg.sender, yt.balanceOf(address(this)));
	}
/*
	function SwapYTtoZCB(address _capitalHandlerAddress, uint _amountYT) external override {}

	function SwapZCBtoU(address _capitalHandlerAddress, uint _amountYT) external override {}

	function SwapUtoZCB(address _capitalHandlerAddress, uint _amountYT) external override {}
*/
}
