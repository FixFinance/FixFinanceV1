// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/ICToken.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "./CTokenWrapperDelegateParent.sol";

contract CTokenWrapperDelegate1 is CTokenWrapperDelegateParent {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;

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
		uint contractControlled;
		{
			ICToken cToken = ICToken(internalUnderlyingAssetAddress);
			uint contractBalance = cToken.balanceOf(address(this));
			uint exchangeRate = cToken.exchangeRateStored();
			contractControlled = contractBalance.mul(exchangeRate) / (1 ether);
		}
		uint prevTotalSupply = internalTotalSupply;
		uint _prevRatio = internalPrevRatio;
		//time in years
		/*
			nextBalance == contractControlled * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply*contractControlled/totalSupply == contractControlled * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply/totalSupply == ((totalBips-bipsToTreasury)/totalBips)**t
			totalSupply == prevTotalSupply*((totalBips-bipsToTreasury)/totalBips)**(-t)
		*/
		uint effectiveRatio = uint(1 ether).mul(contractControlled);
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
				ratio == contractControlled/internalTotalSupply
				internalTotalSupply == contractBalance/ratio
			*/
			newTotalSupply = contractControlled.mul(1 ether).div(minNewRatio);
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
			internalTotalSupply = newTotalSupply;
		}
		else {
			internalBalanceOf[_owner] = internalBalanceOf[_owner].add(dividend);
		}
	}

	/*
		@Description: make first deposit into contract, internalTotalSupply must == 0
		
		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountCToken: the amount of cToken to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function firstDeposit(address _to, uint _amountCToken, ICToken _cToken) internal returns (uint _amountWrappedToken) {
		bool success = _cToken.transferFrom(msg.sender, address(this), _amountCToken);
		require(success);
		internalBalanceOf[_to] = _amountCToken;
		internalTotalSupply = _amountCToken;
		_amountWrappedToken = _amountCToken;
		internalLastHarvest = block.timestamp;
		internalPrevRatio = _cToken.exchangeRateStored();
	}


	/*
		@Description: send in a specific amount of underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of underlying asset units to deposit
	*/
	function depositUnitAmount(address _to, uint _amount) external claimRewards(true, _to) returns (uint _amountWrapped) {
		ICToken cToken = ICToken(internalUnderlyingAssetAddress);
		uint exchangeRate = cToken.exchangeRateStored();
		uint _totalSupply = internalTotalSupply;
		uint cTokenIn = _amount.mul(1 ether).div(exchangeRate);
		if (_totalSupply == 0) {
			return firstDeposit(_to, cTokenIn, cToken);
		}
		harvestToTreasury();
		uint contractBalance = cToken.balanceOf(address(this));
		_amountWrapped = cTokenIn.mul(_totalSupply).div(contractBalance);

		address toCopy = _to; //prevent stack too deep
		internalBalanceOf[toCopy] = internalBalanceOf[toCopy].add(_amountWrapped);
		internalTotalSupply = _totalSupply.add(_amountWrapped);
		bool success = cToken.transferFrom(msg.sender, address(this), cTokenIn);
		require(success);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external claimRewards(true, _to) returns (uint _amountUnit) {
		ICToken cToken = ICToken(internalUnderlyingAssetAddress);
		uint _totalSupply = internalTotalSupply;
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amount, cToken);
		}
		harvestToTreasury();
		uint contractBalance = cToken.balanceOf(address(this));
		uint cTokenIn = contractBalance.mul(_amount).div(_totalSupply).add(1);
		uint exchangeRate = cToken.exchangeRateStored();
		_amountUnit = cTokenIn.mul(1 ether).div(exchangeRate);

		address toCopy = _to; //prevent stack too deep
		internalBalanceOf[toCopy] = internalBalanceOf[toCopy].add(_amount);
		internalTotalSupply = _totalSupply.add(_amount);
		bool success = cToken.transferFrom(msg.sender, address(this), cTokenIn);
		require(success);
	}

	/*
		@Description: burn wrapped asset to receive an amount of underlying asset of _amountUnit

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountUnit: the amount of underlying asset units to withdraw

		@return uint _amountWrappedToken: the amount of units of wrapped asset that were burned
	*/
	function withdrawUnitAmount(address _to, uint _amountUnit, bool _claimRewards) external claimRewards(_claimRewards, msg.sender) returns (uint _amountWrappedToken) {
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
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken, bool _claimRewards) external claimRewards(_claimRewards, msg.sender) returns (uint _amountUnit) {
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		harvestToTreasury();
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_amountUnit = contractBalance*_amountWrappedToken/internalTotalSupply;
		internalBalanceOf[msg.sender] -= _amountWrappedToken;
		internalTotalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountUnit);
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

}