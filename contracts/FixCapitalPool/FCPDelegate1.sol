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
import "../libraries/SafeERC20.sol";
import "./FCPDelegateParent.sol";

contract FCPDelegate1 is FCPDelegateParent {
	using SafeERC20 for IERC20;

	event BalanceUpdate(
		address indexed owner,
		uint newYield,
		int newBond
	);
	event BondBalanceUpdate(
		address indexed owner,
		int newBond
	);
	event ClaimPayout(
		address indexed owner
	);
	event Deposit(
		address indexed to,
		uint wrappedAmountDeposited
	);
	event Withdrawal(
		address indexed from,
		uint wrappedAmountWithdrawn
	);

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

		delete internalBalanceYield[msg.sender];
		delete internalBalanceBonds[msg.sender];

		wrp.FCPDirectClaimSubAccountRewards(true, true, msg.sender, yield, payout);
		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, payout, false);
		else
			IERC20(address(wrp)).safeTransfer(_to, payout);

		emit ClaimPayout(msg.sender);
	}

	/*
		@Description: transfer a ZCB + YT position to another address

		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the internalBalanceYield mapping
		@param int _bond: the amount change in the internalBalanceBonds mapping
	*/
	function transferPosition(address _to, uint _yield, int _bond) external {
		require(_to != msg.sender);
		//ensure position has positive minimum value at internalMaturity
		IWrapper wrp = internalWrapper; //gas savings
		bool _inPayoutPhase = internalInPayoutPhase; //gas savings
		uint ratio = _inPayoutPhase ? internalMaturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		require(isValidPosition(_yield, _bond, ratio));

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

		require(isValidPosition(prevYields[0].sub(_yield), bondSender.sub(_bond), ratio));

		uint newYield0 = prevYields[0].sub(_yield);
		int newBond0 = bondSender.sub(_bond);
		internalBalanceYield[msg.sender] = newYield0;
		internalBalanceBonds[msg.sender] = newBond0;

		address copyTo = _to; // prevent stack too deep
		uint newYield1 = prevYields[1].add(_yield);
		int newBond1 = bondRec.add(_bond);
		internalBalanceYield[copyTo] = newYield1;
		internalBalanceBonds[copyTo] = newBond1;

		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, prevYields, wrappedClaims);

		emit BalanceUpdate(msg.sender, newYield0, newBond0);
		emit BalanceUpdate(copyTo, newYield1, newBond1);
	}

	/*
		@Description: transfer a ZCB + YT position from one address to another address

		@param address _from: the address that shall send the position
		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the internalBalanceYield mapping
		@param int _bond: the amount change in the internalBalanceBonds mapping
	*/
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external {
		require(_from != _to);
		IWrapper wrp = internalWrapper;
		bool _inPayoutPhase = internalInPayoutPhase;//gas savings
		uint[2] memory yieldArr = [internalBalanceYield[_from], internalBalanceYield[_to]];
		int[2] memory bondArr = [internalBalanceBonds[_from], internalBalanceBonds[_to]];
		uint ratio = _inPayoutPhase ? internalMaturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		address[2] memory subAccts = [_from, _to];

		require(isValidPosition(_yield, _bond, ratio));

		if (_yield > 0) {
			//decrement approval of YT
			IYieldToken(internalYieldTokenAddress).decrementAllowance(_from, msg.sender, _yield);
			yieldArr[0] = yieldArr[0].sub(_yield);
			yieldArr[1] = yieldArr[1].add(_yield);
			internalBalanceYield[_from] = yieldArr[0];
			internalBalanceYield[_to] = yieldArr[1];
		}

		uint unitAmtYield = _yield.mul(ratio)/(1 ether);
		//decrement approval of ZCB
		uint unitAmtZCB = _bond > 0 ? unitAmtYield.add(uint(_bond)) : unitAmtYield.sub(uint(_bond.abs()));
		IZeroCouponBond(internalZeroCouponBondAddress).decrementAllowance(_from, msg.sender, unitAmtZCB);
		if (_bond != 0) {
			bondArr[0] = bondArr[0].sub(_bond);
			bondArr[1] = bondArr[1].add(_bond);
			internalBalanceBonds[_from] = bondArr[0];
			internalBalanceBonds[_to] = bondArr[1];
		}

		require(isValidPosition(yieldArr[0], bondArr[0], ratio));

		{
			uint[2] memory oldYieldArr = [yieldArr[0].add(_yield), yieldArr[1].sub(_yield)];
			uint[2] memory wrappedClaims = _inPayoutPhase ? 
				[payoutAmount(oldYieldArr[0], bondArr[0].add(_bond), ratio), payoutAmount(oldYieldArr[1], bondArr[1].sub(_bond), ratio)]
				: oldYieldArr;
			wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, oldYieldArr, wrappedClaims);
		}

		if (_yield != 0 || _bond != 0) {
			emit BalanceUpdate(_from, yieldArr[0], bondArr[0]);
			emit BalanceUpdate(_to, yieldArr[1], bondArr[1]);
		}
	}

	/*
		@Description: zero coupon bond contract must call this function to transfer zcb between addresses

		@param address _from: the address to deduct ZCB from
		@param address _to: the address to send 
	*/
	function transferZCB(address _from, address _to, uint _amount) external {
		require(_from != _to);
		bool _inPayoutPhase = internalInPayoutPhase; //gas savings
		uint conversionRate = _inPayoutPhase ? internalMaturityConversionRate : internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		int[2] memory prevBonds = [internalBalanceBonds[_from], internalBalanceBonds[_to]];

		if (msg.sender != _from && msg.sender != internalZeroCouponBondAddress) {
			IZeroCouponBond(internalZeroCouponBondAddress).decrementAllowance(_from, msg.sender, _amount);
		}
		int intAmount = _amount.toInt();
		require(intAmount >= 0);
		int newFromBond = internalBalanceBonds[_from].sub(intAmount);

		require(isValidPosition(internalBalanceYield[_from], newFromBond, conversionRate));

		internalBalanceBonds[_from] = newFromBond;
		int newBondTo = internalBalanceBonds[_to].add(intAmount);
		internalBalanceBonds[_to] = newBondTo;

		if (_inPayoutPhase) {
			address[2] memory subAccts = [_from, _to];
			uint[2] memory prevYields = [internalBalanceYield[_from], internalBalanceYield[_to]];
			uint[2] memory wrappedClaims = [payoutAmount(prevYields[0], prevBonds[0], conversionRate), payoutAmount(prevYields[1], prevBonds[1], conversionRate)];
			internalWrapper.FCPDirectDoubleClaimSubAccountRewards(true, true, subAccts, prevYields, wrappedClaims);
		}

		emit BondBalanceUpdate(_from, newFromBond);
		emit BondBalanceUpdate(_to, newBondTo);
	}

	/*
		@Description: yield token contract must call this function to move yield token between addresses

		@param address _from: the address to deduct YT from
		@param address _to: the address to credit YT to
		@param uint _amount: the amount of YT to move between _from and _to
			*denominated in wrapped asset*
	*/
	function transferYT(address _from, address _to, uint _amount) external {
		require(_from != _to);
		IWrapper wrp = internalWrapper;
		bool _inPayoutPhase = internalInPayoutPhase; //gas savings
		if (msg.sender != _from && msg.sender != internalYieldTokenAddress) {
			IYieldToken(internalYieldTokenAddress).decrementAllowance(_from, msg.sender, _amount);
		}
		uint conversionRate = _inPayoutPhase ? internalMaturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		int[2] memory bondArr = [internalBalanceBonds[_from], internalBalanceBonds[_to]];
		address[2] memory subAccts = [_from, _to];
		uint[2] memory yieldArr = [internalBalanceYield[_from], internalBalanceYield[_to]];
		uint[2] memory wrappedClaims = _inPayoutPhase ? 
			[payoutAmount(yieldArr[0], bondArr[0], conversionRate), payoutAmount(yieldArr[1], bondArr[1], conversionRate)]
			: yieldArr;

		int amountBondChange = int(_amount.mul(conversionRate) / (1 ether)); //can be casted to int without worry bc '/ (1 ether)' ensures it fits

		require(isValidPosition(yieldArr[0].sub(_amount), bondArr[0].add(amountBondChange), conversionRate));

		internalBalanceYield[_from] = yieldArr[0].sub(_amount);
		internalBalanceBonds[_from] = bondArr[0].add(amountBondChange);
		internalBalanceYield[_to] = yieldArr[1].add(_amount);
		internalBalanceBonds[_to] = bondArr[1].sub(amountBondChange);

		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, yieldArr, wrappedClaims);

		yieldArr[0] = yieldArr[0].sub(_amount);
		yieldArr[1] = yieldArr[1].add(_amount);
		bondArr[0] = bondArr[0].add(amountBondChange);
		bondArr[1] = bondArr[1].sub(amountBondChange);

		emit BalanceUpdate(_from, yieldArr[0], bondArr[0]);
		emit BalanceUpdate(_to, yieldArr[1], bondArr[1]);
	}

}