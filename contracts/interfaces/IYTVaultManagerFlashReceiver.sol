// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

interface IYTVaultManagerFlashReceiver {
	function onFlashLoan(
		address _vaultOwner,
		address _prevStateFCPSupplied,
		address _prevStateFCPBorrowed,
		uint _prevStateYieldSupplied,
		int _prevStateBondSupplied,
		uint _prevStateAmountBorrowed,
		bytes calldata _data
	) external returns (bool);
}