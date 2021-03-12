pragma solidity >=0.6.5 <0.7.0;

import "../interfaces/IVaultHealth.sol";

contract BondMinterData {
	uint internal constant TOTAL_BASIS_POINTS = 10_000;

	int128 internal constant ABDK_1 = 1<<64;

	struct Vault {
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		uint amountBorrowed;
	}

	struct Liquidation {
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		/*
			amountBorrowed is the one value from the Vault object not stored in liquidation
		*/
		address bidder;
		uint bidAmount;
		uint bidTimestamp;
	}

	//acts as a wrapper whitelist
	//wrapper => underlying asset
	mapping(address => address) internal _wrapperToUnderlyingAsset;

	//acts as a whitelist for ZCBs & YTs that may be supplied as collateral
	//capitalHandler => wrapper
	mapping(address => address) internal _capitalHandlerToWrapper;

	//underlying asset => short interest
	mapping(address => uint) internal _shortInterestAllDurations;

	//asset => amount
	mapping(address => uint) internal _revenue;

	//user => vault index => vault
	mapping(address => Vault[]) internal _vaults;

	Liquidation[] internal _Liquidations;

	IVaultHealth internal vaultHealthContract;

	event OpenVault(
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		uint amountBorrowed		
	);

	event CloseVault(
		address owner,
		uint index
	);

	event Remove (
		address owner,
		uint index,
		uint amount
	);

	event Deposit (
		address owner,
		uint index,
		uint amount
	);

	event Borrow (
		address owner,
		uint index,
		uint amount
	);

	event Repay (
		address owner,
		uint index,
		uint amount
	);

}