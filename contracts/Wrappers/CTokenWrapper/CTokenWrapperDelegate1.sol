// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/ICToken.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "../../libraries/SafeERC20.sol";
import "./CTokenWrapperDelegateParent.sol";

contract CTokenWrapperDelegate1 is CTokenWrapperDelegateParent {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;
	using SafeERC20 for IERC20;

	function harvestToTreasury() external {
		internalHarvestToTreasury(ICToken(internalUnderlyingAssetAddress));
	}

	function extractRetsHarvestToTreasury(ICToken _cToken) internal returns(uint, uint, uint) {
		uint[3] memory rets = internalHarvestToTreasury(_cToken);
		return (rets[0], rets[1], rets[2]);
	}

	/*
		@Description: collect fee, send 50% to owner and 50% to treasury address
			after the fee is collected the funds that are retained for wrapped asset holders will
			be == underlyingAsset.balanceOf(this) * (SBPSRetained/totalSBPS)**timeSinceLastHarvest(years)
			though it should be noted that if the fee is greater than 20% of the total interest
			generated since the last harvest the fee will be set to 20% of the total interest
			generated since the last harvest

		@param ICToken _cToken: the underlying c token

		@return uint[3]:
			arr[0]: total supply at end of execution
			arr[1]: value returned by cToken.exchangeRateStored()
			arr[2]: this contract's balance of cTokens
	*/
	function internalHarvestToTreasury(ICToken _cToken) internal returns(uint[3] memory) {
		uint _lastHarvest = internalLastHarvest;
		uint prevTotalSupply = internalTotalSupply;
		uint contractControlled;
		uint exchangeRate;
		uint contractBalance;
		{
			exchangeRate = _cToken.exchangeRateStored();			
			if (prevTotalSupply == 0) {
				return [0, exchangeRate, 0];
			}
			contractBalance = _cToken.balanceOf(address(this));
			if (block.timestamp == _lastHarvest) {
				return [prevTotalSupply, exchangeRate, contractBalance];
			}
			contractControlled = contractBalance.mul(exchangeRate) / (1 ether);
		}
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
			return [prevTotalSupply, exchangeRate, contractBalance];
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
		}
		else {
			internalBalanceOf[_owner] = internalBalanceOf[_owner].add(dividend);
		}
		internalTotalSupply = newTotalSupply;
		return [newTotalSupply, exchangeRate, contractBalance];
	}

	/*
		@Description: make first deposit into contract, internalTotalSupply must == 0
		
		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountCToken: the amount of cToken to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function firstDeposit(address _to, uint _amountCToken, ICToken _cToken) internal returns (uint _amountWrappedToken) {
		require(_amountCToken >= 10**uint(_cToken.decimals()));
		IERC20(address(_cToken)).safeTransferFrom(msg.sender, address(this), _amountCToken);
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
		(uint _totalSupply, uint exchangeRate, uint contractBalance) = extractRetsHarvestToTreasury(cToken);
		uint cTokenIn = _amount.mul(1 ether).div(exchangeRate);
		if (_totalSupply == 0) {
			return firstDeposit(_to, cTokenIn, cToken);
		}
		_amountWrapped = cTokenIn.mul(_totalSupply).div(contractBalance);
		address toCopy = _to; //prevent stack too deep
		internalBalanceOf[toCopy] = internalBalanceOf[toCopy].add(_amountWrapped);
		//we cannot use _totalSupply as internalTotalSupply was set in harvestToTreasury
		internalTotalSupply = internalTotalSupply.add(_amountWrapped);
		IERC20(address(cToken)).safeTransferFrom(msg.sender, address(this), cTokenIn);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external claimRewards(true, _to) returns (uint _amountUnit) {
		ICToken cToken = ICToken(internalUnderlyingAssetAddress);
		(uint _totalSupply, uint exchangeRate, uint contractBalance) = extractRetsHarvestToTreasury(cToken);
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amount, cToken);
		}
		uint cTokenIn = contractBalance.mul(_amount);
			cTokenIn = cTokenIn.div(_totalSupply).add(1);
		_amountUnit = cTokenIn.mul(exchangeRate).div(1 ether);
		address toCopy = _to; //prevent stack too deep
		internalBalanceOf[toCopy] = internalBalanceOf[toCopy].add(_amount);
		//we cannot use _totalSupply as internalTotalSupply was set in harvestToTreasury
		internalTotalSupply = internalTotalSupply.add(_amount);
		IERC20(address(cToken)).safeTransferFrom(msg.sender, address(this), cTokenIn);
	}

	event EVNT(uint its);

	/*
		@Description: burn wrapped asset to receive an amount of underlying asset of _amountUnit

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountUnit: the amount of underlying asset units to withdraw

		@return uint _amountWrappedToken: the amount of units of wrapped asset that were burned
	*/
	function withdrawUnitAmount(address _to, uint _amountUnit, bool _claimRewards) external claimRewards(_claimRewards, msg.sender) returns (uint _amountWrappedToken) {
		ICToken cToken = ICToken(internalUnderlyingAssetAddress);
		(uint _totalSupply, uint exchangeRate, uint contractBalance) = extractRetsHarvestToTreasury(cToken);
		//_amountWrappedToken == ceil(internalTotalSupply*_amountUnit/contractBalance)
		uint amountCToken = _amountUnit;
			amountCToken = amountCToken.mul(1 ether).div(exchangeRate); //prevent stack too deep
		_amountWrappedToken = amountCToken.mul(_totalSupply).div(contractBalance);
		uint bal = internalBalanceOf[msg.sender];
		internalBalanceOf[msg.sender] = bal.sub(_amountWrappedToken);
		internalTotalSupply = internalTotalSupply.sub(_amountWrappedToken);
		address copyTo = _to; //prevent stack too deep
		IERC20(address(cToken)).safeTransfer(copyTo, amountCToken.sub(1)); //subtract 1 to offset any rounding errors
	}

	/*
		@Description: burn a specific amount of wrappet asset to get out underlying asset

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountWrappedToken: the amount of units of wrappet asset to burn

		@return uint _amountUnit: the amount of underlying asset received
	*/
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken, bool _claimRewards) external claimRewards(_claimRewards, msg.sender) returns (uint _amountUnit) {
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		ICToken cToken = ICToken(internalUnderlyingAssetAddress);
		internalHarvestToTreasury(cToken);
		uint contractBalance = cToken.balanceOf(address(this));
		uint cTokenOut = contractBalance.mul(_amountWrappedToken).div(internalTotalSupply);
		internalBalanceOf[msg.sender] = internalBalanceOf[msg.sender].sub(_amountWrappedToken);
		internalTotalSupply = internalTotalSupply.sub(_amountWrappedToken);
		IERC20(address(cToken)).safeTransfer(_to, cTokenOut);
		_amountUnit = cTokenOut.mul(cToken.exchangeRateStored()).div(1 ether);
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