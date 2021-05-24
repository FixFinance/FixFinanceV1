// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IERC20.sol";

abstract contract IZCBamm is IERC20 {
	event Mint(
		address user,
		uint amount
	);

	event Burn(
		address user,
		uint amount
	);

	event Swap(
		address user,
		uint amountZCB,
		uint amountU,
		bool ZCBin
	);

	uint8 private constant LENGTH_RATE_SERIES = 31;

	function forceRateDataUpdate() external virtual;
	function maturity() external virtual view returns (uint64);
	function anchor() external virtual view returns (uint);
	function nextAnchor() external virtual view returns (uint);
	function firstMint(uint128 _Uin, uint128 _ZCBin) external virtual;
	function mint(uint _amount, uint _maxUin, uint _maxZCBin) external virtual;
	function burn(uint _amount) external virtual;
	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _out);
	function SwapToSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _in);
	function SwapFromSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _minAmtOut) external virtual returns(uint _out);
	function SwapToSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _maxAmtIn) external virtual returns(uint _in);
	function ReserveQuoteFromSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _out);
	function ReserveQuoteToSpecificTokens(int128 _amount, bool _ZCBin) external virtual returns(uint _out);
	function TakeQuote(uint _amountIn, uint _amountOut, bool _ZCBin, bool _ToSpecific) external virtual;
	function recalibrate(uint lowerBoundAnchor, uint upperBoundAnchor) external virtual;
	function inflatedTotalSupply() external virtual view returns (uint);
	function getRateFromOracle() external virtual view returns (int128 rate);
	function getAPYFromOracle() external virtual view returns (int128 APY);
	function impliedYieldToMaturity() external virtual view returns (int128 yield);
	function impliedYieldOverYears(int128 _years) external virtual view returns (int128 yield);
	function getImpliedRateData() external virtual view returns (
		int128[LENGTH_RATE_SERIES] memory _impliedRates,
		uint[LENGTH_RATE_SERIES] memory _timestamps
	);
	function getReserves() external virtual view returns (
		uint _Ureserves,
		uint _ZCBreserves,
		uint _TimeRemaining
	);


	//---------------------f-o-r---I-E_R_C-2-0-----------------------
	address public ZCBaddress;
	address public YTaddress;
	address public FCPaddress;

	//total amount of smallest denomination units of coin in this smart contract
	uint public override totalSupply;
	//10 ** decimals == the amount of sub units in a whole coin
	uint8 public override decimals = 18;
	//each user's balance of coins
	mapping(address => uint) public override balanceOf;
	//the amount of funds each address has allowed other addresses to spend on the first address's behalf
	//holderOfFunds => spender => amountOfFundsAllowed
	mapping(address => mapping(address => uint)) public override allowance;


    function transfer(address _to, uint256 _value) public override returns (bool success) {
        require(_value <= balanceOf[msg.sender]);

        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        allowance[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);
    	require(_value <= balanceOf[_from]);

    	balanceOf[_from] -= _value;
    	balanceOf[_to] += _value;

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }


}