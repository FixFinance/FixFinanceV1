pragma solidity >=0.6.5 <0.7.0;

import "../interfaces/IVaultHealth.sol";

contract MarginManagerData {
	uint internal constant TOTAL_BASIS_POINTS = 10_000;

	int128 internal constant ABDK_1 = 1<<64;

	struct Vault {
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		uint amountBorrowed;
	}

	struct Liquidation {
		address vaultOwner;
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		uint amountBorrowed;
		address bidder;
		uint bidAmount;
		uint bidTimestamp;
	}

	uint internal constant MAX_TIME_TO_MATURITY = 7 days;

	uint internal constant CRITICAL_TIME_TO_MATURITY = 1 days;

	uint internal constant AUCTION_COOLDOWN = 10 minutes;

	//acts as a wrapper whitelist
	//wrapper => underlying asset
	mapping(address => address) internal _wrapperToUnderlyingAsset;

	//acts as a whitelist for ZCBs & YTs that may be supplied as collateral
	//capitalHandler => wrapper
	mapping(address => address) internal _capitalHandlerToWrapper;

	//underlying asset => short interest
	mapping(address => uint) internal _shortInterestAllDurations;

	//owner => asset => amount
	mapping(address => mapping(address => uint)) internal _liquidationRebates;

	//asset => amount
	mapping(address => uint) internal _revenue;

	//user => vault index => vault
	mapping(address => Vault[]) internal _vaults;

	/*
		Basis points of surplus collateral over bid which is
		retained by the owner of the liquidated vault
	*/
	uint internal _liquidationRebateBips;

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