// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../helpers/Ownable.sol";

contract VaultHealthData is Ownable {

	uint internal constant SecondsPerYear = 31556926;
	uint internal constant TOTAL_BASIS_POINTS = 10_000;
	int128 internal constant ABDK_1 = 1<<64;

	/*
		the RateAdjuster enum holds information about how to change the APY
		when calculating required collateralisation ratios.

		UPPER means that you are checking the upper collateralisation limit
		LOWER means that you are checking the lower collateralisation limit

		DEPOSIT means that you are finding the rate multiplier for a ZCB that has been supplied to a vault
		BORROW means that you are finding the rate multiplier for a ZCB that has been borrowed from a vault

		BASE means that you are not adjusting the APY to find a collateralisation limit
		BASE means that you are finding the rate multiplier to get as best an approximation of market value
			of the ZCBs as possible
	*/
	enum RateAdjuster {
		UPPER_DEPOSIT,
		LOW_DEPOSIT,
		BASE,
		LOW_BORROW,
		UPPER_BORROW
	}

	/*
		the Safety enum holds information about which collateralsation limit is in question

		as you may have inferred
		UPPER means that the upper collateralisation ratio is in use
		LOWER means that the lower collateralisation ratio is in use
	*/
	enum Safety {
		UPPER,
		LOW
	}

	/*
		When a user deposits bonds we take the Maximum of the rate shown in the oracle +
		(upper/lower)MinimumRateAdjustment[baseWrapperAsset] and the rate shown in the oracle adjusted with the
		corresponding rate threshold as the rate for which collateralization requirements
		will be calculated for the (upper/lower) limit

		When a user borrowes bonds we take the Maximum of the rate shown in the oracle -
		(upper/lower)MinimumRateAdjustment[baseWrapperAsset] and the rate shown in the oracle adjusted with the
		corresponding rate threshold as the rate for which collateralization requirements
		will be calculated for the (upper/lower) limit
	*/
	mapping(address => uint120) internal upperMinimumRateAdjustment;
	mapping(address => uint120) internal lowerMinimumRateAdjustment;

	/*
		The Collateralisation Ratio mappings hold information about the % which any vault
		containing a asset must be overcollateralised.

		For example if
		upperCollateralizationRatio[_assetSupplied] == 1.0 and
		upperCollateralizationRatio[_assetBorrowed] == 1.5

		the total overcollateralisation % required for the vault due to volatility of asset prices
		is (1.0 * 1.5 - 1.0) == 50% for the upper collateralization limit

		these mappings take in an underlying asset, they do not account for overcollateralisation
		required due to rate volatility

		When ZCBs are used in a vault to find the collateralization ratio due to underlying asset
		you must find UpperCollateralzationRatio[org.fixCapitalPoolToWrapper(_ZCBaddress)]

		In ABDK64.64 format
	*/
	mapping(address => uint120) internal lowerCollateralizationRatio;
	mapping(address => uint120) internal upperCollateralizationRatio;


	/*
		Because rates are always over 1.0 (meaning the % notation of the rate is always positive)
		the rate thresholds refer to the % change in the rate minus 1.
		All rate thresholds must be above 1.0 as well,to get the resultant threshold adjusted rate for
		borrowing we find 1 + (rate - 1)/threshold
		to get the resultatn threshold adjusted rate for depositing we find
		1 + (rate - 1)*threshold
		For example if there is a rate treshold of 1.25 and the current rate for that asset is 
		3% the rate used when calculating borrow requirements for that asset will be
		(1.03-1) / 1.25 == 3% / 1.25 == 2.4%
		To calculate the rate for deposit calculations for that asset we would do the following
		(1.03-1) * 1.25 == 3% * 1.25 == 3.75%
	*/
	mapping(address => uint120) internal lowerRateThreshold;
	mapping(address => uint120) internal upperRateThreshold;

	/*
		Set by contract owner this mapping shows the maximum amount of any underlying asset (at all durations combined)
		that may be shorted via the VaultFactory contract
	*/
	mapping(address => uint) internal maximumShortInterest;

	/*
		To get the total liquidatorBonus multiplier get liquidatorBonus[_collateralBase] + liquidatorBonus[_debtBase]
		the liquidationBonus multiplier is used to get the amount of the collateral to give to the liquidator

		collateralToLiquidator == debtAssetFromLiquidator * debtToCollateralPrice_fromOracle * (totalLiquidatorBonus + 1)

		To get the total protocolLiqFee multiplier get protocolLiqFee[_collateralBase] + protocolLiqFee[_debtBase]
		the protocolLiqFee multiplier is used to get the amount of the collateral to give to be split between the treasury and admin

		protocolLiqFee == debtAssetFromLiquidator * debtToCollateralPrice_fromOracle * totalProtocolLiqFee
		Both liquidatorBonus and protocolLiqFee are in ABDK format
	*/
	mapping(address => uint120) internal liquidatorBonus;
	mapping(address => uint120) internal protocolLiqFee;
	uint120 internal constant MIN_THRESHOLD = uint120(ABDK_1) / 100; // 1%
	// liquidatorBonus + protocolLiqFee must always be at least 1% less than the collateralization factor for that asset

	address organizerAddress;
	address oracleContainerAddress;
}