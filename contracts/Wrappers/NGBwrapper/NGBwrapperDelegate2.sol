// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "./NGBwrapperData.sol";

contract NGBwrapperDelegate2 is NGBwrapperData {
	using SafeMath for uint;
	using ABDKMath64x64 for int128;

	modifier doubleClaimRewards(address _addr0, address _addr1) {
		uint len = internalRewardsAssets.length;
		if (len == 0) {
			_;
			return;
		}
		len = len > type(uint8).max ? type(uint8).max : len;
		uint balanceAddr0 = internalBalanceOf[_addr0];
		uint balanceAddr1 = internalBalanceOf[_addr1];
		uint _totalSupply = internalTotalSupply;
		/*
			to save stack space multiple vars will be stored within i
			most significant bit = addr0 is distribution account
			next most significant bit = addr1 is distribution account
			least significant 8 bits = current index
		*/
		uint16 i = (internalIsDistributionAccount[_addr0] ? 1 << 15 : 0)
			& (internalIsDistributionAccount[_addr1] ? 1 << 14 : 0);
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
				internalPrevTotalRewardsPerWasset[uint8(i)][_addr0] = newTRPW;
				if (i >> 15 > 0) {
					address addr = _addr0; // prevent stack too deep
					internalDistributionAccountRewards[i][addr] = internalDistributionAccountRewards[i][addr].add(dividend);
				}
				else {
					bool success = IERC20(_rewardsAddr).transfer(_addr0, dividend);
					require(success);
				}
			}
			prevTRPW = internalPrevTotalRewardsPerWasset[uint8(i)][_addr1];
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr1) / (1 ether);
				getContractBalanceAgain = getContractBalanceAgain || dividend > 0;
				internalPrevTotalRewardsPerWasset[i][_addr1] = newTRPW;
				if (1 & (i >> 14) > 0) {
					internalDistributionAccountRewards[i][_addr1] = internalDistributionAccountRewards[i][_addr1].add(dividend);
				}
				else {
					bool success = IERC20(_rewardsAddr).transfer(_addr1, dividend);
					require(success);
				}
			}
			//fetch balanceOf again rather than taking CBRA and subtracting dividend because of small rounding errors that may occur
			//however if no transfers were executed it is fine to use the previously fetched CBRA value
			internalPrevContractBalance[uint8(i)] = getContractBalanceAgain ? IERC20(_rewardsAddr).balanceOf(address(this)) : CBRA;
			internalTotalRewardsPerWasset[uint8(i)] = newTRPW;
		}
		_;
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