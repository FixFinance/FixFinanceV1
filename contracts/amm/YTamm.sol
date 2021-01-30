pragma solidity >=0.6.0;

import "../helpers/IYTamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IERC20.sol";
import "../helpers/IZCBamm.sol";

contract YTamm is IYTamm {

	using ABDKMath64x64 for int128;

	address public override ZCBammAddress;

	uint64 public override maturity;
	uint public override anchor;

	uint YTreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	bytes32 quoteSignature;
	int128 quotedAmountYT;
	uint256 quotedAmountU;

	uint32 YTtoLmultiplier;

	constructor(address _ZCBammAddress, uint32 _YTtoLmultiplier) public {
		name = "aYT amm Liquidity Token";
		symbol = "aYTLT";
		address _ZCBaddress = IZCBamm(_ZCBammAddress).ZCBaddress();
		address _YTaddress = IZCBamm(_ZCBammAddress).YTaddress();
		uint64 _maturity = IZCBamm(_ZCBammAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		maturity = _maturity;
		anchor = IZCBamm(_ZCBammAddress).anchor();
		ZCBammAddress = _ZCBammAddress;
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

	function getU(uint _amount) internal {
		getZCB(_amount);
		getYT(_amount);
	}

	function getZCB(uint _amount) internal {
		IERC20(ZCBaddress).transferFrom(msg.sender, address(this), _amount);
	}

	function getYT(uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, address(this), _amount, true);
	}

	function sendU(uint _amount) internal {
		sendZCB(_amount);
		sendYT(_amount);
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

	function getQuoteSignature(bool _YTin) internal view returns (bytes32) {
		return keccak256(abi.encodePacked(totalSupply, YTreserves, IZCBamm(ZCBammAddress).getRateFromOracle(), _YTin, block.number));
	}

	function writeQuoteSignature(uint _totalSupply, uint _YTreserves, int _oracleRate, bool _YTin, int128 _amountYT, uint _amountU) internal returns (bytes32) {
		quoteSignature = keccak256(abi.encodePacked(_totalSupply, _YTreserves, _oracleRate, _YTin, block.number));
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
		uint YTin = YTtoLmultiplier * _Uin;

		getYT(_Uin + YTin);
		getZCB(_Uin);

		_mint(msg.sender, _Uin);

		Ureserves = _Uin;
		YTreserves = YTin;
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

	function SwapFromSpecificYT(int128 _amount) external override {
		require(_amount > 0);
		uint _totalSupply = totalSupply;
		uint _YTtoLmultiplier = YTtoLmultiplier;
		require(_totalSupply > _YTtoLmultiplier);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint Uout = uint(-BigMath.YT_U_reserve_change(YTreserves, _totalSupply / _YTtoLmultiplier, _TimeRemaining, OracleRate, _amount));

		require(Ureserves > Uout);

		getYT(uint(_amount));
		sendU(Uout);

		YTreserves += uint(_amount);
		Ureserves -= Uout;

		emit Swap(msg.sender, uint(_amount), Uout, true);
	}

	function reserveQuoteFromYT(int128 _amount) external returns (uint) {
		require(_amount > 0);
		uint _totalSupply = totalSupply;
		uint _YTtoLmultiplier = YTtoLmultiplier;
		require(_totalSupply > _YTtoLmultiplier);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint _YTreserves = YTreserves;
		uint Uout = uint(-BigMath.YT_U_reserve_change(_YTreserves, _totalSupply / _YTtoLmultiplier, _TimeRemaining, OracleRate, _amount));
		require(Ureserves > Uout);
		writeQuoteSignature(_totalSupply, _YTreserves, OracleRate, true, _amount, Uout);
		return Uout;
	}

	function SwapToSpecificYT(int128 _amount) external override {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		uint _totalSupply = totalSupply;
		uint _YTtoLmultiplier = YTtoLmultiplier;
		require(_totalSupply > _YTtoLmultiplier);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint Uin = uint(BigMath.YT_U_reserve_change(_YTreserves, _totalSupply / _YTtoLmultiplier, _TimeRemaining, OracleRate, -_amount));

		getU(Uin);
		sendYT(uint(_amount));

		YTreserves -= uint(_amount);
		Ureserves += Uin;

		emit Swap(msg.sender, uint(_amount), Uin, false);
	}

	function reserveQuoteToYT(int128 _amount) external returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		uint _totalSupply = totalSupply;
		uint _YTtoLmultiplier = YTtoLmultiplier;
		require(_totalSupply > _YTtoLmultiplier);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getRateFromOracle();
		uint Uin = uint(BigMath.YT_U_reserve_change(_YTreserves, _totalSupply / _YTtoLmultiplier, _TimeRemaining, OracleRate, -_amount));
		writeQuoteSignature(_totalSupply, _YTreserves, OracleRate, false, _amount, Uin);
		return Uin;
	}

	function TakeQuote(uint _amountU, int128 _amountYT, bool _YTin) external override verifyQuote(_amountU, _amountYT, _YTin) {
		if (_YTin) {
			require(Ureserves > _amountU);
			getYT(uint(_amountYT));
			sendU(_amountU);
			YTreserves += uint(_amountYT);
			Ureserves -= _amountU;
		} else {
			require(YTreserves > uint(_amountYT));
			getU(_amountU);
			sendYT(uint(_amountYT));
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

	function getReserves() external view returns (uint _Ureserves, uint _YTreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_YTreserves = YTreserves;
		_TimeRemaining = timeRemaining();
	}

}

