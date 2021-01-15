pragma solidity >=0.6.0;

import "../helpers/doubleAssetYieldEnabledToken.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../capitalHandler.sol";
import "../yieldToken.sol";

contract ZCBamm is doubleAssetYieldEnabledToken {

	using ABDKMath64x64 for int128;

	uint64 public maturity;
	uint public anchor;

	uint ZCBreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	constructor(address _ZCBaddress) public {
		name = "aZCB amm Liquidity Token";
		symbol = "aZCBLT";
		address _YTaddress = capitalHandler(_ZCBaddress).yieldTokenAddress();
		uint64 _maturity = capitalHandler(_ZCBaddress).maturity();
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
		@Description first deposit in pool
	*/
	function firstMint(uint128 _Uin, uint128 _ZCBin) public {
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

	function mint(uint _amount, uint _maxUin, uint _maxZCBin) public {
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

	function burn(uint _amount) public {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uout = _amount*Ureserves/_totalSupply;
		uint ZCBout = _amount*ZCBreserves/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(Uout + ZCBout);
		sendYT(Uout);

		Ureserves -= Uout;
		ZCBreserves -= ZCBout;
	}

	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) public {
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
		} else {
			_amtOut = -int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, _amount));

			require(_amtOut > 0);
			require(_amount < _amtOut, "cannot swap to ZCB at negative rate");

			require(ZCBreserves > uint(_amtOut));

			getU(uint(_amount));
			sendZCB(uint(_amtOut));

			Ureserves += uint(_amount);
			ZCBreserves -= uint(_amtOut);
		}

	}

	function SwapToSpecificTokens(int128 _amount, bool _ZCBout) public {
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
		} else {
			require(Ureserves >= uint(_amount));
			_amtIn = int(BigMath.ZCB_U_reserve_change(Ureserves, ZCBreserves+totalSupply, r, -_amount));

			require(_amtIn > 0);

			getZCB(uint(_amtIn));
			sendU(uint(_amount));

			ZCBreserves += uint(_amtIn);
			Ureserves -= uint(_amount);
		}

	}


	//-------------------------implement double asset yield enabled token-------------------------------
	function contractClaimDividend() external override {
		require(lastWithdraw < block.timestamp - 86400, "this function can only be called once every 24 hours");

		uint _ZCBreserves = ZCBreserves;	//gas savings
		uint _Ureserves = Ureserves;	//gas savings

		uint amount = capitalHandler(ZCBaddress).balanceOf(address(this));
		require(amount > _ZCBreserves + _Ureserves);
		amount = amount - _ZCBreserves - _Ureserves + ZCBdividendOut;
		require(amount > contractBalanceAsset1[contractBalanceAsset1.length-1]);
		contractBalanceAsset1.push(amount);

		amount = yieldToken(YTaddress).balanceOf_2(address(this));
		require(amount > _Ureserves);
		amount = amount - _Ureserves + YTdividendOut;
		require(amount > contractBalanceAsset2[contractBalanceAsset2.length-1]);
		contractBalanceAsset2.push(amount);

		lastWithdraw = block.timestamp;
	}


	//------------------------------v-i-e-w-s-----------------------------------------------

	function getReserves() external view returns (uint _Ureserves, uint _ZCBreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_ZCBreserves = ZCBreserves;
		_TimeRemaining = timeRemaining();
	}


}


