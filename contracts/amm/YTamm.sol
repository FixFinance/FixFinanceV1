pragma solidity >=0.6.0;

import "../helpers/IYTamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IERC20.sol";
import "../helpers/IZCBamm.sol";
import "../AmmInfoOracle.sol";


contract YTamm is IYTamm {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	address public override ZCBammAddress;

	uint64 public override maturity;

	uint YTreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	address AmmInfoOracleAddress;

	bytes32 quoteSignature;
	int128 quotedAmountYT;
	uint256 quotedAmountU;
	uint256 quotedTreasuryFee;

	uint public lastRecalibration;
	uint public YTtoLmultiplier;
	uint public SlippageConstant;

	int128 _2WeeksABDK = int128((2 weeks << 64)/BigMath.SecondsPerYear);

	constructor(
		address _ZCBammAddress,
		address _feeOracleAddress
	) public {
		name = "aYT amm Liquidity Token";
		symbol = "aYTLT";
		address _ZCBaddress = IZCBamm(_ZCBammAddress).ZCBaddress();
		address _YTaddress = IZCBamm(_ZCBammAddress).YTaddress();
		uint64 _maturity = IZCBamm(_ZCBammAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		int128 apy = IZCBamm(_ZCBammAddress).getAPYFromOracle();
		require(apy > 0);
		maturity = _maturity;
		ZCBammAddress = _ZCBammAddress;
		AmmInfoOracleAddress = _feeOracleAddress;
		SlippageConstant = AmmInfoOracle(_feeOracleAddress).SlippageConstant();
		YTtoLmultiplier = BigMath.YT_U_ratio(
			apy,
			maturity-block.timestamp
		);
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

	function getYTsendU(uint _amountYT, uint _amountU, uint _treasuryFee, address _treasuryAddress)  internal {
		sendZCB(msg.sender, _amountU);
		if (_amountYT > _amountU) {
			getYT(address(this), _amountYT - _amountU);
		}

		sendYT(_treasuryAddress, _treasuryFee);
		sendZCB(_treasuryAddress, _treasuryFee);
	}

	function sendYTgetU(uint _amountYT, uint _amountU, uint _treasuryFee, address _treasuryAddress) internal {
		require(_amountYT > _amountU);
		sendYT(msg.sender, _amountYT - _amountU);
		getZCB(address(this), _amountU);

		sendYT(_treasuryAddress, _treasuryFee);
		sendZCB(_treasuryAddress, _treasuryFee);
	}

	function getZCB(address _to, uint _amount) internal {
		IERC20(ZCBaddress).transferFrom(msg.sender, _to, _amount);
	}

	function getYT(address _to, uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, _to, _amount, true);
	}

	function sendZCB(address _to, uint _amount) internal {
		IERC20(ZCBaddress).transfer(_to, _amount);
	}

	function sendYT(address _to, uint _amount) internal {
		IYieldToken(YTaddress).transfer_2(_to, _amount, false);
	}

	function timeRemaining() internal view returns (int128) {
		return int128((maturity-block.timestamp)<<64) / int128(BigMath.SecondsPerYear);
	}

	function _inflatedTotalSupply() internal view returns (uint ret) {
		ret = totalSupply.mul(1 ether) / YTtoLmultiplier;
		require(ret > 0);
	}

	function getQuoteSignature(bool _YTin) internal view returns (bytes32) {
		IZCBamm zcbamm = IZCBamm(ZCBammAddress);
		return keccak256(abi.encodePacked(totalSupply, YTreserves, zcbamm.getRateFromOracle(), zcbamm.anchor(), _YTin, block.number));
	}

	function writeQuoteSignature(bool _YTin, int128 _amountYT, uint _amountU, uint _treasuryFee) internal returns (bytes32) {
		quoteSignature = getQuoteSignature(_YTin);
		quotedAmountYT = _amountYT;
		quotedAmountU = _amountU;
		quotedTreasuryFee = _treasuryFee;
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

		getYT(address(this), _Uin + YTin);
		getZCB(address(this), _Uin);

		_mint(msg.sender, _Uin);

		Ureserves = _Uin;
		YTreserves = YTin;
	}

	function isOutOfSync(int128 _approxYTin) internal view returns (bool) {
		uint _YTreserves = YTreserves;
		require(_approxYTin > 0);
		uint effectiveTotalSupply = _inflatedTotalSupply();
		uint Uchange = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			effectiveTotalSupply,
			uint(timeRemaining()),
			SlippageConstant,
			IZCBamm(ZCBammAddress).getAPYFromOracle(),
			_approxYTin
		));
		if (Uchange < Ureserves) {
			// in this case _approxYTin is of no use to us as an upper bound 
			return false;
		}
		uint _MaxYTreserves = _YTreserves + uint(_approxYTin);
		/*
			L = effectiveTotalSupply

			L/_YTreservesAtAPYo == 1
			_YTreservesAtAPYo == L
	
			Thus effectiveTotalSupply == YTLiquidityAboveAPYo
		*/

		//if APYo does not exist along the amm curve return out of sync
		if (_MaxYTreserves >= effectiveTotalSupply) {
			return true;
		}
		uint YTliquidityUnderAPYo = _MaxYTreserves - effectiveTotalSupply;
		if (YTliquidityUnderAPYo < 2*effectiveTotalSupply) {
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
			int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
			int128 _TimeRemaining = timeRemaining();
			//we want to recalibrate such that it is perfectly calibrated at the
			//midpoint in time between this recalibration and the next
			if (_TimeRemaining > 2*_2WeeksABDK) {
				_TimeRemaining = _TimeRemaining.sub(_2WeeksABDK);
			}
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
		//ensure noone reserves quote before recalibrating and is then able to take the quote
		quoteSignature = bytes32(0);
	}

	function mint(uint _amount, uint _maxUin, uint _maxYTin) external override {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uin = _amount*Ureserves;
		Uin = Uin/_totalSupply + (Uin%_totalSupply == 0 ? 0 : 1);
		require(Uin <= _maxUin);

		uint YTin = _amount*YTreserves;
		YTin = YTin/_totalSupply + (YTin%_totalSupply == 0 ? 0 : 1);
		require(YTin <= _maxYTin);

		getZCB(address(this), Uin);
		getYT(address(this), Uin + YTin);

		_mint(msg.sender, _amount);

		Ureserves += Uin;
		YTreserves += YTin;
	}

	function burn(uint _amount) external override {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uout = _amount*Ureserves/_totalSupply;
		uint YTout = _amount*YTreserves/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(msg.sender, Uout);
		sendYT(msg.sender, Uout + YTout);

		Ureserves -= Uout;
		YTreserves -= YTout;
	}

	function SwapFromSpecificYT(int128 _amount) public override returns (uint) {
		require(_amount > 0);
		int128 _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint nonFeeAdjustedUout = uint(-BigMath.YT_U_reserve_change(
			YTreserves,
			_inflatedTotalSupply(),
			uint(_TimeRemaining),
			SlippageConstant,
			OracleRate,
			_amount
		));
		(uint Uout, uint treasuryFee, address sendTo) = AmmInfoOracle(AmmInfoOracleAddress).YT_U_feeAdjustedAmtOut(_TimeRemaining, uint(_amount), nonFeeAdjustedUout);
		uint reserveDecrease = Uout.add(treasuryFee);

		require(Ureserves >= reserveDecrease);

		getYTsendU(uint(_amount), Uout, treasuryFee, sendTo);

		YTreserves += uint(_amount);
		Ureserves -= reserveDecrease;

		emit Swap(msg.sender, uint(_amount), Uout, true);
		return Uout;
	}

	function SwapToSpecificYT(int128 _amount) public override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		int128 _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint nonFeeAdjustedUin = uint(BigMath.YT_U_reserve_change(
			_YTreserves,
			_inflatedTotalSupply(),
			uint(_TimeRemaining),
			SlippageConstant,
			OracleRate,
			-_amount
		));
		(uint Uin, uint treasuryFee, address sendTo) = AmmInfoOracle(AmmInfoOracleAddress).YT_U_feeAdjustedAmtIn(_TimeRemaining, uint(_amount), nonFeeAdjustedUin);
		uint reserveIncrease = Uin.sub(treasuryFee);

		sendYTgetU(uint(_amount), Uin, treasuryFee, sendTo);

		YTreserves -= uint(_amount);
		Ureserves += reserveIncrease;

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
		int128 _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint _YTreserves = YTreserves;
		uint nonFeeAdjustedUout = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			_inflatedTotalSupply(),
			uint(_TimeRemaining),
			SlippageConstant,
			OracleRate,
			_amount
		));
		(uint Uout, uint treasuryFee, ) = AmmInfoOracle(AmmInfoOracleAddress).YT_U_feeAdjustedAmtOut(_TimeRemaining, uint(_amount), nonFeeAdjustedUout);
		uint reserveDecrease = Uout.add(treasuryFee);
		require(Ureserves >= reserveDecrease);
		writeQuoteSignature(true, _amount, Uout, treasuryFee);
		return Uout;
	}

	function ReserveQuoteToYT(int128 _amount) external override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		int128 _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint nonFeeAdjustedUin = uint(BigMath.YT_U_reserve_change(
			_YTreserves,
			_inflatedTotalSupply(),
			uint(_TimeRemaining),
			SlippageConstant,
			OracleRate,
			-_amount
		));
		(uint Uin, uint treasuryFee, ) = AmmInfoOracle(AmmInfoOracleAddress).YT_U_feeAdjustedAmtIn(_TimeRemaining, uint(_amount), nonFeeAdjustedUin);
		writeQuoteSignature(false, _amount, Uin, treasuryFee);
		return Uin;
	}

	function TakeQuote(uint _amountU, int128 _amountYT, bool _YTin) external override verifyQuote(_amountU, _amountYT, _YTin) {
		uint _quotedTreasuryFee = quotedTreasuryFee;
		address sendTo = AmmInfoOracle(AmmInfoOracleAddress).sendTo();
		if (_YTin) {
			uint reserveDecrease = _amountU.add(_quotedTreasuryFee);
			require(Ureserves >= reserveDecrease);
			getYTsendU(uint(_amountYT), _amountU, _quotedTreasuryFee, sendTo);
			YTreserves += uint(_amountYT);
			Ureserves -= reserveDecrease;
		} else {
			uint reserveIncrease = _amountU.sub(_quotedTreasuryFee);
			require(YTreserves > uint(_amountYT));
			sendYTgetU(uint(_amountYT), _amountU, _quotedTreasuryFee, sendTo);
			Ureserves += reserveIncrease;
			YTreserves -= uint(_amountYT);
		}

		emit Swap(msg.sender, uint(_amountYT), _amountU, _YTin);
	}


	//-------------------------implement double asset yield enabled token-------------------------------
	function contractClaimDividend() external override {
		require(lastWithdraw + 1 days < block.timestamp, "this function can only be called once every 24 hours");

		uint _YTreserves = YTreserves;	//gas savings
		uint _Ureserves = Ureserves;	//gas savings
		uint _YT_Ur = _Ureserves + _YTreserves;

		uint amtZCB = IERC20(ZCBaddress).balanceOf(address(this));
		uint amtYT = IYieldToken(YTaddress).balanceOf_2(address(this), false);
		require(amtZCB > _Ureserves);
		require(amtYT > _YT_Ur);
		amtZCB = amtZCB - _Ureserves + ZCBdividendOut;
		amtYT = amtYT - _YT_Ur + YTdividendOut;

		uint prevAsset1 = contractBalanceAsset1[contractBalanceAsset1.length-1];
		uint prevAsset2 = contractBalanceAsset2[contractBalanceAsset2.length-1];

		require(amtZCB > prevAsset1);
		require(amtYT > prevAsset2);

		{
			uint ZCBoverReserves = amtZCB - prevAsset1;
			uint YToverReserves = amtYT - prevAsset2;

			uint ZCBoverutilization = ZCBoverReserves.mul(1 ether).div(_Ureserves);
			uint YToverutilization = YToverReserves.mul(1 ether).div(_YT_Ur);

			/*
				Scale up reserves and effective total supply as much as possible
			*/
			if (ZCBoverutilization > YToverutilization) {
				uint scaledZCBoverReserves = ZCBoverReserves.mul(YToverutilization).div(ZCBoverutilization);

				amtZCB = ZCBoverReserves.sub(scaledZCBoverReserves).add(prevAsset1);
				amtYT = prevAsset2;

				YTreserves += YToverReserves.sub(scaledZCBoverReserves);
				Ureserves += scaledZCBoverReserves;

				/*
					L == effectiveTotalSupply == totalSupply / YTtoLmultiplier
					
					L * (1 + YToverutilization) == totalSupply / (YTtoLmultiplier / (1 + YToverutilization) )

					to increase L by YToverutilization do:
					YTtoLmultiplier /= 1 + YToverutilization
				*/
				YTtoLmultiplier = YTtoLmultiplier.mul(1 ether).div((YToverutilization).add(1 ether));
			}
			else {
				uint scaledYToverReserves = YToverReserves.mul(ZCBoverutilization).div(YToverutilization);

				amtZCB = prevAsset1;
				amtYT = YToverReserves.sub(scaledYToverReserves).add(prevAsset2);

				YTreserves += scaledYToverReserves.sub(ZCBoverReserves);
				Ureserves += ZCBoverReserves;
				/*
					L == effectiveTotalSupply == totalSupply / YTtoLmultiplier
					
					L * (1 + ZCBoverutilization) == totalSupply / (YTtoLmultiplier / (1 + ZCBoverutilization) )

					to increase L by ZCBoverutilization do:
					YTtoLmultiplier /= 1 + ZCBoverutilization
				*/
				YTtoLmultiplier = YTtoLmultiplier.mul(1 ether).div((ZCBoverutilization).add(1 ether));
			}
		}

		contractBalanceAsset1.push(amtZCB);
		contractBalanceAsset2.push(amtYT);

		lastWithdraw = block.timestamp;
	}


	//------------------------------v-i-e-w-s-----------------------------------------------

	function getReserves() external view override returns (uint _Ureserves, uint _YTreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_YTreserves = YTreserves;
		_TimeRemaining = uint(timeRemaining());
	}

	function inflatedTotalSupply() external override view returns (uint) {
		return _inflatedTotalSupply();
	}

}

