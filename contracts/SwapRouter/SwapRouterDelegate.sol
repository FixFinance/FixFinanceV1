pragma solidity >=0.6.0;
import "../helpers/IZCBamm.sol";
import "../helpers/IYTamm.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldToken.sol";
import "../organizer.sol";

contract SwapRouterDelegate {
	//data
	organizer org;

	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

	uint private constant MinBalance = 0x1000;

	uint private constant RoundingBuffer = 0x10;

	function UnitToZCB(address _capitalHandlerAddress, uint _amount, uint _minZCBout) external {
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		organizer _org = org;
		IERC20 underlyingAsset = IERC20(ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress());
		IWrapper wrapper = ICapitalHandler(_capitalHandlerAddress).wrapper();
		IZCBamm amm = IZCBamm(_org.ZCBamms(_capitalHandlerAddress));
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());

		uint _amountWrapped;
		if (wrapper.underlyingIsWrapped()) {
			_amountWrapped = wrapper.UnitAmtToWrappedAmt_RoundUp(_amount);
			underlyingAsset.transferFrom(msg.sender, address(this), _amountWrapped);
			underlyingAsset.approve(address(wrapper), _amountWrapped);
			wrapper.depositWrappedAmount(address(this), _amountWrapped);
		}
		else {
			underlyingAsset.transferFrom(msg.sender, address(this), _amount);
			underlyingAsset.approve(address(wrapper), _amount);
			_amountWrapped = wrapper.depositUnitAmount(address(this), _amount);
		}
		wrapper.approve(_capitalHandlerAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		ch.approve(address(amm), _amount);
		yt.approve(address(amm), _amountWrapped);
		uint _amountToSwap = wrapper.WrappedAmtToUnitAmt_RoundUp(_amountWrapped);
		require(_amountToSwap <= uint(MAX));
		uint _out = amm.SwapFromSpecificTokensWithLimit(int128(_amountToSwap), false, _minZCBout);
		ch.transfer(msg.sender, _out);
	}

	function UnitToYT(address _capitalHandlerAddress, int128 _amountYT, uint _maxUnitAmount) external {
		_amountYT++;	//account for rounding error when transfering funds out of YTamm
		require(_amountYT > 0);
		ICapitalHandler ch = ICapitalHandler(_capitalHandlerAddress);
		organizer _org = org;
		IERC20 underlyingAsset = IERC20(ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress());
		IWrapper wrapper = ICapitalHandler(_capitalHandlerAddress).wrapper();
		IYTamm amm = IYTamm(_org.YTamms(_capitalHandlerAddress));
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());

		uint _amtATkn = amm.ReserveQuoteToYT(_amountYT);
		//remove possibility for problems due to rounding error
		uint _amtTransfer = _amtATkn + RoundingBuffer;
		require(_amtTransfer <= _maxUnitAmount, "Required AToken in is Greater than _maxUnitAmount");
		uint _amountWrapped;
		if (wrapper.underlyingIsWrapped()) {
			_amountWrapped = wrapper.UnitAmtToWrappedAmt_RoundUp(_amtTransfer);
			underlyingAsset.transferFrom(msg.sender, address(this), _amountWrapped);
			underlyingAsset.approve(address(wrapper), _amountWrapped);
			wrapper.depositWrappedAmount(address(this), _amountWrapped);
		}
		else {
			underlyingAsset.transferFrom(msg.sender, address(this), _amtTransfer);
			underlyingAsset.approve(address(wrapper), _amtTransfer);
			_amountWrapped = wrapper.depositUnitAmount(address(this), _amtTransfer);
		}
		wrapper.approve(_capitalHandlerAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		ch.approve(address(amm), _amtTransfer);
		yt.approve(address(amm), _amountWrapped);
		amm.TakeQuote(_amtATkn, int128(_amountYT), false);
		yt.transfer(msg.sender, yt.balanceOf(address(this)));
	}

	function LiquidateAllToUnderlying(address _capitalHandlerAddress, uint _minUout, bool _unwrap) external {
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
}