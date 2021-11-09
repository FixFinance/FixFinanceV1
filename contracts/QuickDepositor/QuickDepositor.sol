// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IOrderbookExchange.sol";
import "../interfaces/IOrganizer.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IQuickDepositor.sol";

contract QuickDepositor is IQuickDepositor {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	//data
	IOrganizer org;

	uint constant bufferAmount = 0x1000; //used to offset rounding errors

	/*
		init
	*/
	constructor(address _organizerAddress) public {
		org = IOrganizer(_organizerAddress);
	}

	/*
		@Description: deposit underlying into wrapper then into FCP

		@param address _depositTo: the address that shall recieve the ZCB & YT upon depositing into the FCP
		@param address _fixCapitalPoolAddress: the address of the FCP contract to deposit into
		@param uint _amountUnderlying: the amount of the underlying ERC20 to deposit
	*/
	function internalFastDepositUnderlying(
		address _depositTo,
		address _fixCapitalPoolAddress,
		uint _amountUnderlying
	) internal returns(uint wrappedDeposit, uint dynamicDeposit) {
		IWrapper wrp = IFixCapitalPool(_fixCapitalPoolAddress).wrapper();
		IERC20 underlying = IERC20(IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress());
		underlying.safeTransferFrom(msg.sender, address(this), _amountUnderlying);
		underlying.safeApprove(address(wrp), _amountUnderlying);
		if (wrp.underlyingIsStatic()) {
			dynamicDeposit = wrp.depositWrappedAmount(address(this), _amountUnderlying);
			wrappedDeposit = _amountUnderlying;
		}
		else {
			wrappedDeposit = wrp.depositUnitAmount(address(this), _amountUnderlying);
			dynamicDeposit = _amountUnderlying;
		}
		IERC20(address(wrp)).safeApprove(_fixCapitalPoolAddress, wrappedDeposit);
		IFixCapitalPool(_fixCapitalPoolAddress).depositWrappedToken(_depositTo, wrappedDeposit);
	}

	/*
		@Description: deposit underlying into wrapper then into FCP, send ZCB & YT back to msg.sender without making any swaps

		@param address _fixCapitalPoolAddress: the address of the FCP contract to deposit into
		@param uint _amountUnderlying: the amount of the underlying ERC20 to deposit

		@return uint wrappedDeposit: the static / wrapped amount of the deposit into the wrapper and subsequently the FCP
		@return uint dynamicDeposit: the dynamic / unit amount of the deposit into the wrapper and subsequently the FCP
	*/
	function FastDepositUnderlying(address _fixCapitalPoolAddress, uint _amountUnderlying) external override returns(uint wrappedDeposit, uint dynamicDeposit) {
		(wrappedDeposit, dynamicDeposit) = internalFastDepositUnderlying(msg.sender, _fixCapitalPoolAddress, _amountUnderlying);
	}

	/*
		@Description: turn underlying asset into ZCB
			deposit underlying into wrapper contract then FCP then swap to ZCB
	
		@param address _fixCapitalPoolAddress: address of the FCP of the ZCB which to swap to
		@param uint _amountUnderlying: the amount of the underlying ERC20 to deposit
		@param uint _minMaturityConversionRate: the minimum MCR of the head order to continue purchasing more ZCB
		@param uint _minCumulativeMaturityConversionRate: if this is greater than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations

		@return uint yield: the yield amount of the ZCB-YT position transferred to msg.sender at the end of execution
		@return int bond: the bond amount of the ZCB-YT position transferred to msg.sender at the end of execution
	*/
	function UnderlyingToZCB(
		address _fixCapitalPoolAddress,
		uint _amountUnderlying,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations
	) external override returns(uint yield, int bond) {
		(uint wrappedDeposit, ) = internalFastDepositUnderlying(address(this), _fixCapitalPoolAddress, _amountUnderlying);
		IOrderbookExchange ob = IOrderbookExchange(org.Orderbooks(_fixCapitalPoolAddress));
		ob.marketSellYT(wrappedDeposit.sub(bufferAmount), _minMaturityConversionRate, _minCumulativeMaturityConversionRate, _maxIterations, false);
		yield = IFixCapitalPool(_fixCapitalPoolAddress).balanceYield(address(this));
		bond = IFixCapitalPool(_fixCapitalPoolAddress).balanceBonds(address(this));
		IFixCapitalPool(_fixCapitalPoolAddress).transferPosition(msg.sender, yield, bond);
	}

	/*
		@Description: turn underlying asset into YT
			deposit underlying into wrapper contract then FCP then swap to YT

		@param address _fixCapitalPoolAddress: address of the FCP of the YT which to swap to
		@param uint _amountUnderlying: the amount of the underlying ERC20 to deposit
		@param uint _maxMaturityConversionRate: the maximum MCR of the head order to continue selling more ZCB
		@param uint _maxCumulativeMaturityConversionRate: if this is smaller than the effective MCR based on ZCB in and YT out at end of execution revert
		@param uint16 _maxIterations: the maximum amount of limit orders to fully fill, important for gas considerations

		@return uint yield: the yield amount of the ZCB-YT position transferred to msg.sender at the end of execution
		@return int bond: the bond amount of the ZCB-YT position transferred to msg.sender at the end of execution
	*/
	function UnderlyingToYT(
		address _fixCapitalPoolAddress,
		uint _amountUnderlying,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations
	) external override returns(uint yield, int bond) {
		( , uint dynamicDeposit) = internalFastDepositUnderlying(address(this), _fixCapitalPoolAddress, _amountUnderlying);
		IOrderbookExchange ob = IOrderbookExchange(org.Orderbooks(_fixCapitalPoolAddress));
		ob.marketSellZCB(dynamicDeposit.sub(bufferAmount), _maxMaturityConversionRate, _maxCumulativeMaturityConversionRate, _maxIterations, false);
		yield = IFixCapitalPool(_fixCapitalPoolAddress).balanceYield(address(this));
		bond = IFixCapitalPool(_fixCapitalPoolAddress).balanceBonds(address(this));
		IFixCapitalPool(_fixCapitalPoolAddress).transferPosition(msg.sender, yield, bond);
	}

}