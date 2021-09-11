// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;
import "../VaultFactory/DifferentBaseSF/DBSFVaultFactoryData.sol";

interface IDBSFVaultFactory {
	event OpenVault(address indexed owner, uint index);

	event CloseVault(address indexed owner, uint index);

	event AdjustVault(address indexed owner, uint index);

	event AuctionLiquidation(
		address indexed vaultOwner,
		uint vaultIndex,
		uint liquidationIndex
	);

	event BidOnLiquidation(uint liquidationIndex);

	event ClaimLiquidation(uint liquidationIndex);

	event InstantLiquidation(address indexed owner, uint index);

	event ClaimRebate(address indexed owner, address asset);

	event OpenYTVault(address indexed owner, uint index);

	event CloseYTVault(address indexed owner, uint index);

	event AdjustYTVault(address indexed owner, uint index);

	event AuctionYTLiquidation(
		address indexed YTvaultOwner,
		uint YTvaultIndex,
		uint YTliquidationIndex
	);

	event InstantYTLiquidation(address indexed owner, uint index);

	event BidOnYTLiquidation(uint YTliquidationIndex);

	event ClaimYTLiquidation(uint YTliquidationIndex);

	event ClaimYTRebate(address indexed owner, address FCPaddress);

	event TransferVault(
		address indexed prevOwner,
		uint prevIndex,
		address indexed newOwner,
		bool isYTVault
	);

	function vaultsLength(address _owner) external view returns(uint);
	function YTvaultsLength(address _owner) external view returns(uint);
	function allVaults(address _owner) external view returns(DBSFVaultFactoryData.Vault[] memory _vaults);
	function liquidationsLength() external view returns (uint);
	function YTLiquidationsLength() external view returns (uint);
	//-----------------------------------------V-a-u-l-t---M-a-n-a-g-e-m-e-n-t-----------------------------
	//----------------------------v-i-e-w-s----------------------------
	function shortInterestAllDurations(address _wrapper) external view returns (uint);
	function VaultHealthAddress() external view returns (address);
	//-----------vault-related-views-----
	function revenue(address _asset) external view returns (uint);
	function liquidationRebates(address _owner, address _asset) external view returns(uint);
	function vaults(address _owner, uint _index) external view returns (
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		uint amountBorrowed,
		uint amountSFee,
		uint64 timestampOpened,
		uint64 stabilityFeeAPR
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
	function YTrevenue(address _FCPaddress) external view returns (uint yield, int bond);
	function YTLiquidationRebates(address _owner, address _FCP) external view returns(uint yield, int bond);
	function YTvaults(address _owner, uint _index) external view returns (
		address FCPsupplied,
		address FCPborrowed,
		uint yieldSupplied,
		int bondSupplied,
		uint amountBorrowed,
		uint amountSFee,
		uint64 timestampOpened,
		uint64 stabilityFeeAPR
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
	function adjustVault(
		address _owner,
		uint _index,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		int128[3] calldata _multipliers,
		bytes calldata _data,
		address _receiverAddr
	) external;
	function closeVault(uint _index, address _to) external;
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
	function adjustYTVault(
		address _owner,
		uint _index,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		int128[3] calldata _multipliers,
		bytes calldata _data,
		address _receiverAddr
	) external;
	function closeYTVault(uint _index, address _to) external;
	//--------------------------------f-o-r---b-o-t-h---s-t-a-n-d-a-r-d---v-a-u-l-t-s---a-n-d---Y-T-v-a-u-l-t-s---------------
	function transferVault(uint _index, address _to, bool _isYTVault) external;
	//----------------------------------------------L-i-q-u-i-d-a-t-i-o-n-s------------------------------------------
	function claimRebate(address _asset) external;
	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _amtIn) external;
	function bidOnLiquidation(uint _index, uint _bid, uint _amtIn) external;
	function claimLiquidation(uint _index, address _to) external;
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxIn, uint _minOut, address _to) external;
	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external;
	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external;
	//----------------------------------------------Y-T-V-a-u-l-t--L-i-q-u-i-d-a-t-i-o-n-s------------------------------------------
	function claimYTRebate(address _FCPaddress) external;
	function auctionYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _bidYield, int _minBondRatio, uint _amtIn) external;
	function bidOnYTLiquidation(uint _index, uint _bidYield, uint _amtIn) external;
	function claimYTLiquidation(uint _index, address _to) external;
	function instantYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _maxIn, uint _minOut, int _minBondRatio, address _to) external;
	function partialYTLiquidationSpecificIn(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _in, uint _minOut, int _minBondRatio, address _to) external;
	function partialYTLiquidationSpecificOut(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _out, int _minBondRatio, uint _maxIn, address _to) external;
	//--------------------------------------------a-d-m-i-n---------------------------------------------
	function registerAsDistributionAccount(address _wrapperAddress) external;
	function setLiquidationRebate(uint _rebateBips) external;
	function claimRevenue(address _asset) external;
	function claimYTRevenue(address _FCP, int _bondIn) external;
}