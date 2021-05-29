// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IDBSFYTVaultManagerFlashReceiver {
	function onFlashLoan(
		address _vaultOwner,
		address _prevStateFCPSupplied,
		address _prevStateFCPBorrowed,
		uint _prevStateYieldSupplied,
		int _prevStateBondSupplied,
		int _changeBorrowedPrevDebtAsset,
		bytes calldata _data
	) external returns (bool);
}