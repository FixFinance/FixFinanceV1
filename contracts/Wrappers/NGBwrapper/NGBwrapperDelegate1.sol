// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "./NGBwrapperData.sol";

contract NGBwrapperDelegate1 is NGBwrapperData {
	using SafeMath for uint;
	using ABDKMath64x64 for int128;

	modifier claimRewards(address _addr) {
		uint len = internalRewardsAssets.length;
		if (len == 0) {
			_;
			return;
		}
		len = len > type(uint8).max ? type(uint8).max : len;
		uint balanceAddr = internalBalanceOf[_addr];
		uint _totalSupply = internalTotalSupply;
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
			bool getContractBalanceAgain = false;
			if (prevTRPW < newTRPW) {
				uint dividend = (newTRPW - prevTRPW).mul(balanceAddr) / (1 ether);
				getContractBalanceAgain = dividend > 0;
				internalPrevTotalRewardsPerWasset[i][_addr] = newTRPW;
				if (i >> 15 > 0) {
					internalDistributionAccountRewards[i][_addr] = internalDistributionAccountRewards[i][_addr].add(dividend);
				}
				else {
					bool success = IERC20(_rewardsAddr).transfer(_addr, dividend);
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

	/*
		@Description: collect fee, send 50% to owner and 50% to treasury address
			after the fee is collected the funds that are retained for wrapped asset holders will
			be == underlyingAsset.balanceOf(this) * (SBPSRetained/totalSBPS)**timeSinceLastHarvest(years)
			though it should be noted that if the fee is greater than 20% of the total interest
			generated since the last harvest the fee will be set to 20% of the total interest
			generated since the last harvest
	*/
	function harvestToTreasury() public {
		uint _lastHarvest = internalLastHarvest;
		if (block.timestamp == _lastHarvest) {
			return;
		}
		uint contractBalance = IERC20(internalUnderlyingAssetAddress).balanceOf(address(this));
		uint prevTotalSupply = internalTotalSupply;
		uint _prevRatio = internalPrevRatio;
		//time in years
		/*
			nextBalance = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply*contractBalance/internalTotalSupply = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply/internalTotalSupply = ((totalBips-bipsToTreasury)/totalBips)**t
			internalTotalSupply = prevTotalSupply*((totalBips-bipsToTreasury)/totalBips)**(-t)
		*/
		uint effectiveRatio = uint(1 ether).mul(contractBalance);
		uint nonFeeAdjustedRatio = effectiveRatio.div(prevTotalSupply);
		if (nonFeeAdjustedRatio <= _prevRatio) {
			//only continue if yield has been generated
			return;
		}
		uint minNewRatio = (nonFeeAdjustedRatio - _prevRatio).mul(minHarvestRetention).div(totalSBPS).add(_prevRatio);
		int128 time = int128(((block.timestamp - _lastHarvest) << 64)/ BigMath.SecondsPerYear);
		uint term = uint(BigMath.Pow(int128((uint(SBPSRetained) << 64) / totalSBPS), time.neg()));
		uint newTotalSupply = prevTotalSupply.mul(term) >> 64;
		effectiveRatio = effectiveRatio.div(newTotalSupply);
		if (effectiveRatio < minNewRatio) {
			/*
				ratio == contractBalance/internalTotalSupply
				internalTotalSupply == contractBalance/ratio
			*/
			newTotalSupply = contractBalance.mul(1 ether).div(minNewRatio);
			internalPrevRatio = minNewRatio;
		}
		else {
			internalPrevRatio = effectiveRatio;
		}
		internalLastHarvest = block.timestamp;
		uint dividend = newTotalSupply.sub(prevTotalSupply);
		address sendTo = IInfoOracle(internalInfoOracleAddress).sendTo();
		internalBalanceOf[sendTo] += dividend >> 1;
		internalBalanceOf[owner] += dividend - (dividend >> 1);
		internalTotalSupply = newTotalSupply;
	}

	/*
		@Description: make first deposit into contract, internalTotalSupply must == 0
		
		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function firstDeposit(address _to, uint _amountUnit) internal returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		bool success = _aToken.transferFrom(msg.sender, address(this), _amountUnit);
		require(success);
		internalBalanceOf[_to] = _amountUnit;
		internalTotalSupply = _amountUnit;
		_amountWrappedToken = _amountUnit;
		internalLastHarvest = block.timestamp;
		internalPrevRatio = 1 ether;
	}

	/*
		@Description: send in underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function deposit(address _to, uint _amountUnit) internal returns (uint _amountWrappedToken) {
		uint _totalSupply = internalTotalSupply;
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amountUnit);
		}
		harvestToTreasury();
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		bool success = _aToken.transferFrom(msg.sender, address(this), _amountUnit);
		require(success);
		_amountWrappedToken = internalTotalSupply*_amountUnit/contractBalance;
		internalBalanceOf[_to] += _amountWrappedToken;
		internalTotalSupply += _amountWrappedToken;
	}

	/*
		@Description: send in a specific amount of underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of underlying asset units to deposit
	*/
	function depositUnitAmount(address _to, uint _amount) external claimRewards(_to) returns (uint _amountWrapped) {
		return deposit(_to, _amount);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external claimRewards(_to) returns (uint _amountUnit) {
		_amountUnit = WrappedAmtToUnitAmt_RoundUp(_amount);
		deposit(_to, _amountUnit);
	}

	/*
		@Description: burn wrapped asset to receive an amount of underlying asset of _amountUnit

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountUnit: the amount of underlying asset units to withdraw

		@return uint _amountWrappedToken: the amount of units of wrapped asset that were burned
	*/
	function withdrawUnitAmount(address _to, uint _amountUnit) external claimRewards(_to) returns (uint _amountWrappedToken) {
		harvestToTreasury();
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		//_amountWrappedToken == ceil(internalTotalSupply*_amountUnit/contractBalance)
		_amountWrappedToken = internalTotalSupply*_amountUnit;
		_amountWrappedToken = (_amountWrappedToken%contractBalance == 0 ? 0 : 1) + (_amountWrappedToken/contractBalance);
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		internalBalanceOf[msg.sender] -= _amountWrappedToken;
		internalTotalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountUnit);
	}

	/*
		@Description: burn a specific amount of wrappet asset to get out underlying asset

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountWrappedToken: the amount of units of wrappet asset to burn

		@return uint _amountUnit: the amount of underlying asset received
	*/
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken) external claimRewards(_to) returns (uint _amountUnit) {
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		harvestToTreasury();
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_amountUnit = contractBalance*_amountWrappedToken/internalTotalSupply;
		internalBalanceOf[msg.sender] -= _amountWrappedToken;
		internalTotalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountUnit);
	}

	function forceRewardsCollection() external claimRewards(msg.sender) {}

	/*
		@Description: get the ratio of underlyingAsset / wrappedAsset
	*/
	function getRatio() internal view returns (uint) {
		uint _totalSupply = internalTotalSupply;	
		uint _prevRatio = internalPrevRatio;
		uint contractBalance = IERC20(internalUnderlyingAssetAddress).balanceOf(address(this));
		uint nonFeeAdjustedRatio = uint(1 ether).mul(contractBalance).div(_totalSupply);
		//handle odd case, most likely only caused by rounding error (off by 1)
		if (nonFeeAdjustedRatio <= _prevRatio) {
			return _prevRatio;
		}
		uint minNewRatio = (nonFeeAdjustedRatio-_prevRatio)
			.mul(minHarvestRetention)
			.div(totalSBPS)
			.add(_prevRatio);
		return minNewRatio;
	}


	/*
		@Description: convert an amount of underlying asset to its corresponding amount of wrapped asset, round down

		@param uint _amountUnit: the amount of underlying asset to convert

		@return uint _amountWrappedToken: the greatest amount of wrapped asset that is <= _amountUnit underlying asset
	*/
	function UnitAmtToWrappedAmt_RoundDown(uint _amountUnit) internal view returns (uint _amountWrappedToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountWrapped == amountUnit/ratio
		*/
		_amountWrappedToken = _amountUnit.mul(1 ether).div(ratio);
	}

	/*
		@Description: convert an amount of underlying asset to its corresponding amount of wrapped asset, round up

		@param uint _amountUnit: the amount of underlying asset to convert

		@return uint _amountWrappedToken: the smallest amount of wrapped asset that is >= _amountUnit underlying asset
	*/
	function UnitAmtToWrappedAmt_RoundUp(uint _amountUnit) internal view returns (uint _amountWrappedToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountWrapped == amountUnit/ratio
		*/
		_amountWrappedToken = _amountUnit.mul(1 ether);
		_amountWrappedToken = _amountWrappedToken/ratio + (_amountWrappedToken%ratio == 0 ? 0 : 1);
	}

	/*
		@Description: convert an amount of wrapped asset to its corresponding amount of underlying asset, round down

		@oaram unit _amountWrappedToken: the amount of wrapped asset to convert

		@return uint _amountWrappedToken: the greatest amount of underlying asset that is <= _amountWrapped wrapped asset
	*/
	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrappedToken) internal view returns (uint _amountUnit) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountUnit == amountWrapped * ratio
		*/
		_amountUnit = _amountWrappedToken.mul(ratio)/(1 ether);
	}

	/*
		@Description: convert an amount of wrapped asset to its corresponding amount of underlying asset, round up

		@oaram unit _amountWrappedToken: the amount of wrapped asset to convert

		@return uint _amountWrappedToken: the smallest amount of underlying asset that is >= _amountWrapped wrapped asset
	*/
	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrappedToken) internal view returns (uint _amountUnit) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountUnit == amountWrapped * ratio
		*/
		_amountUnit = _amountWrappedToken.mul(ratio);
		_amountUnit = _amountUnit/(1 ether) + (_amountUnit%(1 ether) == 0 ? 0 : 1);
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