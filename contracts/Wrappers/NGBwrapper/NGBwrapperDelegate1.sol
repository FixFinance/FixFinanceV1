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



}