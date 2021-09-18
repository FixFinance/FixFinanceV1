// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/ICToken.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "./CTokenWrapperData.sol";

contract CTokenWrapperInternals is CTokenWrapperData {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;

	/*
		@Description: get the ratio of underlyingAsset / wrappedAsset
	*/
	function getRatio() internal view returns (uint) {
		uint _totalSupply = internalTotalSupply;	
		uint _prevRatio = internalPrevRatio;
		ICToken underlying = ICToken(internalUnderlyingAssetAddress);
		uint contractBalance = underlying.balanceOf(address(this));
		uint exchangeRate = underlying.exchangeRateStored();
		uint contractControlled = contractBalance.mul(exchangeRate) / (1 ether);
		uint nonFeeAdjustedRatio = uint(1 ether).mul(contractControlled).div(_totalSupply);
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

}