// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "./NGBwrapperDelegateParent.sol";

contract NGBwrapperDelegate2 is NGBwrapperDelegateParent {
	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;


    function editSubAccountPosition(
        address _subAcct,
        address _FCPaddr,
        int changeYield,
        int changeBond
    ) external claimRewards(true, (_FCPaddr == address(0) ? msg.sender : _FCPaddr)) {
        require(msg.sender != _FCPaddr); //must not be an FCP direct subaccount
        //msg.sender is the distributionAccount
        if (_FCPaddr != address(0)) {
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

    function forceClaimSubAccountRewards(
        address _distributionAccount,
        address _subAccount,
        address _FCPaddr
    ) external claimRewards(true, _distributionAccount) {
        require(msg.sender == _distributionAccount || msg.sender == _subAccount);
        claimSubAccountRewardsRetPos(_distributionAccount, _subAccount, _FCPaddr);
    }

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
        i format:
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
            if (i & (1 << 14) > 0) {
                //collect all YT associated rewards
                uint TRPY = IFixCapitalPool(_FCPaddr).TotalRewardsPerWassetAtMaturity(uint8(i));
                if (prevTotalRewardsPerClaim < TRPY) {
                    dividend = (TRPY - prevTotalRewardsPerClaim).mul(_yield) / (1 ether);
                }
                prevTotalRewardsPerClaim = TRPY;
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
                    uint totalUnspentDARewards = internalTotalUnspentDistributionAccountRewards[uint8(i)].sub(dividend);
                    internalTotalUnspentDistributionAccountRewards[uint8(i)] = totalUnspentDARewards;
                    bool success = IERC20(_rewardsAddr).transfer(_subAcct, dividend);
                    require(success);
                    internalPrevContractBalance[uint8(i)] = IERC20(_rewardsAddr).balanceOf(address(this)).sub(totalUnspentDARewards);
                }
            }
        }
        if (i & (1 << 14) > 0) {
            internalHasClaimedAllYTrewards[_distributionAcct][_subAcct][_FCPaddr] = true;
        }
    }

}