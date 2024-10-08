// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IVaultHealth.sol";
import "../../helpers/Ownable.sol";

contract DBSFVaultFactoryData is Ownable {
	uint internal constant TOTAL_BASIS_POINTS = 10_000;

	int128 internal constant ABDK_1 = 1<<64;

	enum SUPPLIED_ASSET_TYPE {
		ASSET,
		WASSET,
		ZCB,
		INVALID
	}

	struct Vault {
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		uint amountBorrowed;
		uint amountSFee; //amount of debt at timestampOpened that was due to stability fee, < amountBorrowed
		uint64 timestampOpened;
		uint64 stabilityFeeAPR; //inflated by 32 bits
	}

	struct Liquidation {
		address vaultOwner;
		address assetSupplied;
		address assetBorrowed;
		uint amountBorrowed;
		address bidder;
		uint bidAmount;
		uint bidTimestamp;
	}

	struct YTVault {
		address FCPsupplied;
		address FCPborrowed;
		uint yieldSupplied;
		int bondSupplied;
		uint amountBorrowed;
		uint amountSFee; //amount of debt at timestampOpened that was due to stability fee, < amountBorrowed
		uint64 timestampOpened;
		uint64 stabilityFeeAPR; //inflated by 32 bits
	}

	struct YTLiquidation {
		address vaultOwner;
		address FCPsupplied;
		address FCPborrowed;
		//bondSupplied / yieldSupplied inflated by (1 ether)
		int bondRatio;
		uint amountBorrowed;
		address bidder;
		uint bidAmount;
		uint bidTimestamp;
	}

	struct YTPosition {
		uint amountYield;
		int amountBond;
	}

	uint internal constant MAX_TIME_TO_MATURITY = 7 days;

	uint internal constant CRITICAL_TIME_TO_MATURITY = 1 days;

	uint internal constant AUCTION_COOLDOWN = 10 minutes;

	uint64 internal constant NO_STABILITY_FEE = 1 << 32;

	//underlying asset => short interest
	mapping(address => uint) internal _shortInterestAllDurations;

	//owner => asset => amount
	mapping(address => mapping(address => uint)) internal _liquidationRebates;

	//owner => asset => YTposition
	mapping(address => mapping(address => YTPosition)) internal _YTLiquidationRebates;

	//FCP => YTPosition
	mapping(address => YTPosition) internal _YTRevenue;

	mapping(address => YTPosition) internal _YTRevenueOwnerSubAcct;

	//asset => amount
	mapping(address => uint) internal _revenue;

	mapping(address => uint) internal _revenueOwnerSubAcct;

	//user => vault index => vault
	mapping(address => Vault[]) internal _vaults;

	//user => vault index => vault
	mapping(address => YTVault[]) internal _YTvaults;

	address internal _infoOracleAddress;

	/*
		Basis points of surplus collateral over bid which is
		retained by the owner of the liquidated vault
	*/
	uint internal _liquidationRebateBips;

	Liquidation[] internal _Liquidations;

	YTLiquidation[] internal _YTLiquidations;

	IVaultHealth internal vaultHealthContract;
}