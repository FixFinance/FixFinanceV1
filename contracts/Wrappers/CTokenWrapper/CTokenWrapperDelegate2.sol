// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "../../libraries/SafeERC20.sol";
import "./CTokenWrapperDelegateParent.sol";

contract CTokenWrapperDelegate2 is CTokenWrapperDelegateParent {
	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;
    using SafeERC20 for IERC20;

    /*
        @Description: change the amount of bond and yield in a subaccount

        @param address _claimRewards: pass true to enter the claimRewards modifier
            for either msg.sender or the _FCPaddr, depending on if _FCPaddr == address(0)
        @param address _subAccount: the sub account owner address, receives rewards
        @param address _FCPaddr: the address of the FCP for which sub account balances are held
        @param int _changeYield: change in the yield amount in the sub account,
            final amount - initial amount
        @param int _changeBond: the change in the bond amount for the sub account,
            final amount - initial amount
    */
    function editSubAccountPosition(
        bool _claimRewards,
        address _subAcct,
        address _FCPaddr,
        int changeYield,
        int changeBond
    ) external claimRewards(_claimRewards, (_FCPaddr == address(0) ? msg.sender : _FCPaddr)) {
        require(msg.sender != _FCPaddr); //must not be an FCP direct subaccount
        //msg.sender is the distributionAccount
        if (_FCPaddr != address(0) && _claimRewards) {
            claimSubAccountRewardsRetPos(_FCPaddr, msg.sender, _FCPaddr);
        }
        SubAccountPosition memory mPos = claimSubAccountRewardsRetPos(msg.sender, _subAcct, _FCPaddr);
        SubAccountPosition storage sPos = internalSubAccountPositions[msg.sender][_subAcct][_FCPaddr];

        if (changeYield > 0) {
            sPos.yield = mPos.yield.add(uint(changeYield));
        }
        else if (changeYield < 0) {
            sPos.yield = mPos.yield.sub(uint(changeYield.abs()));
        }

        if (changeBond != 0) {
            sPos.bond = mPos.bond.add(changeBond);
        }
    }

    /*
        @Description: force rewards for a sub account to be distributed

        @param bool _claimRewards: pass true to enter the claimRewards modifier for the distribution account
        @param address _distributionAccount: the address of the distribution account for the sub account
        @param address _subAccount: the address that is the owner of the sub account and shall receive the rewards
        @param address _FCPaddr: the address of the FCP contract for which the sub account amounts are denominated
    */
    function forceClaimSubAccountRewards(
        bool _claimRewards,
        address _distributionAccount,
        address _subAccount,
        address _FCPaddr
    ) external claimRewards(_claimRewards, _distributionAccount) {
        require(msg.sender == _distributionAccount || msg.sender == _subAccount);
        claimSubAccountRewardsRetPos(_distributionAccount, _subAccount, _FCPaddr);
    }

    /*
        @Description: force rewards for an FCP direct sub account to be claimed
            only callable by FCP contracts

        @param bool _inPayoutPhase: true if the FCP is in the payout phase
        @param bool _claimRewards: true if the FCP should claim its rewards
        @param address _subAcct: the owner of the FCP Direct sub account for which to claim rewards
        @param uint _yield: the yield amount in the ZCB & YT position of _subAcct
        @param uint _wrappedClaim: the effective amount of the wrapper asset used to calculate the
            distribution of rewards to _subAcct
    */
    function FCPDirectClaimSubAccountRewards(
        bool _inPayoutPhase,
        bool _claimRewards,
        address _subAcct,
        uint _yield,
        uint _wrappedClaim
    ) external claimRewards(_claimRewards, msg.sender) {
        uint len = internalRewardsAssets.length;
        if (len > 0) {
            len = len > type(uint8).max ? type(uint8).max : len;
            uint16 flags = (_inPayoutPhase ? 1 << 15 : 0) |
                (_inPayoutPhase && !internalHasClaimedAllYTrewards[msg.sender][_subAcct][msg.sender] ? 1 << 14 : 0) |
                (internalIsDistributionAccount[_subAcct] ? 1 << 13 : 0);
            subaccountDistributeRewards(uint8(len), msg.sender, _subAcct, msg.sender, _yield, _wrappedClaim, flags);
        }
    }

    /*
        @Description: claim rewareds for a sub account

        @param address _distributionAccount: the distribution account
        @param address _subAcct: the address that shall receive rewards from the sub account
        @param address _FCPaddr: the base FCP address of the sub account,
            if _FCPaddr is address(0) that means there is no base FCP,
            there are only wrapped asset deposits in the sub account,
            ie the sub account bond amount will always be 0
    */
    function claimSubAccountRewardsRetPos(
        address _distributionAcct,
        address _subAcct,
        address _FCPaddr
    ) internal returns(SubAccountPosition memory mPos) {
        if(_distributionAcct != _FCPaddr) {
            mPos = internalSubAccountPositions[_distributionAcct][_subAcct][_FCPaddr];
        }
        uint len = internalRewardsAssets.length;
        if (len > 0) {
            len = len > type(uint8).max ? type(uint8).max : len;
            if (_distributionAcct == _FCPaddr) {
                mPos.yield = IFixCapitalPool(_FCPaddr).balanceYield(_subAcct);
            }
            if (_FCPaddr == address(0)) {
                uint16 flags = internalIsDistributionAccount[_subAcct] ? 1 << 13 : 0;
                subaccountDistributeRewards(uint8(len), _distributionAcct, _subAcct, _FCPaddr, mPos.yield, mPos.yield, flags);
            }
            else {
                bool inPayoutPhase = IFixCapitalPool(_FCPaddr).inPayoutPhase();
                uint16 flags = (inPayoutPhase ? 1 << 15 : 0) |
                    (inPayoutPhase && !internalHasClaimedAllYTrewards[_distributionAcct][_subAcct][_FCPaddr] ? 1 << 14 : 0) |
                    (internalIsDistributionAccount[_subAcct] ? 1 << 13 : 0);
                if (inPayoutPhase) {
                    if (_distributionAcct == _FCPaddr) {
                        mPos.bond = IFixCapitalPool(_FCPaddr).balanceBonds(_subAcct);
                    }
                    uint maturityConversionRate = IFixCapitalPool(_FCPaddr).maturityConversionRate();
                    require(maturityConversionRate > 0); //prevent div by 0
                    uint wrappedZCBConvValue;
                    if (mPos.bond >= 0) {
                        uint wrappedValueBond = uint(mPos.bond).mul(1 ether) / maturityConversionRate;
                        wrappedZCBConvValue = mPos.yield.add(wrappedValueBond);
                    }
                    else {
                        uint wrappedValueBond = uint(mPos.bond.abs()).mul(1 ether);
                        wrappedValueBond = (wrappedValueBond/maturityConversionRate) + (wrappedValueBond%maturityConversionRate == 0 ? 0 : 1);
                        wrappedZCBConvValue = mPos.yield.sub(wrappedValueBond);
                    }
                    subaccountDistributeRewards(uint8(len), _distributionAcct, _subAcct, _FCPaddr, mPos.yield, wrappedZCBConvValue, flags);
                }
                else {
                    subaccountDistributeRewards(uint8(len), _distributionAcct, _subAcct, _FCPaddr, mPos.yield, mPos.yield, flags);
                }
            }
        }
    }

    /*
        @Description: distribute rewards generated by a subaccount

        @param uint8 _len: the number of rewards assets to distribute rewards for
        @param address _distributionAcct: the distribution account of the sub account
        @param address _subAcct: the address that shall receive rewards from the sub account
        @param address _FCPaddr: the base FCP address of the sub account,
            if _FCPaddr is address(0) that means there is no base FCP,
            there are only wrapped asset deposits in the sub account,
            ie the sub account bond amount will always be 0
        @param uint _yield: the yield amount of the sub account
        @param uint _balanceAddr: the effective amount of wrapped asset in rewards claim weileded by the sub account
            if _FCPaddr is address(0) or the FCP is not yet in payout phase this will be equal to _yield
        @param uint i: format:
            i & (1 << 15) > 0 == inPayoutPhase
            i & (1 << 14) > 0 == subAcct0 get YT & ZCB rewards
            i & (1 << 13) > 0 == subAcct0 is distribution account
            uint8(i) == current index in rewards assets array
    */
    function subaccountDistributeRewards(
        uint8 _len,
        address _distributionAcct,
        address _subAcct,
        address _FCPaddr,
        uint _yield,
        uint _balanceAddr,
        uint16 i
    ) internal {
        for (; uint8(i) < _len; i++) {
            address _rewardsAddr = internalRewardsAssets[uint8(i)];
            if (_rewardsAddr == address(0)) {
                continue;
            }
            uint newTRPC = internalTotalRewardsPerWasset[uint8(i)];
            uint dividend;
            uint prevTotalRewardsPerClaim = internalSAPTRPW[uint8(i)][_distributionAcct][_subAcct][_FCPaddr];
            uint activationTRPW = internalTRPWuponActivation[uint8(i)];
            prevTotalRewardsPerClaim = prevTotalRewardsPerClaim > activationTRPW ? prevTotalRewardsPerClaim : activationTRPW;
            if (i & (1 << 14) > 0) {
                //collect all YT associated rewards
                uint TRPY = IFixCapitalPool(_FCPaddr).TotalRewardsPerWassetAtMaturity(uint8(i));
                if (activationTRPW < TRPY) {
                    if (prevTotalRewardsPerClaim < TRPY) {
                        dividend = (TRPY - prevTotalRewardsPerClaim).mul(_yield) / (1 ether);
                    }
                    prevTotalRewardsPerClaim = TRPY;
                }
            }

            if (prevTotalRewardsPerClaim < newTRPC) {
                dividend = dividend.add((newTRPC - prevTotalRewardsPerClaim).mul(_balanceAddr) / (1 ether));
                internalSAPTRPW[uint8(i)][_distributionAcct][_subAcct][_FCPaddr] = newTRPC;
            }
            else if (i & (1 << 14) > 0) {
                internalSAPTRPW[uint8(i)][_distributionAcct][_subAcct][_FCPaddr] = prevTotalRewardsPerClaim;
            }

            if (dividend > 1) {
                dividend--; //sub 1 from dividend to prevent rounding errors resulting in dist acct insolvency by small amounts
                internalDistributionAccountRewards[uint8(i)][_distributionAcct] = internalDistributionAccountRewards[uint8(i)][_distributionAcct].sub(dividend);
                if (i & (1 << 13) > 0) {
                    internalDistributionAccountRewards[uint8(i)][_subAcct] = internalDistributionAccountRewards[uint8(i)][_subAcct].add(dividend);
                }
                else {
                    IERC20(_rewardsAddr).safeTransfer(_subAcct, dividend);
                    internalPrevContractBalance[uint8(i)] = IERC20(_rewardsAddr).balanceOf(address(this));
                }
            }
        }
        if (i & (1 << 14) > 0) {
            internalHasClaimedAllYTrewards[_distributionAcct][_subAcct][_FCPaddr] = true;
        }
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external noReentry claimRewards(true, address(receiver)) returns (bool) {
        require(token == address(this));
        require(amount + internalTotalSupply <= uint256(-1));
        uint _flashLoanFee = internalFlashLoanFee;
        require(amount <= (uint256(-1) - internalTotalSupply).div(_flashLoanFee.add(totalSBPS)));
        uint fee = amount.mul(_flashLoanFee) / totalSBPS;        
        address recAddr = address(receiver);
        internalBalanceOf[recAddr] = internalBalanceOf[recAddr].add(amount);
        emit FlashMint(recAddr, amount);
        uint256 _allowance = internalAllowance[recAddr][address(this)];
        uint toRepay = amount.add(fee);
        require(
            _allowance >= toRepay,
            "FlashMinter: Repay not approved"
        );
        internalAllowance[recAddr][address(this)] = _allowance.sub(toRepay);
        address copyToken = token;
        uint copyAmount = amount;
        bytes memory copyData = data;
        bytes32 out = IERC3156FlashBorrower(recAddr).onFlashLoan(msg.sender, copyToken, copyAmount, fee, copyData);
        require(CALLBACK_SUCCESS == out);
        uint balance = internalBalanceOf[recAddr];
        require(balance >= toRepay);
        internalBalanceOf[recAddr] = balance.sub(toRepay);
        emit FlashBurn(recAddr, toRepay, fee);
        /*
            the flashloan fee is burned, thus we must decrement the total supply by the fee amount
            this distributes the fee among all wrapped asset holders
        */
        internalTotalSupply = internalTotalSupply.sub(fee);
        return true;
    }

}