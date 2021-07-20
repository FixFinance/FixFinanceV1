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
    ) external claimRewards(msg.sender) {
        require(msg.sender != _FCPaddr); //must not be an FCP direct subaccount
        //msg.sender is the distributionAccount
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
    ) external claimRewards(_distributionAccount) {
        require(msg.sender == _distributionAccount || msg.sender == _subAccount);
        claimSubAccountRewardsRetPos(_distributionAccount, _subAccount, _FCPaddr);
    }

    function forceDoubleClaimSubAccountRewards(
        address _subAccount0,
        address _subAccount1
    ) external claimRewards(msg.sender) {
        //msg.sender is distributionAccount & FCP
        claimSubAccountRewardsRetPos(msg.sender, _subAccount0, msg.sender);
        claimSubAccountRewardsRetPos(msg.sender, _subAccount1, msg.sender);
    }

    function claimSubAccountRewardsRetPos(
        address _distributionAcct,
        address _subAcct,
        address _FCPaddr
    ) internal returns(SubAccountPosition memory mPos) {
        if(_distributionAcct != _FCPaddr) {
            mPos = internalSubAccountPositions[_distributionAcct][_subAcct][_FCPaddr];
        }
        else {
            uint yield = IFixCapitalPool(_FCPaddr).balanceYield(_subAcct);
            int bond = IFixCapitalPool(_FCPaddr).balanceBonds(_subAcct);
            mPos = SubAccountPosition(yield, bond);
        }
        uint len = internalRewardsAssets.length;
        if (len > 0) {
            len = len > type(uint8).max ? type(uint8).max : len;
            bool inPayoutPhase = IFixCapitalPool(_FCPaddr).inPayoutPhase();
            uint16 flags = (inPayoutPhase ? 1 << 15 : 0) |
                (inPayoutPhase && !internalHasClaimedAllYTrewards[_distributionAcct][_subAcct][_FCPaddr] ? 1 << 14 : 0) |
                (internalIsDistributionAccount[_subAcct] ? 1 << 13 : 0);
            if (inPayoutPhase) {
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
                subaccountDistributeRewardsPassPos(uint8(len), _distributionAcct, _subAcct, _FCPaddr, mPos, wrappedZCBConvValue, flags);
                mPos.yield = mPos.yield;
                return mPos;
            }
            else {
                subaccountDistributeRewardsPassPos(uint8(len), _distributionAcct, _subAcct, _FCPaddr, mPos, mPos.yield, flags);
            }
        }
    }
/*
    function claimSubAccountRewards(
        address _distributionAcct,
        address _subAcct,
        address _FCPaddr,
    ) internal {
        uint yield = _distributionAcct == _FCPaddr ? IFixCapitalPool(_FCPaddr).balanceYield(_subAcct)
            : internalSubAccountPositions[_distributionAcct][_subAcct][_FCPaddr].yield;
        uint len = internalRewardsAssets.length;
        if (len > 0) {
            len = len > type(uint8).max ? type(uint8).max : len;
            bool inPayoutPhase = IFixCapitalPool(_FCPaddr).inPayoutPhase();
            uint16 flags = (inPayoutPhase ? 1 << 15 : 0) |
                (inPayoutPhase && !internalHasClaimedAllYTrewards[_distributionAcct][_subAcct][_FCPaddr] ? 1 << 14 : 0) |
                (internalIsDistributionAccount[_subAcct] ? 1 << 13 : 0);
            if (inPayoutPhase) {
                uint maturityConversionRate = IFixCapitalPool(_FCPaddr).maturityConversionRate();
                require(maturityConversionRate > 0); //prevent div by 0
                int bond = _distributionAcct == _FCPaddr ? IFixCapitalPool(_FCPaddr).balanceYield(_subAcct)
                    : internalSubAccountPositions[_distributionAcct][_subAcct][_FCPaddr].yield;
                uint wrappedZCBConvValue;
                if (bond >= 0) {
                    uint wrappedValueBond = uint(bond).mul(1 ether) / maturityConversionRate;
                    wrappedZCBConvValue = yield.add(wrappedValueBond);
                }
                else {
                    uint wrappedValueBond = uint(bond.abs()).mul(1 ether);
                    wrappedValueBond = (wrappedValueBond/maturityConversionRate) + (wrappedValueBond%maturityConversionRate == 0 ? 0 : 1);
                    wrappedZCBConvValue = yield.sub(wrappedValueBond);
                }
                subaccountDistributeRewards(uint8(len), _distributionAcct, _subAcct, _FCPaddr, yield, wrappedZCBConvValue, flags);
            }
            else {
                subaccountDistributeRewards(uint8(len), _distributionAcct, _subAcct, _FCPaddr, yield, yield, flags);
            }
        }
    }
*/
    /*
        i format:
            i & (1 << 15) > 0 == inPayoutPhase
            i & (1 << 14) > 0 == subAcct0 get YT & ZCB rewards
            i & (1 << 13) > 0 == subAcct0 is distribution account
            uint8(i) == current index in rewards assets array
    */
    function subaccountDistributeRewardsPassPos(
        uint8 _len,
        address _distributionAcct,
        address _subAcct,
        address _FCPaddr,
        SubAccountPosition memory mPos,
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
                    dividend = (TRPY - prevTotalRewardsPerClaim).mul(mPos.yield) / (1 ether);
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


    /*
        i format:
            i & (1 << 15) > 0 == inPayoutPhase
            i & (1 << 14) > 0 == subAcct0 get YT rewards
            i & (1 << 13) > 0 == subAcct0 is distribution account
            uint8(i) == current index in rewards assets array
    *//*
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
            uint TRPYatMaturity = 
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

            internalDistributionAccountRewards[uint8(i)][_distributionAcct] = internalDistributionAccountRewards[uint8(i)][_distributionAcct].sub(dividend);
            if (i & (1 << 13) > 0) {
                internalDistributionAccountRewards[uint8(i)][_subAcct] = internalDistributionAccountRewards[uint8(i)][_subAcct].add(dividend);
            }
            else {
                internalTotalUnspentDistributionAccountRewards[uint8(i)] = internalTotalUnspentDistributionAccountRewards[uint8(i)].sub(dividend);
                bool success = IERC20(_rewardsAddr).transfer(_subAcct, dividend);
                require(success);
            }
        }
        if (i & (1 << 14) > 0) {
            internalHasClaimedAllYTrewards[_distributionAcct][_subAcct][_FCPaddr] = true;
        }
    }
    */






	//-----------------ERC20-transfer-functionality------------

    function transfer(address _to, uint256 _value) external doubleClaimRewards(_to, msg.sender) {
        require(_value <= internalBalanceOf[msg.sender]);

        internalBalanceOf[msg.sender] -= _value;
        internalBalanceOf[_to] += _value;
    }

    function transferFrom(address _from, address _to, uint256 _value) external doubleClaimRewards(_to, _from) {
        require(_value <= internalAllowance[_from][msg.sender]);
    	require(_value <= internalBalanceOf[_from]);

    	internalBalanceOf[_from] -= _value;
    	internalBalanceOf[_to] += _value;

        internalAllowance[_from][msg.sender] -= _value;
    }

}