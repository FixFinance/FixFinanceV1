pragma solidity >=0.6.0;

import "../helpers/IYTamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IERC20.sol";
import "../helpers/IZCBamm.sol";
import "../FeeOracle.sol";


contract YTamm is IYTamm {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	address public override ZCBammAddress;

	uint64 public override maturity;
	uint public override anchor;

	uint YTreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	address FeeOracleAddress;

	bytes32 quoteSignature;
	int128 quotedAmountYT;
	uint256 quotedAmountU;

	uint public lastRecalibration;
	uint public YTtoLmultiplier;

	constructor(
		address _ZCBammAddress,
		address _feeOracleAddress,
		uint _YTtoLmultiplier
	) public {
		require(_YTtoLmultiplier != 0);
		name = "aYT amm Liquidity Token";
		symbol = "aYTLT";
		address _ZCBaddress = IZCBamm(_ZCBammAddress).ZCBaddress();
		address _YTaddress = IZCBamm(_ZCBammAddress).YTaddress();
		uint64 _maturity = IZCBamm(_ZCBammAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		require(IZCBamm(_ZCBammAddress).getRateFromOracle() > 0);
		maturity = _maturity;
		anchor = IZCBamm(_ZCBammAddress).anchor();
		ZCBammAddress = _ZCBammAddress;
		FeeOracleAddress = _feeOracleAddress;
		YTtoLmultiplier = _YTtoLmultiplier;
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

	function getYTsendU(uint _amountYT, uint _amountU)  internal {
		sendZCB(_amountU);
		if (_amountYT > _amountU) {
			getYT(_amountYT - _amountU);
		}
	}

	function sendYTgetU(uint _amountYT, uint _amountU) internal {
		require(_amountYT > _amountU);
		sendYT(_amountYT - _amountU);
		getZCB(_amountU);
	}

	function getZCB(uint _amount) internal {
		IERC20(ZCBaddress).transferFrom(msg.sender, address(this), _amount);
	}

	function getYT(uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, address(this), _amount, true);
	}

	function sendZCB(uint _amount) internal {
		IERC20(ZCBaddress).transfer(msg.sender, _amount);
	}

	function sendYT(uint _amount) internal {
		IYieldToken(YTaddress).transfer_2(msg.sender, _amount, false);
	}

	function timeRemaining() internal view returns (uint) {
		return uint(int128((maturity-block.timestamp)<<64).div(int128(anchor<<64)));
	}

	function effectiveTotalSupply() internal view returns (uint ret) {
		ret = totalSupply.mul(1 ether) / YTtoLmultiplier;
		require(ret > 0);
	}

	function getQuoteSignature(bool _YTin) internal view returns (bytes32) {
		return keccak256(abi.encodePacked(totalSupply, YTreserves, IZCBamm(ZCBammAddress).getRateFromOracle(), _YTin, block.number));
	}

	function writeQuoteSignature(bool _YTin, int128 _amountYT, uint _amountU) internal returns (bytes32) {
		quoteSignature = getQuoteSignature(_YTin);
		quotedAmountYT = _amountYT;
		quotedAmountU = _amountU;
	}

	modifier verifyQuote(uint _amountU, int128 _amountYT, bool _YTin) {
		require(quotedAmountU == _amountU);
		require(quotedAmountYT == _amountYT);
		require(getQuoteSignature(_YTin) == quoteSignature);
		_;
	}

	/*
		@Description first deposit in pool, pool starts at equilibrim
		this means the implied rate of the pool is the same as the rate fetched from the oracle
	*/
	function firstMint(uint128 _Uin) external override {
		require(totalSupply == 0);
		uint YTin = YTtoLmultiplier.mul(_Uin) / (1 ether);

		getYT(_Uin + YTin);
		getZCB(_Uin);

		_mint(msg.sender, _Uin);

		Ureserves = _Uin;
		YTreserves = YTin;
	}

	function isOutOfSync(int128 _approxYTin) internal view returns (bool) {
		uint _YTreserves = YTreserves;
		require(_approxYTin > 0);
		uint _effectiveTotalSupply = effectiveTotalSupply();
		uint Uchange = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			_effectiveTotalSupply,
			timeRemaining(),
			IZCBamm(ZCBammAddress).getRateFromOracle(),
			_approxYTin
		));
		if (Uchange >= Ureserves) {
			return false;
		}
		uint _MaxYTreserves = _YTreserves + uint(_approxYTin);
		/*
			L = effectiveTotalSupply

			L/_YTreservesAtAPYo == 1
			_YTreservesAtAPYo == L
	
			Thus effectiveTotalSupply == YTLiquidityAboveAPYo
		*/

		//if APYo does not exist along the amm curve
		if (_MaxYTreserves >= _effectiveTotalSupply) {
			return true;
		}
		uint YTliquidityUnderAPYo = _MaxYTreserves - _effectiveTotalSupply;
		if (YTliquidityUnderAPYo < 2*_effectiveTotalSupply) {
			return true;
		}
		return false;
	}

	function recalibrate(int128 _approxYTin) external override {
		require(block.timestamp > lastRecalibration + 4 weeks || isOutOfSync(_approxYTin));
		/*
			Ureserves == (1 - APYo**(-timeRemaining)) * YTreserves

			APYeff == APYo**(L/YTreserves)
			APYerr == APYo
			L/YTreserves == 1
			L == YTreserves
		*/
		uint _YTreserves = YTreserves;
		uint impliedUreserves;
		{
			int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
			int128 _TimeRemaining = int128(timeRemaining());
			// term == OracleRate**(-_TimeRemaining)
			int128 term = OracleRate.log_2().mul(_TimeRemaining).neg().exp_2();
			int128 multiplier = BigMath.ABDK_1.sub(term);
			impliedUreserves = YTreserves.mul(uint(multiplier)) >> 64;
		}
		uint _Ureserves = Ureserves;
		if (_Ureserves > impliedUreserves) {
			Ureserves = impliedUreserves;
		}
		else {
			_YTreserves = _YTreserves.mul(_Ureserves).div(impliedUreserves);
			YTreserves = _YTreserves;
		}
		/*
			L == totalSupply / YTtoLmultiplier
			L/YTreserves == 1
			L == YTreserves
			YTreserves == totalSupply / YTtoLmultiplier
			YTtoLmultiplier == totalSupply / YTreserves
		*/
		YTtoLmultiplier = totalSupply.mul(1 ether) / _YTreserves;
		lastRecalibration = block.timestamp;
	}

	function mint(uint _amount, uint _maxUin, uint _maxYTin) external override {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uin = _amount*Ureserves;
		Uin = Uin/_totalSupply + (Uin%_totalSupply == 0 ? 0 : 1);
		require(Uin <= _maxUin);

		uint YTin = _amount*YTreserves;
		YTin = YTin/_totalSupply + (YTin%_totalSupply == 0 ? 0 : 1);
		require(YTin <= _maxYTin);

		getZCB(Uin);
		getYT(Uin + YTin);

		_mint(msg.sender, _amount);

		Ureserves += Uin;
		YTreserves += YTin;
	}

	function burn(uint _amount) external override {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uout = _amount*Ureserves/_totalSupply;
		uint YTout = _amount*YTreserves/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(Uout);
		sendYT(Uout + YTout);

		Ureserves -= Uout;
		YTreserves -= YTout;
	}

	function SwapFromSpecificYT(int128 _amount) public override returns (uint) {
		require(_amount > 0);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint nonFeeAdjustedUout = uint(-BigMath.YT_U_reserve_change(YTreserves, effectiveTotalSupply(), _TimeRemaining, OracleRate, _amount));
		uint Uout = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, nonFeeAdjustedUout);

		require(Ureserves > Uout);

		getYTsendU(uint(_amount), Uout);

		YTreserves += uint(_amount);
		Ureserves -= Uout;

		emit Swap(msg.sender, uint(_amount), Uout, true);
		return Uout;
	}

	function SwapToSpecificYT(int128 _amount) public override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint nonFeeAdjustedUin = uint(BigMath.YT_U_reserve_change(_YTreserves, effectiveTotalSupply(), _TimeRemaining, OracleRate, -_amount));
		uint Uin = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, nonFeeAdjustedUin);

		sendYTgetU(uint(_amount), Uin);

		YTreserves -= uint(_amount);
		Ureserves += Uin;

		emit Swap(msg.sender, uint(_amount), Uin, false);
		return Uin;
	}

	function SwapFromSpecificYTWithLimit(int128 _amount, uint _minUout) external override returns (uint) {
		uint ret = SwapFromSpecificYT(_amount);
		require(ret >= _minUout);
		return ret;
	}

	function SwapToSpecificYTWithLimit(int128 _amount, uint _maxUin) external override returns (uint) {
		uint ret = SwapToSpecificYT(_amount);
		require(ret <= _maxUin);
		return ret;
	}

	function ReserveQuoteFromYT(int128 _amount) external override returns (uint) {
		require(_amount > 0);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint _YTreserves = YTreserves;
		uint nonFeeAdjustedUout = uint(-BigMath.YT_U_reserve_change(_YTreserves, effectiveTotalSupply(), _TimeRemaining, OracleRate, _amount));
		uint Uout = FeeOracle(FeeOracleAddress).feeAdjustedAmountOut(maturity, nonFeeAdjustedUout);
		require(Ureserves > Uout);
		writeQuoteSignature(true, _amount, Uout);
		return Uout;
	}

	function ReserveQuoteToYT(int128 _amount) external override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint nonFeeAdjustedUin = uint(BigMath.YT_U_reserve_change(_YTreserves, effectiveTotalSupply(), _TimeRemaining, OracleRate, -_amount));
		uint Uin = FeeOracle(FeeOracleAddress).feeAdjustedAmountIn(maturity, nonFeeAdjustedUin);
		writeQuoteSignature(false, _amount, Uin);
		return Uin;
	}

	function TakeQuote(uint _amountU, int128 _amountYT, bool _YTin) external override verifyQuote(_amountU, _amountYT, _YTin) {
		if (_YTin) {
			require(Ureserves > _amountU);
			getYTsendU(uint(_amountYT), _amountU);
			YTreserves += uint(_amountYT);
			Ureserves -= _amountU;
		} else {
			require(YTreserves > uint(_amountYT));
			sendYTgetU(uint(_amountYT), _amountU);
			Ureserves += _amountU;
			YTreserves -= uint(_amountYT);
		}

		emit Swap(msg.sender, uint(_amountYT), _amountU, _YTin);
	}


	//-------------------------implement double asset yield enabled token-------------------------------
	function contractClaimDividend() external override {
		require(lastWithdraw < block.timestamp - 86400, "this function can only be called once every 24 hours");

		uint _YTreserves = YTreserves;	//gas savings
		uint _Ureserves = Ureserves;	//gas savings

		uint amount = IERC20(ZCBaddress).balanceOf(address(this));
		require(amount > _Ureserves);
		amount = amount - _Ureserves + ZCBdividendOut;
		require(amount > contractBalanceAsset1[contractBalanceAsset1.length-1]);
		contractBalanceAsset1.push(amount);

		amount = IYieldToken(YTaddress).balanceOf_2(address(this), false);
		require(amount > _Ureserves + _YTreserves);
		amount = amount - _Ureserves - _YTreserves + YTdividendOut;
		require(amount > contractBalanceAsset2[contractBalanceAsset2.length-1]);
		contractBalanceAsset2.push(amount);

		lastWithdraw = block.timestamp;
	}


	//------------------------------v-i-e-w-s-----------------------------------------------

	function getReserves() external view override returns (uint _Ureserves, uint _YTreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_YTreserves = YTreserves;
		_TimeRemaining = timeRemaining();
	}

}

