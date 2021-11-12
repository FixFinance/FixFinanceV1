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

contract FCPDelegate2 is FCPDelegateParent {
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
		@Description: send wrapped asest to this fix capital pool, receive ZCB & YT

		@param address _to: the address that shall receive the ZCB and YT
		@param uint _amountWrappedTkn: the amount of wrapped asset to deposit
	*/
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external beforePayoutPhase {
		IWrapper wrp = internalWrapper;
		uint yield = internalBalanceYield[_to];
		internalBalanceYield[_to] = yield.add(_amountWrappedTkn);
		IERC20(address(wrp)).safeTransferFrom(msg.sender, address(this), _amountWrappedTkn);
		wrp.FCPDirectClaimSubAccountRewards(false, false, _to, yield, yield);
		emit Deposit(_to, _amountWrappedTkn);
	}

	/*
		@Description: return ZCB & YT and receive wrapped asset

		@param address _to: the address that shall receive the output
		@param uint _amountWrappedTkn: the amount of wrapped asset to withdraw
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external beforePayoutPhase {
		IWrapper wrp = internalWrapper;
		uint yield = internalBalanceYield[msg.sender];
		int bond = internalBalanceBonds[msg.sender];
		//conversionRate doesn't matter if bond >= 0, save gas if we can by not fetching the conv rate
		uint conversionRate = bond < 0 ? wrp.WrappedAmtToUnitAmt_RoundDown(1 ether) : 0;
		require(maxWrappedWithdrawAmt(yield, bond, conversionRate) >= _amountWrappedTkn);

		wrp.FCPDirectClaimSubAccountRewards(false, false, msg.sender, yield, yield);
		internalBalanceYield[msg.sender] = yield.sub(_amountWrappedTkn);

		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, _amountWrappedTkn, true);
		else
			IERC20(address(wrp)).safeTransfer(_to, _amountWrappedTkn);

		emit Withdrawal(msg.sender, _amountWrappedTkn);
	}


	/*
		@Description: return Min(balanceZCB, balanceYT) of both ZCB & YT and receive the corresponding
			amount of wrapped asset.
			Essentially this function is like withdraw except it always withdraws as much as possible

		@param address _to: the address that shall receive the output
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdrawAll(address _to, bool _unwrap) external beforePayoutPhase {
		IWrapper wrp = internalWrapper;
		uint yield = internalBalanceYield[msg.sender];
		int bond = internalBalanceBonds[msg.sender];
		//conversionRate doesn't matter if bond >= 0, save gas if we can by not fetching the conv rate
		uint conversionRate = bond < 0 ? wrp.WrappedAmtToUnitAmt_RoundDown(1 ether) : 0;
		uint freeToMove = maxWrappedWithdrawAmt(yield, bond, conversionRate);

		wrp.FCPDirectClaimSubAccountRewards(false, false, msg.sender, yield, yield);
		internalBalanceYield[msg.sender] = yield.sub(freeToMove);

		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, freeToMove, true);
		else
			IERC20(address(wrp)).safeTransfer(_to, freeToMove);

		emit Withdrawal(msg.sender, freeToMove);
	}

	/*
		@Description: after maturity call this funtion to send into payout phase
	*/
	function enterPayoutPhase() external {
		require(!internalInPayoutPhase && block.timestamp >= internalMaturity);
		internalInPayoutPhase = true;
		internalMaturityConversionRate = internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint len = internalWrapper.numRewardsAssets();
		len = len > type(uint8).max ? type(uint8).max : len;
		IWrapper wrp = internalWrapper;
		for (uint8 i = 0; i < len; i++) {
			internalTotalRewardsPerWassetAtMaturity.push(wrp.totalRewardsPerWasset(i));
		}
	}

    /*
		@Description: VaultFactory contract may mint new ZCB against collateral, to mint new ZCB the VaultFactory
			calls this function
	
		@param address _owner: address to credit new ZCB to
		@param uint _amount: amount of ZCB to credit to _owner
    */
	function mintZCBTo(address _owner, uint _amount) external {
		require(internalWhitelistedVaultFactories[msg.sender]);
		if (internalInPayoutPhase) {
			uint yield = internalBalanceYield[_owner];
			int bond = internalBalanceBonds[_owner];
			uint payout = payoutAmount(yield, bond, internalMaturityConversionRate);
			internalWrapper.FCPDirectClaimSubAccountRewards(true, true, _owner, yield, payout);
		}
		int newBond = internalBalanceBonds[_owner].add(_amount.toInt());
		internalBalanceBonds[_owner] = newBond;
		emit BondBalanceUpdate(_owner, newBond);
	}

	/*
		@Description: when margin position is closed/liquidated VaultFactory contract calls this function to
			remove ZCB from circulation

		@param address _owner: address to take ZCB from
		@param uint _amount: the amount of ZCB to remove from cirulation		
	*/
	function burnZCBFrom(address _owner, uint _amount) external {
		require(internalWhitelistedVaultFactories[msg.sender]);
		IWrapper wrp = internalWrapper;
		bool _inPayoutPhase = internalInPayoutPhase;
		uint yield = internalBalanceYield[_owner];
		int bond = internalBalanceBonds[_owner];
		uint conversionRate = _inPayoutPhase ? internalMaturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		require(minimumUnitAmountAtMaturity(yield, bond, conversionRate) >= _amount);
		if (_inPayoutPhase) {
			uint payout = payoutAmount(yield, bond, internalMaturityConversionRate);
			internalWrapper.FCPDirectClaimSubAccountRewards(true, true, _owner, yield, payout);
		}
		int newBond = internalBalanceBonds[_owner].sub(_amount.toInt());
		internalBalanceBonds[_owner] = newBond;
		emit BondBalanceUpdate(_owner, newBond);
	}

	/*
		@Description: initiate flashloan

		@param IFCPFlashBorrower: the contract that shall borrow the funds
		@param uint256 _amountYield: the amount of yield to flashborrow
		@param int256 _amountBond: the amount of bond to flashborrow
		@param bytes calldata _data: the data to pass to the flash borrow receiver

		@return bool: true when flashloan is successful
    */
    function flashLoan(
        IFCPFlashBorrower _receiver,
        uint256 _amountYield,
        int256 _amountBond,
        bytes calldata _data
    ) external beforePayoutPhase noReentry returns (bool) {
		require(_amountYield <= MAX_YIELD_FLASHLOAN);
		require(_amountBond <= MAX_BOND_FLASHLOAN);
		uint ratio;
		uint _flashLoanFee = flashLoanFee;
		uint yieldFee;
		int bondFee;
		{
			address recAddr = address(_receiver);
			uint copyAmtYield = _amountYield;
			int copyAmtBond = _amountBond;
			uint prevYield = internalBalanceYield[recAddr];
			IWrapper wrp = internalWrapper;
			wrp.FCPDirectClaimSubAccountRewards(false, true, recAddr, prevYield, prevYield);
			ratio = wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);

			uint newYield =  prevYield.add(copyAmtYield);
			int newBond = internalBalanceBonds[recAddr].add(copyAmtBond);
			emit BalanceUpdate(recAddr, newYield, newBond);
			if (copyAmtYield > 0) {
				yieldFee = copyAmtYield.mul(_flashLoanFee) / totalSBPS;
				internalBalanceYield[recAddr] = newYield;
			}
			if (copyAmtBond != 0) {
				bondFee = copyAmtBond.mul(_flashLoanFee.toInt()) / int(totalSBPS);
				internalBalanceBonds[recAddr] = newBond;
			}
		}
		uint effectiveZCB = _amountYield.mul(ratio) / (1 ether);
		if (_amountBond >= 0) {
			effectiveZCB = effectiveZCB.add(_amountBond.toUint());
		}
		else {
			effectiveZCB = effectiveZCB.sub(_amountBond.mul(-1).toUint());
		}

		bytes32 out = _receiver.onFlashLoan(msg.sender, _amountYield, _amountBond, yieldFee, bondFee, _data);
		require(out == CALLBACK_SUCCESS);

		//decrement allowances
		IZeroCouponBond(internalZeroCouponBondAddress).decrementAllowance(address(_receiver), address(this), effectiveZCB);
		IYieldToken(internalYieldTokenAddress).decrementAllowance(address(_receiver), address(this), _amountYield);

		{
			address recAddr = address(_receiver);
			uint copyAmtYield = _amountYield;
			int copyAmtBond = _amountBond;
			uint newYield = internalBalanceYield[recAddr];
			int newBond = internalBalanceBonds[recAddr];
			if (copyAmtYield > 0) {
				newYield = newYield.sub(copyAmtYield).sub(yieldFee);
				internalBalanceYield[recAddr] = newYield;
			}
			if (copyAmtBond != 0) {
				newBond = newBond.sub(copyAmtBond).sub(bondFee);
				internalBalanceBonds[recAddr] = newBond;
			}
			emit BalanceUpdate(recAddr, newYield, newBond);
		}

		address _owner = owner;
		IInfoOracle iorc = IInfoOracle(internalInfoOracleAddress);
		if (iorc.TreasuryFeeIsCollected()) {
			address sendTo = iorc.sendTo();

			uint copyAmtYield = _amountYield;
			int copyAmtBond = _amountBond;

			uint[2] memory yieldArr = [internalBalanceYield[sendTo], internalBalanceYield[_owner]];
			int[2] memory bondArr = [internalBalanceBonds[sendTo], internalBalanceBonds[_owner]];

			if (copyAmtYield > 0) {
				address[2] memory subAccts = [sendTo, _owner];
				//wrappedClaims is same as yield Arr, because this function may only be executed before the payout phase is entered
				internalWrapper.FCPDirectDoubleClaimSubAccountRewards(false, true, subAccts, yieldArr, yieldArr);

				uint dividend = yieldFee >> 1;
				yieldArr[0] = yieldArr[0].add(dividend);
				yieldArr[1] = yieldArr[1].add(yieldFee - dividend);
				internalBalanceYield[subAccts[0]] = yieldArr[0];
				internalBalanceYield[subAccts[1]] = yieldArr[1];
			}
			if (copyAmtBond != 0) {
				int dividend = bondFee / 2;
				bondArr[0] = internalBalanceBonds[sendTo].add(dividend);
				bondArr[1] = internalBalanceBonds[_owner].add(bondFee - dividend);
				internalBalanceBonds[sendTo] = internalBalanceBonds[sendTo];
				internalBalanceBonds[_owner] = internalBalanceBonds[_owner];
			}
			emit BalanceUpdate(sendTo, yieldArr[0], bondArr[0]);
			emit BalanceUpdate(_owner, yieldArr[1], bondArr[1]);
		}
		else {
			if (_amountYield > 0) {
				uint prevYieldOwner = internalBalanceYield[_owner];
				internalWrapper.FCPDirectClaimSubAccountRewards(false, true, _owner, prevYieldOwner, prevYieldOwner);

				internalBalanceYield[_owner] = prevYieldOwner.add(yieldFee);
			}
			if (_amountBond != 0) {
				internalBalanceBonds[_owner] = internalBalanceBonds[_owner].add(bondFee);
			}
		}
	    return true;
    }

}