// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../helpers/nonReentrant.sol";
import "../../helpers/Ownable.sol";

contract CTokenWrapperData is nonReentrant, Ownable {
    bytes32 constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 internalFlashLoanFee = 1000; // denominated in super bips
	//SBPS == super bips == 1/100th of a bip
	//100 * 10_000 == 1_000_000
	uint32 internal constant totalSBPS = 1_000_000;
	//totalSBPS - annualTreasuryFee(in sbps)
	uint32 internal SBPSRetained = 999_000;
	//minimum amount of interest on each harvest that should be retained for holders
	//of this token.
	//800_000 sbps == 8_000 bips == 80%
	//ex. if 1000 units of interest are generated between harvests then 800 units
	//is the minimum amount that must be retained for tokens holders thus the
	//maximum amount that may go to the treasury is 200 units
	uint32 internal constant minHarvestRetention = 800_000;
	uint internal constant ABDK_1 = 1 << 64;
	address internalUnderlyingAssetAddress;
	//amount of unit amount equivalent to (1 ether) of wrapped amount at internalLastHarvest
	uint internalPrevRatio;
	uint8 internalDecimals;
	address internalInfoOracleAddress;
	//most recent timestamp at which harvestToTreasury() was called
	uint internalLastHarvest;
	uint internalTotalSupply;
	mapping(address => uint) internalBalanceOf;
    mapping(address => mapping(address => uint256)) internalAllowance;
    string internalName;
    string internalSymbol;

    //-------G-e-n-e-r-a-l-i-z-e-d---L-i-q-u-i-d-i-t-y---M-i-n-i-n-g---R-e-w-a-r-d-s---C-a-p-t-u-r-e---M-e-c-h-a-n-i-s-m--------
	address[] internalRewardsAssets;
	address[] internalImmutableRewardsAssets;
	uint[] internalPrevContractBalance;
	uint[] internalTotalRewardsPerWasset;
	uint[] internalTRPWuponActivation; //total rewards per wasset at the time of the most recent activation
	mapping(address => uint)[] internalPrevTotalRewardsPerWasset;

	//------s-u-b-a-c-c-o-u-n-t---r-e-w-a-r-d-s---m-e-c-h-a-n-i-s-m---------

	struct SubAccountPosition {
		uint yield;
		int bond;
	}
	mapping(address => uint)[] internalDistributionAccountRewards;
	mapping(address => bool) internalIsDistributionAccount;

	//FCP direct subaccounts don't have entries in the internalSubAccountPositions mapping, those values are fetched from the FCP
	//Distribution Account => Sub Account => FCP => total bond & yield amts
	mapping(address => mapping(address => mapping(address => SubAccountPosition))) internalSubAccountPositions;
	mapping(address => mapping(address => mapping(address => bool))) internalHasClaimedAllYTrewards;
	//SubAccount Prev Total Rewards Per Wasset
	//Distribution Account => Sub Account => FCP => PTRPW
	mapping(address => mapping(address => mapping(address => uint)))[] internalSAPTRPW;
}
