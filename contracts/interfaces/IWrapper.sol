// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IERC20.sol";
import "./IERC3156FlashLender.sol";

interface IWrapper is IERC20, IERC3156FlashLender {
	function underlyingAssetAddress() external view returns(address);
	function underlyingIsStatic() external view returns(bool);
	function infoOracleAddress() external view returns(address);

	function depositUnitAmount(address _to, uint _amount) external returns (uint _amountWrapped);
	function depositWrappedAmount(address _to, uint _amount) external returns (uint _unitAmount);
	function withdrawUnitAmount(address _to, uint _amount) external returns (uint _amountWrapped);
	function withdrawWrappedAmount(address _to, uint _amount) external returns (uint _unitAmount);

	function forceHarvest() external;

	function lastUpdate() external view returns (uint timestamp);
	function UnitAmtToWrappedAmt_RoundDown(uint _unitAmount) external view returns (uint _amountWrapped);
	function UnitAmtToWrappedAmt_RoundUp(uint _unitAmount) external view returns (uint _amountWrapped);
	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrapped) external view returns (uint _unitAmount);
	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrapped) external view returns (uint _unitAmount);
	function getStatus() external view returns (uint updateTimestamp, uint ratio);

	function flashLoanFee() external view returns(uint256);
}


