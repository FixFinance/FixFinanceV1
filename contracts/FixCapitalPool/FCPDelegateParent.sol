// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IInfoOracle.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "./FCPData.sol";

/*
	Contains all internal functions so that there is no need to have the same function
	written twice in two contracts
*/

contract FCPDelegateParent is FCPData {
	using SafeMath for uint;
	using SignedSafeMath for int;

	modifier beforePayoutPhase() {
		require(!internalInPayoutPhase);
		_;
	}

	modifier isInPayoutPhase() {
		require(internalInPayoutPhase);
		_;
	}

	/*
		@Description: find the amount of the IWrapper asset to payout based on the balance of yield and bond
			assumes that the FCP contract is in the payout phase

		@param uint _yield: the yield amount associated with the ZCB & YT position
		@param int _bond: the bond amount associated with the ZCB & YT position
		@param uint _maturityConversionRate: pass the value of the contract variable 'internalMaturityConversionRate'

		@return uint: the amount of wrapped asset that should be paid out
	*/
	function payoutAmount(uint _yield, int _bond, uint _maturityConversionRate) internal pure returns(uint) {
		require(_maturityConversionRate > 0);
		uint ZCB = _yield.mul(_maturityConversionRate) / (1 ether);
		ZCB = _bond > 0 ? ZCB.add(uint(_bond)) : ZCB.sub(uint(_bond.abs()));
		return ZCB.mul(1 ether) / _maturityConversionRate;
	}

	/*
		@Description: find the amount of Unwrapped Units an address will be able to claim at internalMaturity
			if no yield is generated in the internalWrapper from now up to internalMaturity,
			if in payout phase the value returned will be the unit amount that could be claimed at internalMaturity

		@param uint _yield: the yield amount associated with the ZCB & YT position
		@param int _bond: the bond amount associated with the ZCB & YT position
		@param uint _conversionRate: if before payout phase pass the value of the current conversion rate
			if in payout phase pass the value of the contract 'internalMaturityConversionRate' variable

		@return uint balance: the minimum possible value (denominated in Unit/Unwrapped amount) of _owner's
			position at internalMaturity
	*/
	function minimumUnitAmountAtMaturity(uint _yield, int _bond, uint _conversionRate) internal pure returns (uint balance) {
		require(_conversionRate > 0);
		balance = _yield.mul(_conversionRate) / (1 ether);
		balance = _bond > 0 ? balance.add(uint(_bond)) : balance.sub(uint(_bond.abs()));
	}

	/*
		@Description: find the amount of wrapped token that the user may withdraw from the fix capital pool

		@param uint _yield: the yield amount associated with the ZCB & YT position
		@param int _bond: the bond amount associated with the ZCB & YT position
		@param uint _conversionRate: if before payout phase pass the value of the current conversion rate
			if in payout phase pass the value of the contract 'internalMaturityConversionRate' variable

		@return uint: the maximum wrapped amount of the internalWrapper asset that may be withdrawn
			for the owner of the ZCB & YT position
	*/
	function maxWrappedWithdrawAmt(uint _yield, int _bond, uint _conversionRate) internal pure returns(uint) {
		if (_bond < 0){
			uint unitAmtFree = (_yield.mul(_conversionRate) / (1 ether)).sub(uint(_bond.abs()));
			return unitAmtFree.mul(1 ether) / (_conversionRate);
		}
		else {
			return _yield;
		}
	}

	/*
		@Description: return true if and only if a ZCB-YT position has a non negative balance of ZCB & YT

		@param uint yield: the yield value of the ZCB-YT position
		@param int bond: the bond value of the ZCB-YT position
		@param uint ratio: the conversion multiplier for static to dynamic amounts

		@return bool: true if and only if there is a non negative balance of ZCB & YT
	*/
	function isValidPosition(uint yield, int bond, uint ratio) internal pure returns(bool) {
		return bond >= 0 || yield.mul(ratio) / (1 ether) >= bond.abs().toUint();
	}
}