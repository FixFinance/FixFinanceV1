pragma solidity >=0.6.0;
import "../helpers/IZCBamm.sol";
import "../helpers/IYTamm.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../interfaces/IYieldToken.sol";
import "../organizer.sol";

contract SwapRouterDelegate {
	//data
	organizer org;

	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

	uint private constant MinBalance = 0x1000;

	uint private constant RoundingBuffer = 0x10;

	/*
		@Description: turn underlying asset into ZCB
	
		@param address _fixCapitalPoolAddress: address of the ZCB to which to swap into
		@param uint _amount: the amount of the underlying asset to swap
		@param uint _minZCBout
	*/
	function UnitToZCB(address _fixCapitalPoolAddress, uint _amount, uint _minZCBout) external {
		require(_amount > MinBalance && _amount < uint(MAX));
		IFixCapitalPool ch = IFixCapitalPool(_fixCapitalPoolAddress);
		organizer _org = org;
		IERC20 underlyingAsset = IERC20(IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress());
		IWrapper wrapper = IFixCapitalPool(_fixCapitalPoolAddress).wrapper();
		IZCBamm amm = IZCBamm(_org.ZCBamms(_fixCapitalPoolAddress));
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZeroCouponBond zcb = IZeroCouponBond(ch.zeroCouponBondAddress());

		wrapper.forceHarvest();
		uint amtZCBout = amm.ReserveQuoteFromSpecificTokens(int128(_amount), false);
		uint _amountWrapped;
		require(amtZCBout >= _minZCBout);
		if (wrapper.underlyingIsWrapped()) {
			_amountWrapped = wrapper.UnitAmtToWrappedAmt_RoundUp(_amount);
			underlyingAsset.transferFrom(msg.sender, address(this), _amountWrapped);
			underlyingAsset.approve(address(wrapper), _amountWrapped);
			wrapper.depositWrappedAmount(address(this), _amountWrapped);
		}
		else {
			//when underlying is not wrapped there may be some rounding error, this
			//may result in us having too little funds to take the quote we reserved
			uint toDeposit = _amount + RoundingBuffer;
			underlyingAsset.transferFrom(msg.sender, address(this), toDeposit);
			underlyingAsset.approve(address(wrapper), toDeposit);
			_amountWrapped = wrapper.depositUnitAmount(address(this), toDeposit);
		}
		wrapper.approve(_fixCapitalPoolAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		zcb.approve(address(amm), _amount);
		yt.approve(address(amm), _amountWrapped);
		amm.TakeQuote(_amount, amtZCBout, false, false);
		
		zcb.transfer(msg.sender, zcb.balanceOf(address(this)));
	}

	/*
		@Description: turn underlying asset into YT

		@param address _fixCapitalPoolAddress: address of the fix capital pool which manages the yield token
			which we will transform our underlying asset into
		@param int128 _amountYT: amount of YT which we will swap to
		@param uint _maxUnitAmount: maximum amount of the underlying asset to use
	*/
	function UnitToYT(address _fixCapitalPoolAddress, int128 _amountYT, uint _maxUnitAmount) external {
		_amountYT++;	//account for rounding error when transfering funds out of YTamm
		require(_amountYT > int128(MinBalance));
		IFixCapitalPool ch = IFixCapitalPool(_fixCapitalPoolAddress);
		organizer _org = org;
		IERC20 underlyingAsset = IERC20(IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress());
		IWrapper wrapper = IFixCapitalPool(_fixCapitalPoolAddress).wrapper();
		IYTamm amm = IYTamm(_org.YTamms(_fixCapitalPoolAddress));
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZeroCouponBond zcb = IZeroCouponBond(ch.zeroCouponBondAddress());

		wrapper.forceHarvest();
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
		wrapper.approve(_fixCapitalPoolAddress, _amountWrapped);
		ch.depositWrappedToken(address(this), _amountWrapped);
		zcb.approve(address(amm), _amtTransfer);
		yt.approve(address(amm), _amountWrapped);
		amm.TakeQuote(_amtATkn, int128(_amountYT), false);
		yt.transfer(msg.sender, yt.balanceOf(address(this)));
	}

	/*
		@Description: close ZCB and YT positions and return to underlying asset

		@param address _fixCapitalPoolAddress: the fix capital pool that manages the ZCB and YT positions that will be exited
		@param uint _minUOut: the minimum amount of the underlying asset that will be accepted
		@param bool _unwrap: if true the underlying asset will be unwrapped
			otherwise after positions are exited the wrapped asset will be returned back to the caller of this function
	*/
	function LiquidateAllToUnderlying(address _fixCapitalPoolAddress, uint _minUout, bool _unwrap) external {
		IFixCapitalPool ch = IFixCapitalPool(_fixCapitalPoolAddress);
		IYieldToken yt = IYieldToken(ch.yieldTokenAddress());
		IZeroCouponBond zcb = IZeroCouponBond(ch.zeroCouponBondAddress());

		yt.transferFrom(msg.sender, address(this), yt.balanceOf(msg.sender));
		zcb.transferFrom(msg.sender, address(this), zcb.balanceOf(msg.sender));

		int _bondBal = ch.balanceBonds(address(this));

		if (_bondBal < -int(MinBalance)) {
			require(_bondBal >= -int(MAX));
			uint totalBalance = zcb.balanceOf(address(this));
			//yAmm swap
			IYTamm yAmm = IYTamm(org.YTamms(_fixCapitalPoolAddress));
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
			IZCBamm zAmm = IZCBamm(org.ZCBamms(_fixCapitalPoolAddress));
			zcb.approve(address(zAmm), uint(_bondBal));
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