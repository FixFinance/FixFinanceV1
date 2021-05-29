// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IDBSFVaultManagerFlashReceiver {
	function onFlashLoan(
		address _vaultOwner,
		address _prevStateAssetSupplied,
		address _prevStateAssetBorrowed,
		uint _prevStateAmountSupplied,
		int _changeBorrowedPrevDebtAsset,
		bytes calldata _data
	) external returns (bool);
}