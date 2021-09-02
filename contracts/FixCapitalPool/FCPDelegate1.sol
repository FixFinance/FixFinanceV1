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
import "./FCPDelegateParent.sol";

contract FCPDelegate1 is FCPDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;

	/*
		@Description: after the internalMaturity call this function to redeem ZCBs at a ratio of 1:1 with the
			underlying asset, pays out in wrapped asset

		@param address _to: the address that shall receive the wrapped asset
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function claimBondPayout(address _to, bool _unwrap) external isInPayoutPhase {
		IWrapper wrp = internalWrapper;
		uint yield = internalBalanceYield[msg.sender];
		int bond = internalBalanceBonds[msg.sender];
		uint payout = payoutAmount(yield, bond, internalMaturityConversionRate);
		wrp.FCPDirectClaimSubAccountRewards(true, true, msg.sender, yield, payout);
		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, payout, false);
		else
			wrp.transfer(_to, payout);
		delete internalBalanceYield[msg.sender];
		delete internalBalanceBonds[msg.sender];
	}

	/*
		@Description: transfer a ZCB + YT position to another address

		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the internalBalanceYield mapping
		@param int _bond: the amount change in the internalBalanceBonds mapping
	*/
	function transferPosition(address _to, uint _yield, int _bond) external {
		//ensure position has positive minimum value at internalMaturity
		IWrapper wrp = internalWrapper; //gas savings
		bool _inPayoutPhase = internalInPayoutPhase; //gas savings
		uint ratio = _inPayoutPhase ? internalMaturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		require(_bond >= 0 || _yield.mul(ratio)/(1 ether) >= uint(-_bond));

		int bondSender = internalBalanceBonds[msg.sender];
		int bondRec = internalBalanceBonds[_to];

		uint[2] memory prevYields = [internalBalanceYield[msg.sender], internalBalanceYield[_to]];
		uint[2] memory wrappedClaims;

		if (_inPayoutPhase) {
			uint mcr = internalMaturityConversionRate;
			wrappedClaims = [payoutAmount(prevYields[0], bondSender, mcr), payoutAmount(prevYields[1], bondRec, mcr)];
		}
		else {
			wrappedClaims = prevYields;
		}
		address[2] memory subAccts = [msg.sender, _to];
		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, prevYields, wrappedClaims);
		require(bondSender >= _bond || prevYields[0].sub(_yield).mul(ratio)/(1 ether) >= uint(bondSender.sub(_bond).abs()));
		internalBalanceYield[msg.sender] = prevYields[0] - _yield;
		internalBalanceBonds[msg.sender] = bondSender - _bond;
		internalBalanceYield[_to] = prevYields[1].add(_yield);
		internalBalanceBonds[_to] = bondRec.add(_bond);
	}

	/*
		@Description: transfer a ZCB + YT position from one address to another address

		@param address _from: the address that shall send the position
		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the internalBalanceYield mapping
		@param int _bond: the amount change in the internalBalanceBonds mapping
	*/
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external {
		IWrapper wrp = internalWrapper;
		bool _inPayoutPhase = internalInPayoutPhase;//gas savings
		uint[2] memory prevYields = [internalBalanceYield[_from], internalBalanceYield[_to]];
		int[2] memory prevBonds = [internalBalanceBonds[_from], internalBalanceBonds[_to]];
		uint ratio = _inPayoutPhase ? internalMaturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint[2] memory wrappedClaims = _inPayoutPhase ? 
			[payoutAmount(prevYields[0], prevBonds[0], ratio), payoutAmount(prevYields[1], prevBonds[1], ratio)]
			: prevYields;
		address[2] memory subAccts = [_from, _to];
		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, prevYields, wrappedClaims);

		require(prevBonds[0] >= _bond || prevYields[0].sub(_yield).mul(ratio)/(1 ether) >= uint(prevBonds[0].sub(_bond).abs()));

		if (_yield > 0) {
			//decrement approval of YT
			IYieldToken(internalYieldTokenAddress).decrementAllowance(_from, msg.sender, _yield);
			internalBalanceYield[_from] = prevYields[0].sub(_yield);
			internalBalanceYield[_to] = prevYields[1].add(_yield);
		}

		uint unitAmtYield = _yield.mul(ratio)/(1 ether);
		require(_bond >= 0 || unitAmtYield >= uint(-_bond));
		//decrement approval of ZCB
		uint unitAmtZCB = _bond > 0 ? unitAmtYield.add(uint(_bond)) : unitAmtYield.sub(uint(_bond.abs()));
		IZeroCouponBond(internalZeroCouponBondAddress).decrementAllowance(_from, msg.sender, unitAmtZCB);
		if (_bond != 0) {
			internalBalanceBonds[_from] = prevBonds[0].sub(_bond);
			internalBalanceBonds[_to] = prevBonds[1].add(_bond);
		}
	}

	/*
		@Description: zero coupon bond contract must call this function to transfer zcb between addresses

		@param address _from: the address to deduct ZCB from
		@param address _to: the address to send 
	*/
	function transferZCB(address _from, address _to, uint _amount) external {
		require(_amount <= uint(type(int256).max));
		uint conversionRate;
		int[2] memory prevBonds = [internalBalanceBonds[_from], internalBalanceBonds[_to]];
		if (internalInPayoutPhase) {
			conversionRate = internalMaturityConversionRate;
			address[2] memory subAccts = [_from, _to];
			uint[2] memory prevYields = [internalBalanceYield[_from], internalBalanceYield[_to]];
			uint[2] memory wrappedClaims = [payoutAmount(prevYields[0], prevBonds[0], conversionRate), payoutAmount(prevYields[1], prevBonds[1], conversionRate)];
			internalWrapper.FCPDirectDoubleClaimSubAccountRewards(true, true, subAccts, prevYields, wrappedClaims);
		}
		else {
			conversionRate = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		}

		if (msg.sender != _from && msg.sender != internalZeroCouponBondAddress) {
			IZeroCouponBond(internalZeroCouponBondAddress).decrementAllowance(_from, msg.sender, _amount);
		}
		int intAmount = int(_amount);
		require(intAmount >= 0);
		int newFromBond = internalBalanceBonds[_from].sub(intAmount);

		//ensure that _from address's position may be cashed out to a positive amount of wrappedToken
		//if it cannot the following call will revert this tx
		minimumUnitAmountAtMaturity(internalBalanceYield[_from], newFromBond, conversionRate);

		internalBalanceBonds[_to] = internalBalanceBonds[_to].add(intAmount);
		internalBalanceBonds[_from] = newFromBond;
	}

}