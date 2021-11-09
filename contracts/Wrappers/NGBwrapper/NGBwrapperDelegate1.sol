// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "../../libraries/SafeERC20.sol";
import "./NGBwrapperDelegateParent.sol";

contract NGBwrapperDelegate1 is NGBwrapperDelegateParent {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;
	using SafeERC20 for IERC20;

	function harvestToTreasury() external {
		internalHarvestToTreasury(IERC20(internalUnderlyingAssetAddress));
	}

	function extractRetsHarvestToTreasury(IERC20 _underlyingAsset) internal returns(uint, uint) {
		uint[2] memory rets = internalHarvestToTreasury(_underlyingAsset);
		return (rets[0], rets[1]);
	}

	/*
		@Description: collect fee, send 50% to owner and 50% to treasury address
			after the fee is collected the funds that are retained for wrapped asset holders will
			be == underlyingAsset.balanceOf(this) * (SBPSRetained/totalSBPS)**timeSinceLastHarvest(years)
			though it should be noted that if the fee is greater than 20% of the total interest
			generated since the last harvest the fee will be set to 20% of the total interest
			generated since the last harvest

		@param IERC20 _underlyingAsset: ERC20 representation of the underlying asset

		@return uint[2]:
			arr[0]: total supply at end of execution
			arr[1]: this contract's balance of the underlying
	*/
	function internalHarvestToTreasury(IERC20 _underlyingAsset) internal returns(uint[2] memory) {
		uint _lastHarvest = internalLastHarvest;
		uint prevTotalSupply = internalTotalSupply;
		if (prevTotalSupply == 0) {
			return [uint(0), uint(0)];
		}
		uint contractBalance = _underlyingAsset.balanceOf(address(this));
		if (block.timestamp == _lastHarvest) {
			return [prevTotalSupply, contractBalance];
		}
		uint _prevRatio = internalPrevRatio;
		//time in years
		/*
			nextBalance == contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply*contractBalance/internalTotalSupply == contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply/internalTotalSupply == ((totalBips-bipsToTreasury)/totalBips)**t
			internalTotalSupply == prevTotalSupply*((totalBips-bipsToTreasury)/totalBips)**(-t)
		*/
		uint effectiveRatio = uint(1 ether).mul(contractBalance);
		uint nonFeeAdjustedRatio = effectiveRatio.div(prevTotalSupply);
		if (nonFeeAdjustedRatio <= _prevRatio) {
			//only continue if yield has been generated
			return [prevTotalSupply, contractBalance];
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
		IInfoOracle iorc = IInfoOracle(internalInfoOracleAddress);
		address _owner = owner;
		if (iorc.TreasuryFeeIsCollected()) {
			address sendTo = iorc.sendTo();
			internalBalanceOf[sendTo] = internalBalanceOf[sendTo].add(dividend >> 1);
			internalBalanceOf[_owner] = internalBalanceOf[_owner].add(dividend - (dividend >> 1));
		}
		else {
			internalBalanceOf[_owner] = internalBalanceOf[_owner].add(dividend);
		}
		internalTotalSupply = newTotalSupply;
		return [newTotalSupply, contractBalance];
	}

	/*
		@Description: make first deposit into contract, internalTotalSupply must == 0
		
		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit
		@param IERC20 _underlyingAsset: the underlying asset which the NGBwrapper contract is based on

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function firstDeposit(address _to, uint _amountUnit, IERC20 _underlyingAsset) internal returns (uint _amountWrappedToken) {
		_underlyingAsset.safeTransferFrom(msg.sender, address(this), _amountUnit);
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
		IERC20 underlying = IERC20(internalUnderlyingAssetAddress);
		(uint _totalSupply, uint contractBalance) = extractRetsHarvestToTreasury(underlying);
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amountUnit, underlying);
		}
		underlying.safeTransferFrom(msg.sender, address(this), _amountUnit);
		_amountWrappedToken = internalTotalSupply.mul(_amountUnit).div(contractBalance);
		internalBalanceOf[_to] = internalBalanceOf[_to].add(_amountWrappedToken);
		//we cannot use _totalSupply as the value of internalTotalSupply may have been changed in internalHarvestToTreasury()
		internalTotalSupply = internalTotalSupply.add(_amountWrappedToken);
	}

	/*
		@Description: send in a specific amount of underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of underlying asset units to deposit
	*/
	function depositUnitAmount(address _to, uint _amount) external claimRewards(true, _to) returns (uint _amountWrapped) {
		return deposit(_to, _amount);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external claimRewards(true, _to) returns (uint _amountUnit) {
		_amountUnit = WrappedAmtToUnitAmt_RoundUp(_amount);
		deposit(_to, _amountUnit);
	}

	/*
		@Description: burn wrapped asset to receive an amount of underlying asset of _amountUnit

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountUnit: the amount of underlying asset units to withdraw

		@return uint _amountWrappedToken: the amount of units of wrapped asset that were burned
	*/
	function withdrawUnitAmount(address _to, uint _amountUnit, bool _claimRewards) external claimRewards(_claimRewards, msg.sender) returns (uint _amountWrappedToken) {
		IERC20 underlying = IERC20(internalUnderlyingAssetAddress);
		(uint _totalSupply, uint contractBalance) = extractRetsHarvestToTreasury(underlying);
		//_amountWrappedToken == ceil(internalTotalSupply*_amountUnit/contractBalance)
		_amountWrappedToken = _totalSupply.mul(_amountUnit);
		_amountWrappedToken = uint256(_amountWrappedToken%contractBalance == 0 ? 0 : 1).add(_amountWrappedToken.div(contractBalance));
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		internalBalanceOf[msg.sender] = internalBalanceOf[msg.sender].sub(_amountWrappedToken);
		internalTotalSupply = _totalSupply.sub(_amountWrappedToken);
		underlying.safeTransfer(_to, _amountUnit);
	}

	/*
		@Description: burn a specific amount of wrappet asset to get out underlying asset

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountWrappedToken: the amount of units of wrappet asset to burn

		@return uint _amountUnit: the amount of underlying asset received
	*/
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken, bool _claimRewards) external claimRewards(_claimRewards, msg.sender) returns (uint _amountUnit) {
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		IERC20 underlying = IERC20(internalUnderlyingAssetAddress);
		(uint _totalSupply, uint contractBalance) = extractRetsHarvestToTreasury(underlying);
		_amountUnit = contractBalance.mul(_amountWrappedToken).div(_totalSupply);
		internalBalanceOf[msg.sender] = internalBalanceOf[msg.sender].sub(_amountWrappedToken);
		internalTotalSupply = _totalSupply.sub(_amountWrappedToken);
		underlying.safeTransfer(_to, _amountUnit);
	}

	function forceRewardsCollection() external claimRewards(true, msg.sender) {}

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
		_amountWrappedToken = _amountWrappedToken.div(ratio).add(_amountWrappedToken%ratio == 0 ? 0 : 1);
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
		_amountUnit = _amountUnit.div(1 ether).add(_amountUnit%(1 ether) == 0 ? 0 : 1);
	}

}