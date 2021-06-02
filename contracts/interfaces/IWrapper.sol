// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IERC20.sol";
import "./IERC3156FlashLender.sol";

interface IWrapper is IERC20, IERC3156FlashLender {
	function underlyingAssetAddress() external view returns(address);
	function underlyingIsWrapped() external view returns(bool);
	function infoOracleAddress() external view returns(address);

	function depositUnitAmount(address _to, uint _amount) external returns (uint _amountWrappedToken);
	function depositWrappedAmount(address _to, uint _amount) external returns (uint _amountWrappedToken);
	function withdrawUnitAmount(address _to, uint _amountAToken) external returns (uint _amountWrappedToken);
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken) external returns (uint _amountAToken);

	function forceHarvest() external;

	function lastUpdate() external view returns (uint timestamp);
	function UnitAmtToWrappedAmt_RoundDown(uint _amountAToken) external view returns (uint _amountWrappedToken);
	function UnitAmtToWrappedAmt_RoundUp(uint _amountAToken) external view returns (uint _amountWrappedToken);
	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrappedToken) external view returns (uint _amountAToken);
	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrappedToken) external view returns (uint _amountAToken);
	function getStatus() external view returns (uint updateTimestamp, uint ratio);

	function CALLBACK_SUCCESS() external view returns(bytes32);
	function flashLoanFee() external view returns(uint256);
}


