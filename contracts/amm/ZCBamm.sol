pragma solidity >=0.6.0;

import "../helpers/IZCBamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IERC20.sol";
import "../FeeOracle.sol";

contract ZCBamm is IZCBamm {

	using ABDKMath64x64 for int128;

	uint8 private constant LENGTH_RATE_SERIES = 31;
	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
	uint private constant SecondsPerYear = 31556926;

	uint64 public override maturity;
	uint public override anchor;

	uint ZCBreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	address FeeOracleAddress;

	bytes32 quoteSignature;
	uint256 quotedAmountIn;
	uint256 quotedAmountOut;

	uint8 toSet;
	bool CanSetOracleRate;
	int128 OracleRate;
	int128[LENGTH_RATE_SERIES] impliedRates;
	uint[LENGTH_RATE_SERIES] timestamps;


	constructor(address _ZCBaddress, address _feeOracleAddress) public {
		name = "aZCB amm Liquidity Token";
		symbol = "aZCBLT";
		address _YTaddress = ICapitalHandler(_ZCBaddress).yieldTokenAddress();
		uint64 _maturity = ICapitalHandler(_ZCBaddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		maturity = _maturity;
		//we want time remaining / anchor to be less than 1, thus make anchor greater than time remaining
		anchor = 10 * (maturity - block.timestamp) / 9;
		FeeOracleAddress = _feeOracleAddress;
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

	function getZCBsendU(uint _amountZCB, uint _amountU) internal {
		sendYT(_amountU);
		if (_amountZCB > _amountU) {
			getZCB(_amountZCB - _amountU);
		}
	}

	function sendZCBgetU(uint _amountZCB, uint _amountU) internal {
		require(_amountZCB > _amountU);
		sendZCB(_amountZCB - _amountU);
		getYT(_amountU);
	}

	function getZCB(uint _amount) internal {
		ICapitalHandler(ZCBaddress).transferFrom(msg.sender, address(this), _amount);
	}

	function getYT(uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, address(this), _amount, true);
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

	function getQuoteSignature(bool _ZCBin) internal view returns (bytes32) {
		return keccak256(abi.encodePacked(totalSupply, ZCBreserves, Ureserves, _ZCBin, block.number));
	}

	function writeQuoteSignature(bool _ZCBin, uint _amountIn, uint _amountOut) internal returns (bytes32) {
		quoteSignature = getQuoteSignature(_ZCBin);
		quotedAmountIn = _amountIn;
		quotedAmountOut = _amountOut;
	}

	modifier verifyQuote(uint _amountIn, uint _amountOut, bool _ZCBin) {
		require(quotedAmountIn == _amountIn);
		require(quotedAmountOut == _amountOut);
		require(getQuoteSignature(_ZCBin) == quoteSignature);
		_;
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

	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) public override setRateModifier returns (uint amountOut) {
		require(_amount > 0);
		uint r = timeRemaining();

		if (_ZCBin) {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(ZCBreserves+totalSupply, Ureserves, r, _amount));
				require(temp > 0);
				amountOut = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
			}

			require(Ureserves > amountOut);

			getZCBsendU(uint(_amount), amountOut);

			ZCBreserves += uint(_amount);
			Ureserves -= amountOut;

			emit Swap(msg.sender, uint(_amount), amountOut, true);

		} else {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, _amount));
				require(temp > 0);
				amountOut = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
			}

			require(uint(_amount) < amountOut, "cannot swap to ZCB at negative rate");

			require(ZCBreserves > amountOut);

			sendZCBgetU(amountOut, uint(_amount));

			Ureserves += uint(_amount);
			ZCBreserves -= amountOut;

			emit Swap(msg.sender, amountOut, uint(_amount), false);
		}
	}

	function SwapToSpecificTokens(int128 _amount, bool _ZCBin) public override setRateModifier returns (uint amountIn) {
		require(_amount > 0);
		uint r = timeRemaining();

		if (_ZCBin) {
			require(Ureserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, -_amount));
				require(temp > 0);
				amountIn = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
			}

			getZCBsendU(amountIn, uint(_amount));

			ZCBreserves += amountIn;
			Ureserves -= uint(_amount);

			emit Swap(msg.sender, amountIn, uint(_amount), true);
		} else {
			require(ZCBreserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(ZCBreserves+totalSupply, Ureserves, r, -_amount));
				require(temp > 0);
				amountIn = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
			}

			require(uint(_amount) > amountIn, "cannot swap to ZCB at negative rate");

			sendZCBgetU(uint(_amount), amountIn);

			Ureserves += amountIn;
			ZCBreserves -= uint(_amount);

			emit Swap(msg.sender, uint(_amount), amountIn, false);
		}
	}

	function SwapFromSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _minAmtOut) external override returns(uint _out) {
		_out = SwapFromSpecificTokens(_amount, _ZCBin);
		require(_out >= _minAmtOut);
	}

	function SwapToSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _maxAmtIn) external override returns(uint _in) {
		_in = SwapToSpecificTokens(_amount, _ZCBin);
		require(_in <= _maxAmtIn);
	}

	function ReserveQuoteFromSpecificTokens(int128 _amount, bool _ZCBin) external override setRateModifier returns(uint amountOut) {
		require(_amount > 0);
		uint r = timeRemaining();

		if (_ZCBin) {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(ZCBreserves+totalSupply, Ureserves, r, _amount));
				require(temp > 0);
				amountOut = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
			}

			require(Ureserves > amountOut);

		} else {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, _amount));
				require(temp > 0);
				amountOut = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
			}

			require(uint(_amount) < amountOut, "cannot swap to ZCB at negative rate");

			require(ZCBreserves > amountOut);
		}
		writeQuoteSignature(_ZCBin, uint(_amount), amountOut);
	}

	function ReserveQuoteToSpecificTokens(int128 _amount, bool _ZCBin) external override setRateModifier returns(uint amountIn) {
		require(_amount > 0);
		uint r = timeRemaining();

		if (_ZCBin) {
			require(Ureserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, -_amount));
				require(temp > 0);
				amountIn = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
			}

		} else {
			require(ZCBreserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(ZCBreserves+totalSupply, Ureserves, r, -_amount));
				require(temp > 0);
				amountIn = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
			}

			require(uint(_amount) > amountIn, "cannot swap to ZCB at negative rate");
		}
		writeQuoteSignature(_ZCBin, amountIn, uint(_amount));
	}

	function TakeQuote(uint _amountIn, uint _amountOut, bool _ZCBin) external override verifyQuote(_amountIn, _amountOut, _ZCBin) {
		if (_ZCBin) {
			require(Ureserves >= _amountOut);
			getZCBsendU(_amountIn, _amountOut);
			ZCBreserves += _amountIn;
			Ureserves -= _amountOut;
			emit Swap(msg.sender, _amountIn, _amountOut, _ZCBin);
		} else {
			require(ZCBreserves >= _amountOut);
			sendZCBgetU(_amountOut, _amountIn);
			Ureserves += _amountIn;
			ZCBreserves -= _amountOut;
			emit Swap(msg.sender, _amountOut, _amountIn, _ZCBin);
		}
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
		timestamps[_index] = block.timestamp;
		impliedRates[_index] = int128(rate);
		if (_index+1 == LENGTH_RATE_SERIES) {
			CanSetOracleRate = true;
		}
		else {
			toSet++;
		}
	}

	modifier setRateModifier() {
		if (!CanSetOracleRate) {
			uint8 _toSet = toSet;
			uint8 mostRecent = (LENGTH_RATE_SERIES-1+_toSet)%LENGTH_RATE_SERIES;
			if (block.timestamp >= timestamps[mostRecent] + (1 minutes)) setOracleRate(_toSet);
		}
		_;
	}

	//returns APY**(anchor/1 year)
	function getRateFromOracle() external view override returns (int128 rate) {
		rate = OracleRate;
	}

	function setOracleRate(int128 _rate) external {
		require(CanSetOracleRate);

		uint8 numLarger;
		uint8 numEqual;
		for (uint8 i = 0; i < LENGTH_RATE_SERIES; i++) {
			if (impliedRates[i] > _rate) {
				numLarger++;
			}
			else if (impliedRates[i] == _rate) {
				numEqual++;
			}
		}
		//uint8 numSmaller = LENGTH_RATE_SERIES - numEqual - numLarger;
		uint8 medianIndex = LENGTH_RATE_SERIES/2;
		require(numLarger + numEqual >= medianIndex);
		//require(numSmaller + numEqual >= medianIndex);
		require(LENGTH_RATE_SERIES - numLarger >= medianIndex);

		OracleRate = _rate;
		CanSetOracleRate = false;
		toSet = 0;
	}

	function getAPYFromOracle() external view override returns (int128 APY) {
		/*
			APY == getRateFromOracle()**(1 year / anchor)
			APY == exp2 ( log 2 ( getRateFromOracle()**(1 year / anchor)))
			APY == exp2 ( (1 year / anchor) * log 2 ( getRateFromOracle()))
		*/
		APY = OracleRate;
		int128 _1overAnchor = int128((SecondsPerYear << 64) / anchor);
		APY = APY.log_2().mul(_1overAnchor).exp_2();
	}

	function getImpliedRateData() external view override returns (
		int128[LENGTH_RATE_SERIES] memory _impliedRates,
		uint[LENGTH_RATE_SERIES] memory _timestamps
		) {
		_impliedRates = impliedRates;
		_timestamps = timestamps;
	}


	//-----------------------o-t-h-e-r---v-i-e-w-s-----------------------------------------------

	function getReserves() external view returns (uint _Ureserves, uint _ZCBreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_ZCBreserves = ZCBreserves;
		_TimeRemaining = timeRemaining();
	}



}


