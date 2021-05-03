pragma solidity >=0.6.0 <0.7.0;

interface IVaultManagerFlashReceiver {
	function onFlashLoan(
		address _vaultOwner,
		bytes calldata _data
	) external returns (bool);
}