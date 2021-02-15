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

	uint private constant RoundingBuffer = 0x10;

	constructor(address _organizerAddress) public {
		org = organizer(_organizerAddress);
	}

	function ATknToZCB(address _capitalHandlerAddress, uint _amount, uint _minZCBout) external override {
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
		uint _out = amm.SwapFromSpecificTokensWithLimit(int128(_amountToSwap), false, _minZCBout);
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
		uint _amtTransfer = _amtATkn + RoundingBuffer;
		require(_amtTransfer <= _maxATkn, "Required AToken in is Greater than _maxATkn");

		aToken.transferFrom(msg.sender, address(this), _amtTransfer);
		aToken.approve(address(aw), _amtTransfer);
		uint _amountWrapped = aw.deposit(address(this), _amtTransfer);
		aw.approve(_capitalHandlerAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		ch.approve(address(amm), _amtTransfer);
		yt.approve(address(amm), _amountWrapped);
		amm.TakeQuote(_amtATkn, int128(_amountYT), false);
		yt.transfer(msg.sender, yt.balanceOf(address(this)));
	}

	function LiquidateAllToUnderlying(address _capitalHandlerAddress, uint _minUout, bool _unwrap) external override {
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());

		yt.transferFrom(msg.sender, address(this), yt.balanceOf(msg.sender));
		ch.transferFrom(msg.sender, address(this), ch.balanceOf(msg.sender));

		int _bondBal = ch.balanceBonds(address(this));

		if (_bondBal < -int(MinBalance)) {
			require(_bondBal >= -int(MAX));
			uint totalBalance = ch.balanceOf(address(this));
			//yAmm swap
			IYTamm yAmm = IYTamm(org.YTamms(_capitalHandlerAddress));
			yt.approve_2(address(yAmm), uint(-_bondBal), true);
			if (_minUout + RoundingBuffer > totalBalance) {
				yAmm.SwapFromSpecificYTWithLimit(int128(-_bondBal), _minUout-totalBalance+RoundingBuffer);
			}
			else {
				yAmm.SwapFromSpecificYT(int128(-_bondBal));
			}

		}
		else if (_bondBal > int(MinBalance)) {
			require(_bondBal <= int(MAX));
			uint totalBalance = yt.balanceOf_2(address(this), false);
			//zAmm swap
			IZCBamm zAmm = IZCBamm(org.ZCBamms(_capitalHandlerAddress));
			ch.approve(address(zAmm), uint(_bondBal));
			if (_minUout + RoundingBuffer > totalBalance) {
				zAmm.SwapFromSpecificTokensWithLimit(int128(_bondBal), true, _minUout-totalBalance+RoundingBuffer);
			}
			else {
				zAmm.SwapFromSpecificTokens(int128(_bondBal), true);				
			}
		}

		ch.withdrawAll(msg.sender, _unwrap);
	}

	function LiquidateSpecificToUnderlying(
			address _capitalHandlerAddress,
			uint _amountZCB,
			uint _amountYT,
			uint _minUout,
			bool _unwrap
		) external override {
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());

		yt.transferFrom_2(msg.sender, address(this), _amountYT, false);
		ch.transferFrom(msg.sender, address(this), _amountZCB);

		int _bondBal = ch.balanceBonds(address(this));

		if (_bondBal < -int(MinBalance)) {
			require(_bondBal >= -int(MAX));
			uint totalBalance = ch.balanceOf(address(this));
			//yAmm swap
			IYTamm yAmm = IYTamm(org.YTamms(_capitalHandlerAddress));
			yt.approve_2(address(yAmm), uint(-_bondBal), true);
			if (_minUout + RoundingBuffer > totalBalance) {
				yAmm.SwapFromSpecificYTWithLimit(int128(-_bondBal), _minUout-totalBalance+RoundingBuffer);
			}
			else {
				yAmm.SwapFromSpecificYT(int128(-_bondBal));
			}

		}
		else if (_bondBal > int(MinBalance)) {
			require(_bondBal <= int(MAX));
			uint totalBalance = yt.balanceOf_2(address(this), false);
			//zAmm swap
			IZCBamm zAmm = IZCBamm(org.ZCBamms(_capitalHandlerAddress));
			ch.approve(address(zAmm), uint(_bondBal));
			if (_minUout + RoundingBuffer > totalBalance) {
				zAmm.SwapFromSpecificTokensWithLimit(int128(_bondBal), true, _minUout-totalBalance+RoundingBuffer);
			}
			else {
				zAmm.SwapFromSpecificTokens(int128(_bondBal), true);
			}
		}

		ch.withdrawAll(msg.sender, _unwrap);
	}

	function SwapZCBtoYT(address _capitalHandlerAddress, uint _amountYT, uint _maxZCBin) external override {
		require(_amountYT < uint(MAX));
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		organizer _org = org;
		IZCBamm zAmm = IZCBamm(_org.ZCBamms(_capitalHandlerAddress));
		IYTamm yAmm = IYTamm(_org.YTamms(_capitalHandlerAddress));

		uint _amtU = yAmm.ReserveQuoteToYT(int128(_amountYT+RoundingBuffer));
		uint _amtZCB = zAmm.ReserveQuoteToSpecificTokens(int128(_amtU+RoundingBuffer), true);
		require(_amtZCB <= _maxZCBin);
		ch.transferFrom(msg.sender, address(this), _amtZCB);
		ch.approve(address(zAmm), _amtZCB);
		zAmm.TakeQuote(_amtZCB, _amtU+RoundingBuffer, true);
		//approvals for before yAmm swap
		ch.approve(address(yAmm), _amtU);
		yt.approve_2(address(yAmm), _amtU, true);
		yAmm.TakeQuote(_amtU, int128(_amountYT+RoundingBuffer), false);
		yt.transfer(msg.sender, yt.balanceOf(address(this)));
	}

	function SwapYTtoZCB(address _capitalHandlerAddress, uint _amountYT, uint _minZCBout) external override {
		require(_amountYT < uint(MAX) && _amountYT > RoundingBuffer);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		organizer _org = org;
		IZCBamm zAmm = IZCBamm(_org.ZCBamms(_capitalHandlerAddress));
		IYTamm yAmm = IYTamm(_org.YTamms(_capitalHandlerAddress));

		yt.transferFrom_2(msg.sender, address(this), _amountYT, false);
		yt.approve_2(address(yAmm), _amountYT, false);

		uint _amtU = yAmm.SwapFromSpecificYTWithLimit(int128(_amountYT-RoundingBuffer), RoundingBuffer);
		require(_amtU < uint(MAX));

		ch.approve(address(zAmm), _amtU);
		yt.approve_2(address(zAmm), _amtU+RoundingBuffer, false);
		uint _amtZCB = zAmm.SwapFromSpecificTokensWithLimit(int128(_amtU), false, _minZCBout);

		ch.transfer(msg.sender, _amtZCB);
	}


}
