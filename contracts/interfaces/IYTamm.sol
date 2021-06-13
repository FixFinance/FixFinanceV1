// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IERC20.sol";
import "./IDividend.sol";

interface IYTamm is IERC20, IDividend {
	function firstMint(uint128 _Uin) external;
	function mint(uint _amount, uint _maxUin, uint _maxYTin) external;
	function burn(uint _amount) external;
	function SwapFromSpecificYT(int128 _amount) external returns (uint);
	function SwapToSpecificYT(int128 _amount) external returns (uint);
	function SwapFromSpecificYTWithLimit(int128 _amount, uint _minUout) external returns (uint);
	function SwapToSpecificYTWithLimit(int128 _amount, uint _maxUin) external returns (uint);
	function ReserveQuoteFromYT(int128 _amount) external returns (uint);
	function ReserveQuoteToYT(int128 _amount) external returns (uint);
	function TakeQuote(uint _amountU, int128 _amountYT, bool _YTin) external;
	function recalibrate() external;
	function inflatedTotalSupply() external view returns (uint);
	function getReserves() external view returns (
		uint _Ureserves,
		uint _YTreserves,
		uint _TimeRemaining
	);

	//length of contractBalance arrays
	function length() external view returns (uint);
    function transferIneligible(address _to, uint256 _value) external returns (bool success);
    function transferIneligibleFrom(address _from, address _to, uint256 _value) external returns (bool success);

    //dividend enabled data
    function ZCBaddress() external view returns(address);
    function YTaddress() external view returns(address);
    function activeTotalSupply() external view returns(uint);
    function lastWithdraw() external view returns(uint);
    function ineligibleBalanceOf(address _owner) external view returns(uint);
    function contractBondDividend(uint _index) external view returns(int);
    function contractYieldDividend(uint _index) external view returns(uint);

    //AYTammData
	function ZCBammAddress() external view returns(address);
	function maturity() external view returns(uint64);
	function lastRecalibration() external view returns(uint);
	function YTtoLmultiplier() external view returns(uint);
	function SlippageConstant() external view returns(uint);
	function FCPaddress() external view returns(address);
}