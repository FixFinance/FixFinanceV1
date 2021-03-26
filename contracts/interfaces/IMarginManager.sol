pragma experimental ABIEncoderV2;
pragma solidity >=0.6.0;
import "../MarginManager/MarginManagerData.sol";

interface IMarginManager {
	function vaultsLength(address _owner) external view returns(uint);
	function allVaults(address _owner) external view returns(MarginManagerData.Vault[] memory _vaults);
	function liquidationsLength() external view returns (uint);
	//-----------------------------------------V-a-u-l-t---M-a-n-a-g-e-m-e-n-t-----------------------------
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
	function wrapperToUnderlyingAsset(address _wrapeprAddress) external view returns (address);
	function capitalHandlerToWrapper(address _capitalHandlerAddress) external view returns (address);
	function shortInterestAllDurations(address _wrapper) external view returns (uint);
	function revenue(address _asset) external view returns (uint);
	function vaults(address _owner, uint _index) external view returns (
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		uint amountBorrowed
	);
	function Liquidations(uint _index) external view returns (
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
	);
	function VaultHealthAddress() external view returns (address);
	//----------------------------------------------L-i-q-u-i-d-a-t-i-o-n-s------------------------------------------
	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _minOut) external;
	function bidOnLiquidation(uint _index, uint _bid) external;
	function claimLiquidation(uint _index, address _to) external;
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxBid, uint _minOut, address _to) external;
	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external;
	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external;
	//--------------------------------------------a-d-m-i-n---------------------------------------------
	function whitelistWrapper(address _wrapeprAddress) external;
	function whitelistAsset(address _assetAddress) external;
	function whitelistCapitalHandler(address _capitalHandlerAddress) external;
	function claimRevenue(address _asset, uint _amount) external;
}