// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IInfoOracle.sol";

contract OrderbookData {

	event MakeLimitSellZCB(
		address indexed maker,
		uint prevID,
		uint amount,
		uint maturityConversionRate
	);

	event MakeLimitSellYT(
		address indexed maker,
		uint prevID,
		uint amount,
		uint maturityConversionRate
	);

	event ModifyOrder(
		uint orderID,
		int change
	);

	event MarketBuyYT(
		address indexed taker,
		uint newYTSellHeadID,
		uint headAmount
	);

	event MarketBuyZCB(
		address indexed taker,
		uint newZCBSellHeadID,
		uint headAmount
	);

	struct LimitSellZCB {
		//same as LimitBuyYT
		address maker;
		uint amount;
		uint maturityConversionRate;
		uint nextID;
	}

	struct LimitSellYT {
		//same as LimitBuyZCB
		address maker;
		uint amount;
		uint maturityConversionRate;
		uint nextID;
	}

	mapping(address => uint) internal internalYieldDeposited;
	mapping(address => int) internal internalBondDeposited;

	/*
		amount of static YT that is being used as collateral for a limit order,
		when YT is locked lockedYT increases and YieldDeposited remains the same
	*/
	mapping(address => uint) internal internalLockedYT;
	/*
		amount of ZCB that is being used as collateral for a limit order
		when ZCB is locked lockedZCB increases and BondDeposited remains the same
	*/
	mapping(address => uint) internal internalLockedZCB;

	mapping(uint => LimitSellYT) internal internalYTSells;
	mapping(uint => LimitSellZCB) internal internalZCBSells;

	uint internal internalHeadYTSellID;
	uint internal internalHeadZCBSellID;

	//value of totalNumOrders at the time an order is created is its key in the order mapping
	uint totalNumOrders;

	IFixCapitalPool public internalFCP;
	IWrapper public internalWrapper;
	IInfoOracle public internalIORC;

	uint40 public internalMaturity;

	uint public internalYieldRevenue;
	int public internalBondRevenue;


	//--------------data for rate oracle---------------
	uint8 constant LENGTH_RATE_SERIES = 31;
	uint constant TIME_BETWEEN_DATAPOINTS = 1 minutes;
	uint constant SecondsPerYear = 31556926;
	int128 constant ABDK_1 = 1<<64;
	uint OracleMCR;
	uint[LENGTH_RATE_SERIES] impliedMCRs;
	uint40 lastDatapointCollection;
	uint8 toSet;

	//-----------admin---------------
	uint minimumOrderSize;
}