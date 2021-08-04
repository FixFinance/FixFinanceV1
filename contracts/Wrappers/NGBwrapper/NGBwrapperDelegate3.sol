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

contract NGBwrapperDelegate3 is NGBwrapperDelegateParent {
	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

    function FCPDirectDoubleClaimSubAccountRewards(
        bool _inPayoutPhase,
        bool _claimRewards,
        address[2] calldata _subAccts,
        uint[2] calldata _yieldArr,
        uint[2] calldata _wrappedClaims
    ) external claimRewards(_claimRewards, msg.sender) {
        uint len = internalRewardsAssets.length;
        if (len > 0) {
            len = len > type(uint8).max ? type(uint8).max : len;
            bool copyInPayoutPhase = _inPayoutPhase;
            uint16 flags = (copyInPayoutPhase ? 1 << 15 : 0);
            flags = flags | (copyInPayoutPhase && !internalHasClaimedAllYTrewards[msg.sender][_subAccts[0]][msg.sender] ? 1 << 14 : 0);
            flags = flags | (internalIsDistributionAccount[_subAccts[0]] ? 1 << 13 : 0);
            flags = flags | (copyInPayoutPhase && !internalHasClaimedAllYTrewards[msg.sender][_subAccts[1]][msg.sender] ? 1 << 12 : 0);
            flags = flags | (internalIsDistributionAccount[_subAccts[1]] ? 1 << 11 : 0);
            doubleSubaccountDistributeRewards(uint8(len), msg.sender, _subAccts, _yieldArr, _wrappedClaims, flags);
        }
    }

    /*
        i format:
            i & (1 << 15) > 0 == inPayoutPhase
            i & (1 << 14) > 0 == subAcct0 get YT & ZCB rewards
            i & (1 << 13) > 0 == subAcct0 is distribution account
            i & (1 << 12) > 0 == subAcct1 get YT & ZCB rewards
            i & (1 << 11) > 0 == subAcct1 is distribution account
            uint8(i) == current index in rewards assets array
    */
    function doubleSubaccountDistributeRewards(
        uint8 _len,
        address _FCPaddr,
        address[2] memory _subAccts,
        uint[2] memory _yieldArr,
        uint[2] memory _balanceAddrs,
        uint16 i
    ) internal {
        for (; uint8(i) < _len; i++) {
            address _rewardsAddr = internalRewardsAssets[uint8(i)];
            if (_rewardsAddr == address(0)) {
                continue;
            }
            uint newTRPC = internalTotalRewardsPerWasset[uint8(i)];
            uint TRPY = (i & ((1 << 14) | (1 << 12))) > 0 ? IFixCapitalPool(_FCPaddr).TotalRewardsPerWassetAtMaturity(uint8(i)) : 0;
            uint dividend;
            uint prevTotalRewardsPerClaim = internalSAPTRPW[uint8(i)][_FCPaddr][_subAccts[0]][_FCPaddr];
            if (i & (1 << 14) > 0) {
                //collect all YT associated rewards
                if (prevTotalRewardsPerClaim < TRPY) {
                    dividend = (TRPY - prevTotalRewardsPerClaim).mul(_yieldArr[0]) / (1 ether);
                }
                prevTotalRewardsPerClaim = TRPY;
            }

            if (prevTotalRewardsPerClaim < newTRPC) {
                dividend = dividend.add((newTRPC - prevTotalRewardsPerClaim).mul(_balanceAddrs[0]) / (1 ether));
                internalSAPTRPW[uint8(i)][_FCPaddr][_subAccts[0]][_FCPaddr] = newTRPC;
            }
            else if (i & (1 << 14) > 0) {
                internalSAPTRPW[uint8(i)][_FCPaddr][_subAccts[0]][_FCPaddr] = prevTotalRewardsPerClaim;
            }

            if (dividend > 1) {
                dividend--; //sub 1 from dividend to prevent rounding errors resulting in dist acct insolvency by small amounts
                internalDistributionAccountRewards[uint8(i)][_FCPaddr] = internalDistributionAccountRewards[uint8(i)][_FCPaddr].sub(dividend);
                if (i & (1 << 13) > 0) {
                    internalDistributionAccountRewards[uint8(i)][_subAccts[0]] = internalDistributionAccountRewards[uint8(i)][_subAccts[0]].add(dividend);
                }
                else {
                    bool success = IERC20(_rewardsAddr).transfer(_subAccts[0], dividend);
                    require(success);
                    internalPrevContractBalance[uint8(i)] = IERC20(_rewardsAddr).balanceOf(address(this));
                }
            }

            dividend = 0;
            prevTotalRewardsPerClaim = internalSAPTRPW[uint8(i)][_FCPaddr][_subAccts[1]][_FCPaddr];
            if (i & (1 << 12) > 0) {
                //collect all YT associated rewards
                if (prevTotalRewardsPerClaim < TRPY) {
                    dividend = (TRPY - prevTotalRewardsPerClaim).mul(_yieldArr[1]) / (1 ether);
                }
                prevTotalRewardsPerClaim = TRPY;
            }

            if (prevTotalRewardsPerClaim < newTRPC) {
                dividend = dividend.add((newTRPC - prevTotalRewardsPerClaim).mul(_balanceAddrs[1]) / (1 ether));
                internalSAPTRPW[uint8(i)][_FCPaddr][_subAccts[1]][_FCPaddr] = newTRPC;
            }
            else if (i & (1 << 12) > 0) {
                internalSAPTRPW[uint8(i)][_FCPaddr][_subAccts[1]][_FCPaddr] = prevTotalRewardsPerClaim;
            }

            if (dividend > 1) {
                dividend--; //sub 1 from dividend to prevent rounding errors resulting in dist acct insolvency by small amounts
                internalDistributionAccountRewards[uint8(i)][_FCPaddr] = internalDistributionAccountRewards[uint8(i)][_FCPaddr].sub(dividend);
                if (i & (1 << 11) > 0) {
                    internalDistributionAccountRewards[uint8(i)][_subAccts[1]] = internalDistributionAccountRewards[uint8(i)][_subAccts[1]].add(dividend);
                }
                else {
                    bool success = IERC20(_rewardsAddr).transfer(_subAccts[1], dividend);
                    require(success);
                    internalPrevContractBalance[uint8(i)] = IERC20(_rewardsAddr).balanceOf(address(this));
                }
            }
        }
        if (i & (1 << 14) > 0) {
            internalHasClaimedAllYTrewards[_FCPaddr][_subAccts[0]][_FCPaddr] = true;
        }
        if (i & (1 << 12) > 0) {
            internalHasClaimedAllYTrewards[_FCPaddr][_subAccts[1]][_FCPaddr] = true;
        }
    }


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