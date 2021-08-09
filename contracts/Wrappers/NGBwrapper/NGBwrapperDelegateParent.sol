// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "./NGBwrapperData.sol";

contract NGBwrapperDelegateParent is NGBwrapperData {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;

	/*
		@Description: claim rewards for an address holding the wrapped asset of the wrapper contract
	
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
		uint16 i = internalIsDistributionAccount[_addr] ? 1 << 15 : 0;
		for ( ; uint8(i) < len; i++) {
			address _rewardsAddr = internalRewardsAssets[uint8(i)];
			if (_rewardsAddr == address(0)) {
				continue;
			}
			uint newTRPW;
			uint CBRA = IERC20(_rewardsAddr).balanceOf(address(this)); //contract balance rewards asset
			{
				uint prevCBRA = internalPrevContractBalance[uint8(i)];
				if (prevCBRA > CBRA) { //odd case, should never happen
					continue;
				}
				uint newRewardsPerWasset = (CBRA - prevCBRA).mul(1 ether).div(_totalSupply);
				newTRPW = internalTotalRewardsPerWasset[uint8(i)].add(newRewardsPerWasset);
			}
			uint prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr];
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr) / (1 ether);
				internalPrevTotalRewardsPerWasset[uint8(i)][_addr] = newTRPW;
				if (dividend > 0) {
					if (i >> 15 > 0) {
						internalDistributionAccountRewards[uint8(i)][_addr] = internalDistributionAccountRewards[uint8(i)][_addr].add(dividend);
					}
					else {
						bool success = IERC20(_rewardsAddr).transfer(_addr, dividend);
						require(success);
						CBRA = CBRA.sub(dividend);
					}
				}
			}
			internalPrevContractBalance[uint8(i)] = CBRA;
			internalTotalRewardsPerWasset[uint8(i)] = newTRPW;
		}
		_;
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
				if (prevCBRA > CBRA) { //odd case, should never happen
					continue;
				}
				uint newRewardsPerWasset = (CBRA - prevCBRA).mul(1 ether).div(_totalSupply);
				newTRPW = internalTotalRewardsPerWasset[uint8(i)].add(newRewardsPerWasset);
			}
			uint prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr0];
			bool getContractBalanceAgain = false;
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr0) / (1 ether);
				getContractBalanceAgain = dividend > 0;
				address addr = _addr0; // prevent stack too deep
				internalPrevTotalRewardsPerWasset[uint8(i)][addr] = newTRPW;
				if (i >> 15 > 0) {
					internalDistributionAccountRewards[uint8(i)][addr] = internalDistributionAccountRewards[uint8(i)][addr].add(dividend);
				}
				else {
					bool success = IERC20(_rewardsAddr).transfer(addr, dividend);
					require(success);
					CBRA = CBRA.sub(dividend);
				}
			}
			prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr1];
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr1) / (1 ether);
				getContractBalanceAgain = getContractBalanceAgain || dividend > 0;
				address addr = _addr1; // prevent stack too deep
				internalPrevTotalRewardsPerWasset[uint8(i)][addr] = newTRPW;
				if (1 & (i >> 14) > 0) {
					internalDistributionAccountRewards[uint8(i)][addr] = internalDistributionAccountRewards[uint8(i)][addr].add(dividend);
				}
				else {
					bool success = IERC20(_rewardsAddr).transfer(addr, dividend);
					require(success);
					CBRA = CBRA.sub(dividend);
				}
			}
			internalPrevContractBalance[uint8(i)] = CBRA;
			internalTotalRewardsPerWasset[uint8(i)] = newTRPW;
		}
		_;
	}

}