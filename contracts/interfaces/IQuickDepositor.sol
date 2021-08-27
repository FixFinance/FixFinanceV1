// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IQuickDepositor {
	function FastDepositUnderlying(address _fixCapitalPoolAddress, uint _amountUnderlying) external returns(uint wrappedDeposit, uint dynamicDeposit);
	function UnderlyingToZCB(
		address _fixCapitalPoolAddress,
		uint _amountUnderlying,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations
	) external returns(uint yield, int bond);
	function UnderlyingToYT(
		address _fixCapitalPoolAddress,
		uint _amountUnderlying,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations
	) external returns(uint yield, int bond);
}