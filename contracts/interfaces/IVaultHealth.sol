// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IVaultHealth {
	//return true if collateral is above limit
	function satisfiesUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool);
	function satisfiesLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool);

	function amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view returns (uint);
	function amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view returns (uint);

	function amountBorrowedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external view returns (uint);
	function amountBorrowedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external view returns (uint);

	function YTvaultAmountBorrowedAtUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond) external view returns (uint);
	function YTvaultAmountBorrowedAtLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond) external view returns (uint);

	function YTvaultSatisfiesUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external view returns (bool);
	function YTvaultSatisfiesLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external view returns (bool);

	function vaultWithstandsChange(
		bool _reqSameBase,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _pctPriceChange,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external view returns (bool);

	function YTvaultWithstandsChange(
		bool _reqSameBase,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond,
		uint _amountBorrowed,
		uint _pctPriceChange,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external view returns (bool);	

	function maximumShortInterest(address _underlyingAssetAddress) external view returns (uint);
	function UpperCollateralizationRatio(address _wrapperAddress) external view returns(uint120);
	function LowerCollateralizationRatio(address _wrapperAddress) external view returns(uint120);
	function UpperRateThreshold(address _wrapperAddress) external view returns(uint120);
	function LowerRateThreshold(address _wrapperAddress) external view returns(uint120);
	function upperMinimumRateAdjustment(address _wrapperAddress) external view returns (uint120);
	function lowerMinimumRateAdjustment(address _wrapperAddress) external view returns (uint120);

	//-------------a-d-m-i-n---------------
	function setCollateralizationRatios(address _wrapperAddress, uint120 _upper, uint120 _lower) external;
	function setRateThresholds(address _wrapperAddress, uint120 _upper, uint120 _lower) external;
	function setOrganizerAddress(address _organizerAddress) external;
	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external;
	function setMinimumRateAdjustments(address _wrapperAddress, uint120 _upper, uint120 _lower) external;
}
