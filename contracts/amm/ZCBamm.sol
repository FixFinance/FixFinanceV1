pragma solidity >=0.6.0;

import "../helpers/IZCBamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IERC20.sol";

contract ZCBamm is IZCBamm {

	using ABDKMath64x64 for int128;

	uint64 public override maturity;
	uint public override anchor;

	uint ZCBreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	int128[3] impliedRates;
	uint[3] heights;

	constructor(address _ZCBaddress) public {
		name = "aZCB amm Liquidity Token";
		symbol = "aZCBLT";
		address _YTaddress = ICapitalHandler(_ZCBaddress).yieldTokenAddress();
		uint64 _maturity = ICapitalHandler(_ZCBaddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		maturity = _maturity;
		//we want time remaining / anchor to be less than 1, thus make anchor greater than time remaining
		anchor = 10 * (maturity - block.timestamp) / 9;
		init(_ZCBaddress, _YTaddress);
	}

	function _mint(address _to, uint _amount) internal {
        claimDividendInternal(_to, _to);
		balanceOf[_to] += _amount;
		totalSupply += _amount;

		emit Mint(_to, _amount);
	}

	function _burn(address _from, uint _amount) internal {
		require(balanceOf[_from] >= _amount);
        claimDividendInternal(_from, _from);
		balanceOf[_from] -= _amount;
		totalSupply -= _amount;

		emit Burn(_from, _amount);
	}

	function getU(uint _amount) internal {
		getZCB(_amount);
		getYT(_amount);
	}

	function getZCB(uint _amount) internal {
		ICapitalHandler(ZCBaddress).transferFrom(msg.sender, address(this), _amount);
	}

	function getYT(uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, address(this), _amount, true);
	}

	function sendU(uint _amount) internal {
		sendZCB(_amount);
		sendYT(_amount);
	}

	function sendZCB(uint _amount) internal {
		ICapitalHandler(ZCBaddress).transfer(msg.sender, _amount);
	}

	function sendYT(uint _amount) internal {
		IYieldToken(YTaddress).transfer_2(msg.sender, _amount, false);
	}

	function timeRemaining() internal view returns (uint) {
		return uint(int128((maturity-block.timestamp)<<64).div(int128(anchor<<64)));
	}

	/*
		@Description first deposit in pool
	*/
	function firstMint(uint128 _Uin, uint128 _ZCBin) external override {
		require(totalSupply == 0);

		uint r = timeRemaining();
		uint _Uout = uint(- BigMath.ZCB_U_reserve_change(_Uin, _Uin, r, int128(_ZCBin) ) );

		require(_Uout < _Uin);
		uint effectiveU = _Uin - _Uout;

		getZCB(effectiveU + _ZCBin);
		getYT(effectiveU);

		_mint(msg.sender, _Uin);

		ZCBreserves = _ZCBin;
		Ureserves = effectiveU;
	}

	function mint(uint _amount, uint _maxUin, uint _maxZCBin) external override setRateModifier {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uin = _amount*Ureserves;
		Uin = Uin/_totalSupply + (Uin%_totalSupply == 0 ? 0 : 1);
		require(Uin <= _maxUin);

		uint ZCBin = _amount*ZCBreserves;
		ZCBin = ZCBin/_totalSupply + (ZCBin%_totalSupply == 0 ? 0 : 1);
		require(ZCBin <= _maxZCBin);

		getZCB(ZCBin + Uin);
		getYT(Uin);

		_mint(msg.sender, _amount);

		Ureserves += Uin;
		ZCBreserves += ZCBin;
	}

	function burn(uint _amount) external override setRateModifier {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uout = _amount*Ureserves/_totalSupply;
		uint ZCBout = _amount*ZCBreserves/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(Uout + ZCBout);
		sendYT(Uout);

		Ureserves -= Uout;
		ZCBreserves -= ZCBout;
	}

	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) external override setRateModifier returns (uint) {
		require(_amount > 0);
		int _amtOut;
		uint r = timeRemaining();

		if (_ZCBin) {
			_amtOut = -int(BigMath.ZCB_U_reserve_change(ZCBreserves+totalSupply, Ureserves, r, _amount));

			require(_amtOut > 0);

			require(Ureserves > uint(_amtOut));

			getZCB(uint(_amount));
			sendU(uint(_amtOut));

			ZCBreserves += uint(_amount);
			Ureserves -= uint(_amtOut);

			emit Swap(msg.sender, uint(_amount), uint(_amtOut), true);

		} else {
			_amtOut = -int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, _amount));

			require(_amtOut > 0);
			require(_amount < _amtOut, "cannot swap to ZCB at negative rate");

			require(ZCBreserves > uint(_amtOut));

			getU(uint(_amount));
			sendZCB(uint(_amtOut));

			Ureserves += uint(_amount);
			ZCBreserves -= uint(_amtOut);

			emit Swap(msg.sender, uint(_amtOut), uint(_amount), false);
		}

		return uint(_amtOut);
	}

	function SwapToSpecificTokens(int128 _amount, bool _ZCBout) external override setRateModifier returns (uint) {
		require(_amount > 0);
		int _amtIn;
		uint r = timeRemaining();

		if (_ZCBout) {
			require(ZCBreserves >= uint(_amount));
			_amtIn = int(BigMath.ZCB_U_reserve_change(ZCBreserves+totalSupply, Ureserves, r, -_amount));

			require(_amtIn > 0);
			require(_amount > _amtIn, "cannot swap to ZCB at negative rate");

			getU(uint(_amtIn));
			sendZCB(uint(_amount));

			Ureserves += uint(_amtIn);
			ZCBreserves -= uint(_amount);

			emit Swap(msg.sender, uint(_amount), uint(_amtIn), false);

		} else {
			require(Ureserves >= uint(_amount));
			_amtIn = int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, -_amount));

			require(_amtIn > 0);

			getZCB(uint(_amtIn));
			sendU(uint(_amount));

			ZCBreserves += uint(_amtIn);
			Ureserves -= uint(_amount);

			emit Swap(msg.sender, uint(_amtIn), uint(_amount), true);
		}

		return uint(_amtIn);
	}

	function forceRateDataUpdate() external override setRateModifier {}

	//-------------------------implement double asset yield enabled token-------------------------------
	function contractClaimDividend() external override {
		require(lastWithdraw < block.timestamp - 86400, "this function can only be called once every 24 hours");

		uint _ZCBreserves = ZCBreserves;	//gas savings
		uint _Ureserves = Ureserves;	//gas savings

		uint amount = ICapitalHandler(ZCBaddress).balanceOf(address(this));
		require(amount > _ZCBreserves + _Ureserves);
		amount = amount - _ZCBreserves - _Ureserves + ZCBdividendOut;
		require(amount > contractBalanceAsset1[contractBalanceAsset1.length-1]);
		contractBalanceAsset1.push(amount);

		amount = IYieldToken(YTaddress).balanceOf_2(address(this), false);
		require(amount > _Ureserves);
		amount = amount - _Ureserves + YTdividendOut;
		require(amount > contractBalanceAsset2[contractBalanceAsset2.length-1]);
		contractBalanceAsset2.push(amount);

		lastWithdraw = block.timestamp;
	}

	//------------------------e-n-a-b-l-e---p-o-o-l---t-o---a-c-t---a-s---r-a-t-e---o-r-a-c-l-e-----------------
	function indexToSet() internal view returns (uint8) {
		uint8 i = 2;
		for (;i > 0 && heights[i] >= heights[i-1]; i--) {}
		return i;
	}

	function setOracleRate(uint8 _index) internal {
		/*
			APY**(anchor/1 year) == ZCBreserves/Ureserves
			APY == (ZCBreserves/Ureserves)**(1 year/anchor)

			the main function of our rate oracle is to feed info to the YTamm which knows the anchor so we are good with storing ZCBreserves/Ureserves here
		*/
		uint _Ureserves = Ureserves;
		uint _ZCBreserves = totalSupply + ZCBreserves;
		//only record when rate is a positive real number, also _ZCB reserves must fit into 192 bits
		if (Ureserves == 0 || _ZCBreserves >> 192 != 0  || _ZCBreserves <= _Ureserves) return;
		uint rate = (_ZCBreserves << 64) / _Ureserves;
		//rate must fit into 127 bits
		if (rate >= 1 << 128) return;
		heights[_index] = block.number;
		impliedRates[_index] = int128(rate);
	}

	modifier setRateModifier() {
		uint8 toSet = indexToSet();
		uint8 mostRecent = (2+toSet)%3;
		if (block.number != heights[mostRecent]) setOracleRate(toSet);
		_;
	}

	//returns APY**(anchor/1 year)
	function getRateFromOracle() public view override returns (int128 rate) {
		require(heights[2] != 0);	//rate data must be non-null

		int128 first = impliedRates[0];
		int128 second = impliedRates[1];
		int128 third = impliedRates[2];

        (first,second) = first > second ? (first, second) : (second,first);
        (second,third) = second > third ? (second, third) : (third,second);
        (first,second) = first > second ? (first, second) : (second,first);

        return second;
	}

	function getAPYFromOracle() external view override returns (int128 APY) {
		/*
			APY == getRateFromOr111acle()**(1 year / anchor)
			APY == exp2 ( log 2 ( getRateFromOracle()**(1 year / anchor)))
			APY == exp2 ( (1 year / anchor) * log 2 ( getRateFromOracle()))
		*/
		APY = getRateFromOracle();
		// 31556926 is the number of seconds in a year
		int128 _1overAnchor = int128((31556926 << 64) / anchor);
		APY = APY.log_2().mul(_1overAnchor).exp_2();
	}

	function getImpliedRateData() external view override returns (
		int128 impliedRate0,
		int128 impliedRate1,
		int128 impliedRate2,
		uint height0,
		uint height1,
		uint height2
	) {
		impliedRate0 = impliedRates[0];
		impliedRate1 = impliedRates[1];
		impliedRate2 = impliedRates[2];
		height0 = heights[0];
		height1 = heights[1];
		height2 = heights[2];
	}


	//-----------------------o-t-h-e-r---v-i-e-w-s-----------------------------------------------

	function getReserves() external view returns (uint _Ureserves, uint _ZCBreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_ZCBreserves = ZCBreserves;
		_TimeRemaining = timeRemaining();
	}



}


