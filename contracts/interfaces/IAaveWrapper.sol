pragma solidity >=0.6.5 <0.7.0;
import "./IERC20.sol";

interface IAaveWrapper is IERC20 {
	function aToken() external view returns(address);
	function firstDeposit(address _to, uint _amountAToken) external returns (uint _amountWrappedToken);
	function deposit(address _to, uint _amountAToken) external returns (uint _amountWrappedToken);
	function withdrawAToken(address _to, uint _amountAToken) external returns (uint _amountWrappedToken);
	function withdrawWrappedToken(address _to, uint _amountWrappedToken) external returns (uint _amountAToken);

	function balanceAToken(address _owner) external view returns (uint balance);
	function ATokenToWrappedToken_RoundDown(uint _amountAToken) external view returns (uint _amountWrappedToken);
	function ATokenToWrappedToken_RoundUp(uint _amountAToken) external view returns (uint _amountWrappedToken);
	function WrappedTokenToAToken_RoundDown(uint _amountWrappedToken) external view returns (uint _amountAToken);
	function WrappedTokenToAToken_RoundUp(uint _amountWrappedToken) external view returns (uint _amountAToken);

}


