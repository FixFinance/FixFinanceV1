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

	/*
		@Description first deposit in pool

	*/
	function firstMint(uint128 _Uin, uint128 _ZCBin) public {
		require(totalSupply == 0);
		_mint(msg.sender, _Uin);

		uint r = uint(int128((maturity-block.timestamp)<<64).div(int128(anchor<<64)));
		uint _Uout = uint(- BigMath.ZUB_U_reserve_change(_Uin, _Uin, r, int128(_ZCBin) ) );

		require(_Uout < _Uin);
		uint effectiveU = _Uin - _Uout;

		getZCB(effectiveU + _ZCBin);
		getYT(effectiveU);

		ZCBreserves = _ZCBin;
		Ureserves = effectiveU;
	}

/*

	function mint(uint _amount, uint _maxUIn, uint _maxZCBin) public {}

	function burn() public {}

	function SwapFromSpecificTokens(uint _amount, bool _ZCBin) public {}

	function SwapToSpecificTokens(uint _amount, bool _ZCBin) public {}

*/


}


