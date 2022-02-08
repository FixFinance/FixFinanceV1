// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../helpers/Ownable.sol";
import "../interfaces/IOrderbookExchange.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IOrganizer.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../oracle/interfaces/IOracleContainer.sol";
import "./VaultHealthDelegateParent.sol";


contract VaultHealthDelegate1 is VaultHealthDelegateParent {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	/*
		@Description: find description in VaultHealth contract
	*/
	function setCollateralizationRatios(address _wrapperAddress, uint120 _upper, uint120 _lower, uint120 _liqBonus, uint120 _liqProtocolFee) external onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		require(_upper > uint(_liqBonus).add(uint(_liqProtocolFee)).add(uint(MIN_THRESHOLD) + uint(ABDK_1)));
		//ensure that the contract at _wrapperAddress is not a fix capital pool contract
		require(IOrganizer(organizerAddress).fixCapitalPoolToWrapper(_wrapperAddress) == address(0));
		upperCollateralizationRatio[_wrapperAddress] = _upper;
		lowerCollateralizationRatio[_wrapperAddress] = _lower;
		liquidatorBonus[_wrapperAddress] = _liqBonus;
		protocolLiqFee[_wrapperAddress] = _liqProtocolFee;
	}

	/*
		@Description: admin may set the vaules in the RateThreshold mappings

		@param address _wrapperAddress: the wrapper asset for which to set the a collateralisation ratio
		@param uint120 _upper: the upper rate threshold multiplier
			in ABDK64.64 format
		@param uint120 _lower: the lower rate threshold multiplier
			in ABDK64.64 format
	*/
	function setRateThresholds(address _wrapperAddress, uint120 _upper, uint120 _lower) external onlyOwner {
		require(_upper >= _lower && _lower > ABDK_1);
		//ensure that the contract at _wrapperAddress is not a fix capital pool contract
		require(IOrganizer(organizerAddress).fixCapitalPoolToWrapper(_wrapperAddress) == address(0));
		upperRateThreshold[_wrapperAddress] = _upper;
		lowerRateThreshold[_wrapperAddress] = _lower;
	}

	/*
		@Description: admin may set the organizer contract address
	*/
	function setOrganizerAddress(address _organizerAddress) external onlyOwner {
		require(organizerAddress == address(0));
		organizerAddress = _organizerAddress;
	}

	/*
		@Description: admin may set the maximum short interest for bonds of any maturity for a specific asset

		@param address _underlyingAssetAddress: the address of the underlying asset for which to set a short interest cap
		@param uint _maximumShortInterest: the maximum amount of units of the underlying asset that may sold short via ZCBs
	*/
	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external onlyOwner {
		maximumShortInterest[_underlyingAssetAddress] = _maximumShortInterest;
	}

	/*
		@Description: admin may set the minimum amount by which the rate for an asset is adjusted when calculating
			collalteralization requirements for the upper and lower limits
	
		@param address _underlyingAssetAddress: the address of the wrapper asset for which to set the minimum rate adjustment
		@param uint120 _upperMinimumRateAdjustment: the new upper minimum rate adjustment for _wrapperAsset
		@param uint120 _lowerMinimumRateAdjustment: the new lower minimum rate adjustment for _wrapperAsset
	*/
	function setMinimumRateAdjustments(address _wrapperAddress, uint120 _upperMinimumRateAdjustment, uint120 _lowerMinimumRateAdjustment) external onlyOwner {
		upperMinimumRateAdjustment[_wrapperAddress] = _upperMinimumRateAdjustment;
		lowerMinimumRateAdjustment[_wrapperAddress] = _lowerMinimumRateAdjustment;
	}
}