pragma solidity >=0.6.0;

import "../ERC20.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../capitalHandler.sol";
import "../yieldToken.sol";

contract ZCBamm is ERC20 {

	using ABDKMath64x64 for int128;

	address public capitalHandlerAddress;
	address public yieldTokenAddress;

	uint64 public maturity;
	uint public anchor;

	uint ZCBreserves;
	uint Ureserves;

	constructor(address _capitalHandlerAddress) public {
		name = "aZCB amm Liquidity Token";
		symbol = "aZCBLT";
		capitalHandlerAddress = _capitalHandlerAddress;
		yieldTokenAddress = capitalHandler(_capitalHandlerAddress).yieldTokenAddress();
		uint64 _maturity = capitalHandler(_capitalHandlerAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		maturity = _maturity;
		//we want time remaining / anchor to be less than 1, thus make anchor greater than time remaining
		anchor = 10 * (maturity - block.timestamp) / 9;
	}

	function _mint(address _to, uint _amount) internal {
		balanceOf[_to] += _amount;
		totalSupply += _amount;
	}

	function _burn(address _from, uint _amount) internal {
		require(balanceOf[_from] >= _amount);
		balanceOf[_from] -= _amount;
		totalSupply -= _amount;
	}

	function getU(uint _amount) internal {
		getZCB(_amount);
		getYT(_amount);
	}

	function getZCB(uint _amount) internal {
		capitalHandler(capitalHandlerAddress).transferFrom(msg.sender, address(this), _amount);
	}

	function getYT(uint _amount) internal {
		yieldToken(yieldTokenAddress).transferFrom_2(msg.sender, address(this), _amount);
	}

	function sendU(uint _amount) internal {
		sendZCB(_amount);
		sendYT(_amount);
	}

	function sendZCB(uint _amount) internal {
		capitalHandler(capitalHandlerAddress).transfer(msg.sender, _amount);
	}

	function sendYT(uint _amount) internal {
		yieldToken(yieldTokenAddress).transfer_2(msg.sender, _amount);
	}

	function timeRemaining() internal returns (uint) {
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

}


