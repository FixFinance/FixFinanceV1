pragma solidity >=0.6.0;
import "../helpers/IZCBamm.sol";
import "../helpers/IYTamm.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IERC20.sol";
import "../organizer.sol";
import "./SwapRouterDelegate.sol";

contract SwapRouter is ISwapRouter {
	//data
	organizer org;
	address delegateAddress;

	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

	uint private constant MinBalance = 0x1000;

	uint private constant RoundingBuffer = 0x10;

	constructor(address _organizerAddress, address _delegateAddress) public {
		org = organizer(_organizerAddress);
		delegateAddress = _delegateAddress;
	}

	function UnitToZCB(address _capitalHandlerAddress, uint _amount, uint _minZCBout) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"UnitToZCB(address,uint256,uint256)",
			_capitalHandlerAddress,
			_amount,
			_minZCBout
		));
		require(success);
	}

	function UnitToYT(address _capitalHandlerAddress, int128 _amountYT, uint _maxUnitAmount) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"UnitToYT(address,int128,uint256)",
			_capitalHandlerAddress,
			_amountYT,
			_maxUnitAmount
		));
		require(success);
	}

	function LiquidateAllToUnderlying(address _capitalHandlerAddress, uint _minUout, bool _unwrap) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"LiquidateAllToUnderlying(address,uint256,bool)",
			_capitalHandlerAddress,
			_minUout,
			_unwrap
		));
		require(success);
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
		zAmm.TakeQuote(_amtZCB, _amtU+RoundingBuffer, true, true);
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

	function _SwapZCBtoYT_ZCBamm(address _capitalHandlerAddress, uint _amountYT, uint _maxZCBin, bool _transferIn, bool _transferOut) internal returns (uint ZCBin) {
		require(_amountYT < uint(MAX) && _amountYT > RoundingBuffer);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZCBamm zAmm = IZCBamm(org.ZCBamms(_capitalHandlerAddress));

		uint quotedAmtIn = zAmm.ReserveQuoteToSpecificTokens(int128(_amountYT), true);
		ZCBin = quotedAmtIn > _amountYT ? quotedAmtIn - _amountYT : 0;
		require(ZCBin <= _maxZCBin);

		if (_transferIn) {
			ch.transferFrom(msg.sender, address(this), ZCBin);
		}
		ch.approve(address(zAmm), _maxZCBin);
		zAmm.TakeQuote(quotedAmtIn, _amountYT, true, true);
		if (_transferOut) {
			yt.transfer(msg.sender, yt.balanceOf(address(this)));
			ch.transfer(msg.sender, ch.balanceOf(address(this)));
		}
	}

	function _SwapYTtoZCB_ZCBamm(address _capitalHandlerAddress, uint _amountYT, uint _minZCBout, bool _transferIn, bool _transferOut) internal returns (uint ZCBout) {
		require(_amountYT < uint(MAX) && _amountYT > RoundingBuffer);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZCBamm zAmm = IZCBamm(org.ZCBamms(_capitalHandlerAddress));

		uint quotedAmtOut = zAmm.ReserveQuoteFromSpecificTokens(int128(_amountYT), false);
		require(quotedAmtOut >= _amountYT);
		ZCBout = quotedAmtOut - _amountYT;
		require(ZCBout >= _minZCBout);

		if (_transferIn) {
			yt.transferFrom_2(msg.sender, address(this), _amountYT, true);
		}
		yt.approve_2(address(zAmm), _amountYT, true);
		zAmm.TakeQuote(_amountYT, quotedAmtOut, false, false);
		if (_transferOut) {
			yt.transfer(msg.sender, yt.balanceOf(address(this)));
			ch.transfer(msg.sender, ch.balanceOf(address(this)));
		}
	}

	function SwapZCBtoYT_ZCBamm(address _capitalHandlerAddress, uint _amountYT, uint _maxZCBin) external override {
		_SwapZCBtoYT_ZCBamm(_capitalHandlerAddress, _amountYT, _maxZCBin, true, true);
	}

	function SwapYTtoZCB_ZCBamm(address _capitalHandlerAddress, uint _amountYT, uint _minZCBout) external override {
		_SwapYTtoZCB_ZCBamm(_capitalHandlerAddress, _amountYT, _minZCBout, true, true);
	}

	function SwapUtoYT_ZCBamm(address _capitalHandlerAddress, uint _amountYT, int128 _Uin) external override {
		require(_amountYT <= uint(MAX) && _amountYT > RoundingBuffer);
		require(_Uin > 0);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZCBamm zAmm = IZCBamm(org.ZCBamms(_capitalHandlerAddress));

		uint ZCBinMiddle = zAmm.ReserveQuoteFromSpecificTokens(_Uin, false);

		yt.transferFrom_2(msg.sender, address(this), uint(_Uin), true);
		ch.transferFrom(msg.sender, address(this), uint(_Uin));
		yt.approve_2(address(zAmm), uint(_Uin), true);
		zAmm.TakeQuote(uint(_Uin), ZCBinMiddle, false, false);

		_SwapZCBtoYT_ZCBamm(_capitalHandlerAddress, _amountYT, ZCBinMiddle, false, true);
	}

	function SwapYTtoU_ZCBamm(address _capitalHandlerAddress, uint _amountYT, uint _minUout) external override {
		uint ZCBout = _SwapYTtoZCB_ZCBamm(_capitalHandlerAddress, _amountYT, _minUout, true, false);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZCBamm zAmm = IZCBamm(org.ZCBamms(_capitalHandlerAddress));
		require(ZCBout <= uint(MAX));

		//now we will use ZCBout as the input to the next trade
		uint Uout = zAmm.ReserveQuoteFromSpecificTokens(int128(ZCBout), true);
		require(Uout >= _minUout);
		ch.approve(address(zAmm), ZCBout);
		zAmm.TakeQuote(ZCBout, Uout, true, false);

		yt.transfer(msg.sender, yt.balanceOf(address(this)));
		ch.transfer(msg.sender, ch.balanceOf(address(this)));
	}

}
