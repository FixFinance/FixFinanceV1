pragma solidity >=0.6.5 <0.7.0;

interface IVaultHealth {
	//return true if collateral is above upper limit
	function upperLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool);
	//return true if collateral is above middle limit
	function middleLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool);
	//return true if collateral is above lower limit
	function lowerLimitSuppliedAsset(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool);
}

