// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../interfaces/IWrapper.sol";

contract FCPData {
	//set to true after internalMaturity
	//once true users may redeem ZCBs for underlying
	bool internalInPayoutPhase;
	//timestamp at which payout phase may be entered
	uint40 internalMaturity;
	//(1 ether) * amountUnit / wrappedToken
	uint internalMaturityConversionRate;
	IWrapper internalWrapper;
	address internalUnderlyingAssetAddress;
	/*
		These 2 mappings along with the conversion ratio between Unit amounts and
		wrapped amounts keep track of a user's balance of ZCB and YT

		internalBalanceYield refers to the amount of wrapped assets which have been credited to a user.
		When a user depsoits X amount of wrapped asset internalBalanceYield[user] += X;
		internalBalanceYield is denominated in wrapped asset amounts
		internalBalanceBonds refers to the amount of ZCBs that a user is indebted against their 
		position of wrapped assets stored in internalBalanceYield.
		The values in internalBalanceBonds may be positive or negative.
		A positive balance in internalBalanceBonds indicates that a user extra ZCB ontop of
		how ever much wrapped asset they own in internalBalanceYield.
		A negative balance in internalBalanceBonds indicates that a user is indebted ZCB against their
		wrapped assets held in internalBalanceYield.
		The current value in Uint amount of a user's balance of wrapped asset stored in internalBalanceYield 
		may never be greater than a user's negatie balance in internalBalanceBonds

		If a user would like to sell more ZCB against the underlying asset than the face unit value of
		underlying asset they must use open a vault with the VaultFactory contract to access margin
	*/
	mapping(address => int) internalBalanceBonds;
	mapping(address => uint) internalBalanceYield;
	address internalYieldTokenAddress;
	address internalZeroCouponBondAddress;
	mapping(address => bool) internalWhitelistedVaultFactories;
    address internalInfoOracleAddress;
    uint[] internalTotalRewardsPerWassetAtMaturity;
	//when isFinalized, internalWhitelistedVaultFactories mapping may not be changed
	bool internalIsFinalized;

	//----------end-overridden-data--------

	//data for flashloans
    uint256 flashLoanFee; // denominated in super bips
    //---------------add flashLoanFee into IFixCapitalPool interface------------

    bytes32 constant CALLBACK_SUCCESS = keccak256("FCPFlashBorrower.onFlashLoan");
	//SBPS == super bips == 1/100th of a bip
	//100 * 10_000 == 1_000_000
	uint32 internal constant totalSBPS = 1_000_000;
    uint256 internal constant MAX_YIELD_FLASHLOAN = 2**250 / totalSBPS;
    int256 internal constant MAX_BOND_FLASHLOAN = 2**250 / int(totalSBPS);
}