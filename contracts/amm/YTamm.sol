pragma solidity >=0.6.0;

import "../helpers/doubleAssetYieldEnabledToken.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../capitalHandler.sol";
import "../yieldToken.sol";
import "./ZCBamm.sol";

contract YTamm is doubleAssetYieldEnabledToken {

	using ABDKMath64x64 for int128;

	address public ZCBammAddress;

	uint64 public maturity;
	uint public anchor;

	uint YTreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	uint32 YTtoLmultiplier;

	constructor(address _ZCBammAddress, uint32 _YTtoLmultiplier) public {
		name = "aYT amm Liquidity Token";
		symbol = "aYTLT";
		address _ZCBaddress = ZCBamm(_ZCBammAddress).ZCBaddress();
		address _YTaddress = ZCBamm(_ZCBammAddress).YTaddress();
		uint64 _maturity = ZCBamm(_ZCBammAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		maturity = _maturity;
		anchor = ZCBamm(_ZCBammAddress).anchor();
		ZCBammAddress = _ZCBammAddress;
		YTtoLmultiplier = _YTtoLmultiplier;
		init(_ZCBaddress, _YTaddress);
	}

	function _mint(address _to, uint _amount) internal {
        claimDividendInternal(_to, _to);
		balanceOf[_to] += _amount;
		totalSupply += _amount;
	}

	function _burn(address _from, uint _amount) internal {
		require(balanceOf[_from] >= _amount);
        claimDividendInternal(_from, _from);
		balanceOf[_from] -= _amount;
		totalSupply -= _amount;
	}

	function getU(uint _amount) internal {
		getZCB(_amount);
		getYT(_amount);
	}

	function getZCB(uint _amount) internal {
		capitalHandler(ZCBaddress).transferFrom(msg.sender, address(this), _amount);
	}

	function getYT(uint _amount) internal {
		yieldToken(YTaddress).transferFrom_2(msg.sender, address(this), _amount, true);
	}

	function sendU(uint _amount) internal {
		sendZCB(_amount);
		sendYT(_amount);
	}

	function sendZCB(uint _amount) internal {
		capitalHandler(ZCBaddress).transfer(msg.sender, _amount);
	}

	function sendYT(uint _amount) internal {
		yieldToken(YTaddress).transfer_2(msg.sender, _amount, false);
	}

	function timeRemaining() internal view returns (uint) {
		return uint(int128((maturity-block.timestamp)<<64).div(int128(anchor<<64)));
	}

	/*
		@Description first deposit in pool, pool starts at equilibrim
		this means the implied rate of the pool is the same as the rate fetched from the oracle
	*/
	function firstMint(uint128 _Uin) public {
		require(totalSupply == 0);
		uint YTin = YTtoLmultiplier * _Uin;

		getYT(_Uin + YTin);
		getZCB(_Uin);

		_mint(msg.sender, _Uin);

		Ureserves = _Uin;
		YTreserves = YTin;
	}

	function mint(uint _amount, uint _maxUin, uint _maxYTin) public {
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

	function burn(uint _amount) public {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uout = _amount*Ureserves/_totalSupply;
		uint YTout = _amount*YTreserves/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(Uout);
		sendYT(Uout + YTout);

		Ureserves -= Uout;
		YTreserves -= YTout;
	}

	function SwapFromSpecificYT(int128 _amount) public {
		require(_amount > 0);
		uint _totalSupply = totalSupply;
		uint _YTtoLmultiplier = YTtoLmultiplier;
		require(_totalSupply > _YTtoLmultiplier);
		uint _TimeRemaining = timeRemaining();
		int128 APYo = ZCBamm(ZCBammAddress).getRateFromOracle();
		uint Uout = uint(-BigMath.YT_U_reserve_change(YTreserves, _totalSupply / _YTtoLmultiplier, _TimeRemaining, APYo, _amount));

		require(Ureserves > Uout);

		getYT(uint(_amount));
		sendU(Uout);

		YTreserves += uint(_amount);
		Ureserves -= Uout;
	}

	function SwapToSpecificYT(int128 _amount) public {
		require(_amount > 0);
		uint _totalSupply = totalSupply;
		uint _YTtoLmultiplier = YTtoLmultiplier;
		require(_totalSupply > _YTtoLmultiplier);
		uint _TimeRemaining = timeRemaining();
		int128 APYo = ZCBamm(ZCBammAddress).getRateFromOracle();
		uint Uin = uint(BigMath.YT_U_reserve_change(YTreserves, _totalSupply / _YTtoLmultiplier, _TimeRemaining, APYo, -_amount));

		require(YTreserves > uint(_amount));

		getU(Uin);
		sendYT(uint(_amount));

		YTreserves -= uint(_amount);
		Ureserves += Uin;
	}


	//-------------------------implement double asset yield enabled token-------------------------------
	function contractClaimDividend() external override {
		require(lastWithdraw < block.timestamp - 86400, "this function can only be called once every 24 hours");

		uint _YTreserves = YTreserves;	//gas savings
		uint _Ureserves = Ureserves;	//gas savings

		uint amount = capitalHandler(ZCBaddress).balanceOf(address(this));
		require(amount > _Ureserves);
		amount = amount - _Ureserves + ZCBdividendOut;
		require(amount > contractBalanceAsset1[contractBalanceAsset1.length-1]);
		contractBalanceAsset1.push(amount);

		amount = yieldToken(YTaddress).balanceOf_2(address(this));
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


