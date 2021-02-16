pragma solidity >=0.6.5 <0.7.0;
import "./IERC20.sol";

interface IWrapper is IERC20 {
	function underlyingAssetAddress() external view returns(address);
	function underlyingIsWrapped() external view returns(bool);

	function depositUnitAmount(address _to, uint _amount) external returns (uint _amountWrappedToken);
	function depositWrappedAmount(address _to, uint _amount) external returns (uint _amountWrappedToken);
	function withdrawUnitAmount(address _to, uint _amountAToken) external returns (uint _amountWrappedToken);
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken) external returns (uint _amountAToken);

	function balanceUnit(address _owner) external view returns (uint balance);
	function UnitAmtToWrappedAmt_RoundDown(uint _amountAToken) external view returns (uint _amountWrappedToken);
	function UnitAmtToWrappedAmt_RoundUp(uint _amountAToken) external view returns (uint _amountWrappedToken);
	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrappedToken) external view returns (uint _amountAToken);
	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrappedToken) external view returns (uint _amountAToken);

}


