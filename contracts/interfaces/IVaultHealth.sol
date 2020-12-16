pragma solidity >=0.6.5 <0.7.0;

interface IVaultHealth {
	//collateral above return value of this function may be withdrawn from vault
	function upperLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view returns (uint);
	//collateral must be greater than or equal to the return value to avoid liquidation
	function lowerLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view returns (uint);
}

