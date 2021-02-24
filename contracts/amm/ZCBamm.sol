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
	using SafeMath for uint256;

	uint8 private constant LENGTH_RATE_SERIES = 31;
	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
	uint private constant SecondsPerYear = 31556926;

	uint64 public override maturity;
	uint public override anchor;
	uint public override nextAnchor;

	uint ZCBreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	address FeeOracleAddress;

	bytes32 quoteSignature;
	uint256 quotedAmountIn;
	uint256 quotedAmountOut;
	uint256 quotedTreasuryFee;

	uint lastRecalibration;
	uint LPTokenInflation;

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
		uint temp = 10 * (maturity - block.timestamp) / 9;
		anchor = temp;
		nextAnchor = temp;
		FeeOracleAddress = _feeOracleAddress;
		lastRecalibration = block.timestamp;
		LPTokenInflation = 1 ether;
		ZCBaddress = _ZCBaddress;
		YTaddress = _YTaddress;
	}

	function _mint(address _to, uint _amount) internal {
		balanceOf[_to] += _amount;
		totalSupply += _amount;

		emit Mint(_to, _amount);
	}

	function _burn(address _from, uint _amount) internal {
		require(balanceOf[_from] >= _amount);
		balanceOf[_from] -= _amount;
		totalSupply -= _amount;

		emit Burn(_from, _amount);
	}

	function getZCBsendU(uint _amountZCB, uint _amountU, uint _treasuryFee, address _treasuryAddress, bool _treasuryFeeInZCB) internal {
		sendYT(msg.sender, _amountU);
		if (_amountZCB > _amountU) {
			getZCB(address(this), _amountZCB - _amountU);
		}

		sendZCB(_treasuryAddress, _treasuryFee);
		if (!_treasuryFeeInZCB) {
			sendYT(_treasuryAddress, _treasuryFee);
		}
	}

	function sendZCBgetU(uint _amountZCB, uint _amountU, uint _treasuryFee, address _treasuryAddress, bool _treasuryFeeInZCB) internal {
		require(_amountZCB > _amountU);
		sendZCB(msg.sender, _amountZCB - _amountU);
		getYT(address(this), _amountU);

		sendZCB(_treasuryAddress, _treasuryFee);
		if (!_treasuryFeeInZCB) {
			sendYT(_treasuryAddress, _treasuryFee);
		}
	}

	function getZCB(address _to, uint _amount) internal {
		ICapitalHandler(ZCBaddress).transferFrom(msg.sender, _to, _amount);
	}

	function getYT(address _to, uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, _to, _amount, true);
	}

	function sendZCB(address _to, uint _amount) internal {
		ICapitalHandler(ZCBaddress).transfer(_to, _amount);
	}

	function sendYT(address _to, uint _amount) internal {
		IYieldToken(YTaddress).transfer_2(_to, _amount, false);
	}

	function timeRemaining() internal view returns (uint) {
		return uint(int128((maturity-block.timestamp)<<64).div(int128(nextAnchor<<64)));
	}

	function nextTimeRemaining() internal view returns (uint) {
		return uint(int128((maturity-block.timestamp)<<64).div(int128(nextAnchor<<64)));
	}

	function getQuoteSignature(uint8 _tradeType) internal view returns (bytes32) {
		return keccak256(abi.encodePacked(totalSupply, ZCBreserves, Ureserves, _tradeType, block.number));
	}

	function _inflatedTotalSupply() internal view returns (uint) {
		return totalSupply.mul(LPTokenInflation).div(1 ether);
	}

	function writeQuoteSignature(bool _ZCBin, bool _ToSpecific, uint _amountIn, uint _amountOut, uint _treasuryFee) internal returns (bytes32) {
		quoteSignature = getQuoteSignature(tradeType(_ZCBin, _ToSpecific));
		quotedAmountIn = _amountIn;
		quotedAmountOut = _amountOut;
		quotedTreasuryFee = _treasuryFee;
	}

	function tradeType(bool _ZCBin, bool _ToSpecific) internal pure returns (uint8) {
		return uint8((_ZCBin ? 2: 0) | (_ToSpecific ? 1 : 0));
	}

	modifier verifyQuote(uint _amountIn, uint _amountOut, bool _ZCBin, bool _ToSpecific) {
		require(quotedAmountIn == _amountIn);
		require(quotedAmountOut == _amountOut);
		require(getQuoteSignature(tradeType(_ZCBin, _ToSpecific)) == quoteSignature);
		_;
	}

	/*
		@Description first deposit in pool
	*/
	function firstMint(uint128 _Uin, uint128 _ZCBin) external override {
		require(totalSupply == 0);

		uint r = nextTimeRemaining();
		uint _Uout = uint(- BigMath.ZCB_U_reserve_change(_Uin, _Uin, r, int128(_ZCBin) ) );

		require(_Uout < _Uin);
		uint effectiveU = _Uin - _Uout;

		getZCB(address(this), effectiveU + _ZCBin);
		getYT(address(this), effectiveU);

		_mint(msg.sender, _Uin);

		ZCBreserves = _ZCBin;
		Ureserves = effectiveU;
	}

	function mint(uint _amount, uint _maxYTin, uint _maxZCBin) external override setRateModifier {
		uint _totalSupply = totalSupply;	//gas savings

		uint contractZCBbalance = IERC20(ZCBaddress).balanceOf(address(this));
		uint contractYTbalance = IYieldToken(YTaddress).balanceOf_2(address(this), false);

		uint ZCBin = _amount.mul(contractZCBbalance);
		ZCBin = ZCBin/_totalSupply + (ZCBin%_totalSupply == 0 ? 0 : 1);
		require(ZCBin <= _maxZCBin);

		uint YTin = _amount.mul(contractYTbalance);
		YTin = YTin/_totalSupply + (YTin%_totalSupply == 0 ? 0 : 1);
		require(YTin <= _maxYTin);

		getZCB(address(this), ZCBin);
		getYT(address(this), YTin);

		_mint(msg.sender, _amount);

		Ureserves = Ureserves.mul(_totalSupply+_amount) / _totalSupply;
		ZCBreserves = ZCBreserves.mul(_totalSupply+_amount) / _totalSupply;
	}

	function burn(uint _amount) external override setRateModifier {
		uint _totalSupply = totalSupply;	//gas savings

		uint contractZCBbalance = IERC20(ZCBaddress).balanceOf(address(this));
		uint contractYTbalance = IYieldToken(YTaddress).balanceOf_2(address(this), false);

		uint ZCBout = _amount.mul(contractZCBbalance)/_totalSupply;
		uint YTout = _amount.mul(contractYTbalance)/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(msg.sender, ZCBout);
		sendYT(msg.sender, YTout);

		Ureserves = Ureserves.mul(_totalSupply-_amount) / _totalSupply;
		ZCBreserves = ZCBreserves.mul(_totalSupply-_amount) / _totalSupply;
	}

	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) public override setRateModifier returns (uint amountOut) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		address sendTo;
		uint reserveDecrease;
		if (_ZCBin) {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(ZCBreserves+_inflatedTotalSupply(), Ureserves, r, _amount));
				require(temp > 0);
				(amountOut, treasuryFee, sendTo) = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
				reserveDecrease = amountOut.add(treasuryFee);
			}

			require(Ureserves >= reserveDecrease);

			getZCBsendU(uint(_amount), amountOut, treasuryFee, sendTo, false);

			ZCBreserves += uint(_amount);
			Ureserves -= reserveDecrease;

			emit Swap(msg.sender, uint(_amount), amountOut, true);

		} else {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+_inflatedTotalSupply(), r, _amount));
				require(temp > 0);
				(amountOut, treasuryFee, sendTo) = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
				reserveDecrease = amountOut.add(treasuryFee);
			}

			require(uint(_amount) < amountOut, "cannot swap to ZCB at negative rate");

			require(ZCBreserves >= reserveDecrease);

			sendZCBgetU(amountOut, uint(_amount), treasuryFee, sendTo, true);

			Ureserves += uint(_amount);
			ZCBreserves -= reserveDecrease;

			emit Swap(msg.sender, amountOut, uint(_amount), false);
		}
	}

	function SwapToSpecificTokens(int128 _amount, bool _ZCBin) public override setRateModifier returns (uint amountIn) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		address sendTo;
		uint reserveIncrease;
		if (_ZCBin) {
			require(Ureserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+_inflatedTotalSupply(), r, -_amount));
				require(temp > 0);
				(amountIn, treasuryFee, sendTo) = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
				reserveIncrease = amountIn.sub(treasuryFee);
			}
			getZCBsendU(amountIn, uint(_amount), treasuryFee, sendTo, true);

			ZCBreserves += reserveIncrease;
			Ureserves -= uint(_amount);

			emit Swap(msg.sender, amountIn, uint(_amount), true);
		} else {
			require(ZCBreserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(ZCBreserves+_inflatedTotalSupply(), Ureserves, r, -_amount));
				require(temp > 0);
				(amountIn, treasuryFee, sendTo) = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
				reserveIncrease = amountIn.sub(treasuryFee);
			}

			require(uint(_amount) > amountIn, "cannot swap to ZCB at negative rate");

			sendZCBgetU(uint(_amount), amountIn, treasuryFee, sendTo, false);

			Ureserves += reserveIncrease;
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
		uint r = nextTimeRemaining();

		uint treasuryFee;
		if (_ZCBin) {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(ZCBreserves+_inflatedTotalSupply(), Ureserves, r, _amount));
				require(temp > 0);
				(amountOut, treasuryFee, ) = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
			}

			require(Ureserves > amountOut);

		} else {
			{
				int temp = -int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+_inflatedTotalSupply(), r, _amount));
				require(temp > 0);
				(amountOut, treasuryFee, ) = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, uint(temp));
			}

			require(uint(_amount) < amountOut, "cannot swap to ZCB at negative rate");
			
			uint reserveDecrease = amountOut.add(treasuryFee);

			require(ZCBreserves >= reserveDecrease);
		}
		writeQuoteSignature(_ZCBin, false, uint(_amount), amountOut, treasuryFee);
	}

	function ReserveQuoteToSpecificTokens(int128 _amount, bool _ZCBin) external override setRateModifier returns(uint amountIn) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		if (_ZCBin) {
			require(Ureserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+_inflatedTotalSupply(), r, -_amount));
				require(temp > 0);
				(amountIn, treasuryFee, ) = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
			}

		} else {
			require(ZCBreserves >= uint(_amount));
			{
				int temp = int(BigMath.ZCB_U_reserve_change(ZCBreserves+_inflatedTotalSupply(), Ureserves, r, -_amount));
				require(temp > 0);
				(amountIn, treasuryFee, ) = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, uint(temp));
			}

			require(uint(_amount) > amountIn, "cannot swap to ZCB at negative rate");
		}
		writeQuoteSignature(_ZCBin, true, amountIn, uint(_amount), treasuryFee);
	}

	function TakeQuote(uint _amountIn, uint _amountOut, bool _ZCBin, bool _ToSpecific) external override verifyQuote(_amountIn, _amountOut, _ZCBin, _ToSpecific) {
		address sendTo = FeeOracle(FeeOracleAddress).sendTo();
		uint _quotedTreasuryFee = quotedTreasuryFee;
		uint reserveDecrease = _amountOut.add(!_ToSpecific ? _quotedTreasuryFee : 0);
		if (_ZCBin) {
			require(Ureserves >= reserveDecrease);
			getZCBsendU(_amountIn, _amountOut, _quotedTreasuryFee, sendTo, _ToSpecific);
			ZCBreserves += _amountIn.sub(_ToSpecific ? _quotedTreasuryFee : 0);
			Ureserves -= reserveDecrease;
			emit Swap(msg.sender, _amountIn, _amountOut, _ZCBin);
		} else {
			require(ZCBreserves >= reserveDecrease);
			sendZCBgetU(_amountOut, _amountIn, _quotedTreasuryFee, sendTo, !_ToSpecific);
			Ureserves += _amountIn.sub(_ToSpecific ? _quotedTreasuryFee : 0);
			ZCBreserves -= reserveDecrease;
			emit Swap(msg.sender, _amountOut, _amountIn, _ZCBin);
		}
	}

	//------------------------e-n-a-b-l-e---p-o-o-l---t-o---a-c-t---a-s---r-a-t-e---o-r-a-c-l-e-----------------

	function forceRateDataUpdate() external override setRateModifier {}

	function internalSetOracleRate(uint8 _index) internal {
		/*
			APY**(anchor/1 year) == ZCBreserves/Ureserves
			APY == (ZCBreserves/Ureserves)**(1 year/anchor)

			the main function of our rate oracle is to feed info to the YTamm which knows the anchor so we are good with storing ZCBreserves/Ureserves here
		*/
		uint _Ureserves = Ureserves;
		uint _ZCBreserves = _inflatedTotalSupply() + ZCBreserves;
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
		toSet++;
	}

	modifier setRateModifier() {
		if (!CanSetOracleRate) {
			uint8 _toSet = toSet;
			uint8 mostRecent = (LENGTH_RATE_SERIES-1+_toSet)%LENGTH_RATE_SERIES;
			if (block.timestamp >= timestamps[mostRecent] + (2 minutes)) internalSetOracleRate(_toSet);
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
		anchor = nextAnchor;
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

	function recalibrate(uint lowerBoundAnchor, uint upperBoundAnchor) external override {
		require(block.timestamp > 1 days + lastRecalibration);
		require(nextAnchor == anchor);
		require(toSet == 0);

		uint _ZCBreserves = ZCBreserves;
		uint _Ureserves = Ureserves;

		uint prevRatio = _ZCBreserves.add(_inflatedTotalSupply()).mul(1 ether).div(_Ureserves);

		int128 prevAnchor = int128(anchor << 64);
		int128 secondsRemaining = int128(( maturity - block.timestamp ) << 64);
		uint newZCBreserves;
		uint newUreserves;
		{
			uint amtZCB = IERC20(ZCBaddress).balanceOf(address(this));
			uint amtYT = IYieldToken(YTaddress).balanceOf_2(address(this), false);

			uint incZCB = amtZCB.sub(_ZCBreserves).sub(_Ureserves);
			uint incYT = amtYT.sub(_Ureserves);

			if (incYT > incZCB) {
				//transfer excess YT growth to the fee oracle sendTo address this will only happen
				//if someone makes a direct transfer of YT to this contract thus the natural yield
				//generated by funds in the amm will never be transfered out
				IYieldToken(YTaddress).transfer_2(FeeOracle(FeeOracleAddress).sendTo(), incYT-incZCB, false);
				amtYT -= incYT - incZCB;
			}
			newUreserves = amtYT;
			newZCBreserves = amtZCB.sub(amtYT);
		}
		require(newUreserves != 0 && newZCBreserves >> 192 == 0);
		uint effectiveTotalSupply = BigMath.ZCB_U_recalibration(
			prevRatio,
			prevAnchor,
			secondsRemaining,
			upperBoundAnchor,
			lowerBoundAnchor,
			newZCBreserves,
			newUreserves
		);
		/*
			effectiveTotalSupply == totalSupply * LPTokenInflation
			LPTokenInflation == effectiveTotalSupply / totalSupply
		*/
		LPTokenInflation = effectiveTotalSupply.mul(1 ether).div(totalSupply);
		ZCBreserves = newZCBreserves;
		Ureserves = newUreserves;
		nextAnchor = lowerBoundAnchor.add(upperBoundAnchor) >> 1;
		lastRecalibration = block.timestamp;
		//non utilized reserves will be paid out as dividends to LPs
	}

	//-----------------------o-t-h-e-r---v-i-e-w-s-----------------------------------------------

	function getReserves() external view override returns (uint _Ureserves, uint _ZCBreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_ZCBreserves = ZCBreserves;
		_TimeRemaining = timeRemaining();
	}

	function inflatedTotalSupply() external view override returns (uint) {
		return _inflatedTotalSupply();
	}


}


