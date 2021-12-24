// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/SafeERC20.sol";
import "./CTokenWrapperInternals.sol";

contract CTokenWrapperDelegateParent is CTokenWrapperInternals {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;
	using SafeERC20 for IERC20;

	event FlashMint(
		address indexed to,
		uint wrappedAmount
	);

	event FlashBurn(
		address indexed from,
		uint wrappedAmount,
		uint feeAmount
	);

	/*
		@Description: claim rewards for an address holding the wrapped asset of the wrapper contract, modifier form
	
		@param bool _claim: if false don't do not do any computation return immediately
			if true go ahead and actually claim rewards
		@param address _addr: the address for which to claim rewards
	*/
	modifier claimRewards(bool _claim, address _addr) {
		if (!_claim) {
			_;
			return;
		}
		uint len = internalRewardsAssets.length;
		if (len == 0) {
			_;
			return;
		}
		len = len > type(uint8).max ? type(uint8).max : len;
		uint _totalSupply = internalTotalSupply;
		if (_totalSupply == 0) {
			_;
			return;
		}
		uint balanceAddr = internalBalanceOf[_addr];
		internalClaimRewards(_addr, len, _totalSupply, balanceAddr);
		_;
	}

	/*
		@Description: claim rewards for an address holding the wrapped asset of the wrapper contract, internal function

		@param address _addr: the address for which to claim rewards
		@param uint _len: the length of the rewards asset array
		@param uint _totalSupply: copy of internalTotalSupply
		@param uint _balanceAddr: the balance of the address for which to claim rewards
	*/
	function internalClaimRewards(address _addr, uint _len, uint _totalSupply, uint _balanceAddr) internal {
		uint16 i = internalIsDistributionAccount[_addr] ? 1 << 15 : 0;
		for ( ; uint8(i) < _len; i++) {
			address _rewardsAddr = internalRewardsAssets[uint8(i)];
			if (_rewardsAddr == address(0)) {
				continue;
			}
			uint newTRPW;
			uint CBRA = IERC20(_rewardsAddr).balanceOf(address(this)); //contract balance rewards asset
			{
				uint prevCBRA = internalPrevContractBalance[uint8(i)];
				uint newRewardsPerWasset = CBRA.sub(prevCBRA).mul(1 ether).div(_totalSupply);
				newTRPW = internalTotalRewardsPerWasset[uint8(i)].add(newRewardsPerWasset);
			}
			uint prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr];
			uint activationTRPW = internalTRPWuponActivation[uint8(i)];
			prevTRPW = prevTRPW > activationTRPW ? prevTRPW : activationTRPW;
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(_balanceAddr) / (1 ether);
				internalPrevTotalRewardsPerWasset[uint8(i)][_addr] = newTRPW;
				if (dividend > 0) {
					if (i >> 15 > 0) {
						internalDistributionAccountRewards[uint8(i)][_addr] = internalDistributionAccountRewards[uint8(i)][_addr].add(dividend);
					}
					else {
						IERC20(_rewardsAddr).safeTransfer(_addr, dividend);
						CBRA = CBRA.sub(dividend);
					}
				}
			}
			internalPrevContractBalance[uint8(i)] = CBRA;
			internalTotalRewardsPerWasset[uint8(i)] = newTRPW;
		}
	}

	/*
		@Description: claim rewards for two addresses holding the wrapped asset of the wrapper contract
	
		@param address _addr0: the first address for which to claim rewards
		@param address _addr1: the second address for which to claim rewards
	*/
	modifier doubleClaimRewards(address _addr0, address _addr1) {
		uint len = internalRewardsAssets.length;
		if (len == 0) {
			_;
			return;
		}
		len = len > type(uint8).max ? type(uint8).max : len;
		uint _totalSupply = internalTotalSupply;
		if (_totalSupply == 0) {
			_;
			return;
		}
		uint balanceAddr0 = internalBalanceOf[_addr0];
		uint balanceAddr1 = internalBalanceOf[_addr1];
		internalDoubleClaimRewards(_addr0, _addr1, len, _totalSupply, balanceAddr0, balanceAddr1);
		_;
	}

	function internalDoubleClaimRewards(
		address _addr0,
		address _addr1,
		uint len,
		uint _totalSupply,
		uint balanceAddr0,
		uint balanceAddr1
	) internal {
		/*
			to save stack space multiple vars will be stored within i
			most significant bit = addr0 is distribution account
			next most significant bit = addr1 is distribution account
			least significant 8 bits = current index
		*/
		uint16 i = (internalIsDistributionAccount[_addr0] ? 1 << 15 : 0)
			| (internalIsDistributionAccount[_addr1] ? 1 << 14 : 0);
		for (; uint8(i) < len; i++) {
			address _rewardsAddr = internalRewardsAssets[uint8(i)];
			if (_rewardsAddr == address(0)) {
				continue;
			}
			uint newTRPW;
			uint CBRA = IERC20(_rewardsAddr).balanceOf(address(this)); //contract balance rewards asset
			{
				uint prevCBRA = internalPrevContractBalance[uint8(i)];
				uint newRewardsPerWasset = CBRA.sub(prevCBRA).mul(1 ether).div(_totalSupply);
				newTRPW = internalTotalRewardsPerWasset[uint8(i)].add(newRewardsPerWasset);
			}
			uint prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr0];
			uint activationTRPW = internalTRPWuponActivation[uint8(i)];
			prevTRPW = prevTRPW > activationTRPW ? prevTRPW : activationTRPW;
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr0) / (1 ether);
				address addr = _addr0; // prevent stack too deep
				internalPrevTotalRewardsPerWasset[uint8(i)][addr] = newTRPW;
				if (i >> 15 > 0) {
					internalDistributionAccountRewards[uint8(i)][addr] = internalDistributionAccountRewards[uint8(i)][addr].add(dividend);
				}
				else {
					IERC20(_rewardsAddr).safeTransfer(addr, dividend);
					CBRA = CBRA.sub(dividend);
				}
			}
			prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr1];
			prevTRPW = prevTRPW > activationTRPW ? prevTRPW : activationTRPW;
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr1) / (1 ether);
				internalPrevTotalRewardsPerWasset[uint8(i)][_addr1] = newTRPW;
				if (1 & (i >> 14) > 0) {
					internalDistributionAccountRewards[uint8(i)][_addr1] = internalDistributionAccountRewards[uint8(i)][_addr1].add(dividend);
				}
				else {
					IERC20(_rewardsAddr).safeTransfer(_addr1, dividend);
					CBRA = CBRA.sub(dividend);
				}
			}
			internalPrevContractBalance[uint8(i)] = CBRA;
			internalTotalRewardsPerWasset[uint8(i)] = newTRPW;
		}
	}

}