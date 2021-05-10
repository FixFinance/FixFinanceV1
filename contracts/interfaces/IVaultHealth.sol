// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.7.0;

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
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _pctPriceChange,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external view returns (bool);

	function YTvaultWithstandsChange(
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
	function upperMinimumRateAdjustment(address _underlyingAssetAddress) external view returns (int128);
	function lowerMinimumRateAdjustment(address _underlyingAssetAddress) external view returns (int128);

	//-------------a-d-m-i-n---------------
	function setCollateralizationRatios(address _underlyingAssetAddress, uint120 _upper, uint120 _lower) external;
	function setRateThresholds(address _underlyingAssetAddress, uint120 _upper, uint120 _lower) external;
	function setOrganizerAddress(address _organizerAddress) external;
	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external;
	function setUpperMinimumRateAdjustment(address _wrapperAddress, int128 _minimumRateAdjustment) external;
	function setLowerMinimumRateAdjustment(address _wrapperAddress, int128 _minimumRateAdjustment) external;
}
