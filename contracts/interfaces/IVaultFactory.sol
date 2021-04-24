pragma experimental ABIEncoderV2;
pragma solidity >=0.6.0;
import "../VaultFactory/VaultFactoryData.sol";

interface IVaultFactory {
	function vaultsLength(address _owner) external view returns(uint);
	function YTvaultsLength(address _owner) external view returns(uint);
	function allVaults(address _owner) external view returns(VaultFactoryData.Vault[] memory _vaults);
	function liquidationsLength() external view returns (uint);
	function YTLiquidationsLength() external view returns (uint);
	//-----------------------------------------V-a-u-l-t---M-a-n-a-g-e-m-e-n-t-----------------------------
	//----------------------------v-i-e-w-s----------------------------
	function wrapperToUnderlyingAsset(address _wrapeprAddress) external view returns (address);
	function fixCapitalPoolToWrapper(address _fixCapitalPoolAddress) external view returns (address);
	function shortInterestAllDurations(address _wrapper) external view returns (uint);
	function VaultHealthAddress() external view returns (address);
	//-----------vault-related-views-----
	function revenue(address _asset) external view returns (uint);
	function vaults(address _owner, uint _index) external view returns (
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		uint amountBorrowed
	);
	function Liquidations(uint _index) external view returns (
		address vaultOwner,
		address assetSupplied,
		address assetBorrowed,
		uint amountBorrowed,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
	);
	//-------------YT-vault-related-views-----------
	function YTrevenue(address _asset) external view returns (uint yield, int bond);
	function YTvaults(address _owner, uint _index) external view returns (
		address FCPsupplied,
		address FCPborrowed,
		uint yieldSupplied,
		int bondSupplied,
		uint amountBorrowed
	);
	function YTLiquidations(uint _index) external view returns (
		address vaultOwner,
		address FCPsupplied,
		address FCPborrowed,
		int bondRatio,
		uint amountBorrowed,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
	);
	//---------------------------n-o-r-m-a-l---v-a-u-l-t-s--------------------------
	function openVault(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external;
	function closeVault(uint _index, address _to) external;
	function remove(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external;
	function deposit(address _owner, uint _index, uint _amount) external;
	function borrow(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external;
	function repay(address _owner, uint _index, uint _amount) external;
	//---------------------------Y-T---v-a-u-l-t-s---------------------------------
	function openYTVault(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external;
	function closeYTVault(uint _index, address _to) external;
	function YTremove(
		uint _index,
		uint _amountYield,
		int _amountBond,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external;
	function YTdeposit(address _owner, uint _index, uint _amountYield, int _amountBond) external;
	function YTborrow(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external;
	function YTrepay(address _owner, uint _index, uint _amount) external;
	//----------------------------------------------L-i-q-u-i-d-a-t-i-o-n-s------------------------------------------
	function claimRebate(address _asset) external;
	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _amtIn) external;
	function bidOnLiquidation(uint _index, uint _bid, uint _amtIn) external;
	function claimLiquidation(uint _index, address _to) external;
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxIn, uint _minOut, address _to) external;
	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external;
	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external;
	//----------------------------------------------Y-T-V-a-u-l-t--L-i-q-u-i-d-a-t-i-o-n-s------------------------------------------
	function claimYTRebate(address _asset) external;
	function auctionYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _bidYield, int _minBondRatio, uint _amtIn) external;
	function bidOnYTLiquidation(uint _index, uint _bidYield, uint _amtIn) external;
	function claimYTLiquidation(uint _index, address _to) external;
	function instantYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _maxIn, uint _minOut, int _minBondRatio, address _to) external;
	function partialYTLiquidationSpecificIn(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _in, uint _minOut, int _minBondRatio, address _to) external;
	function partialYTLiquidationSpecificOut(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _out, int _minBondRatio, uint _maxIn, address _to) external;
	//--------------------------------------------a-d-m-i-n---------------------------------------------
	function setLiquidationRebate(uint _rebateBips) external;
	function whitelistWrapper(address _wrapeprAddress) external;
	function whitelistAsset(address _assetAddress) external;
	function whitelistFixCapitalPool(address _fixCapitalPoolAddress) external;
	function claimRevenue(address _asset) external;
	function claimYTRevenue(address _FCP, int _bondIn) external;
}