// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IWrapper.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IInfoOracle.sol";

interface IOrderbookExchange {

	function deposit(uint _amountYield, int _amountBond) external;
	function withdraw(uint _amountYield, int _amountBond) external;
	function limitSellZCB(uint _amount, uint _maturityConversionRate, uint _hintID, uint _maxSteps) external;
	function limitSellYT(uint _amount, uint _maturityConversionRate, uint _hintID, uint _maxSteps) external;
	function modifyZCBLimitSell(int _amount, uint _targetID, uint _hintID, uint _maxSteps, bool _removeBelowMin) external returns(int change);
	function modifyYTLimitSell(int _amount, uint _targetID, uint _hintID, uint _maxSteps, bool _removeBelowMin) external returns(int change);
	function marketBuyYT(
		uint _amountYT,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external returns (uint YTbought,uint ZCBsold);
	function marketSellYT(
		uint _amountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external returns(uint ZCBbought, uint YTsold);
	function marketBuyZCB(
		uint _amountZCB,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external returns(uint ZCBbought, uint YTsold);
	function marketSellZCB(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external returns(uint YTbought, uint ZCBsold);
	function marketSellZCBtoU(
		uint _amountZCB,
		uint _maxMaturityConversionRate,
		uint _maxCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external returns(uint YTbought, uint ZCBsold);
	function marketSellUnitYTtoU(
		uint _unitAmountYT,
		uint _minMaturityConversionRate,
		uint _minCumulativeMaturityConversionRate,
		uint16 _maxIterations,
		bool _useInternalBalances
	) external returns(uint ZCBbought, uint YTsold);


	//--------------v-i-e-w-s------------------
	function YieldDeposited(address _depositor) external view returns(uint);
	function BondDeposited(address _depositor) external view returns(int);
	function lockedYT(address _depositor) external view returns(uint);
	function lockedZCB(address _depositor) external view returns(uint);
	function YTSells(uint _ID) external view returns(
		address maker,
		uint amount,
		uint maturityConversionRate,
		uint nextID
	);
	function ZCBSells(uint _ID) external view returns(
		address maker,
		uint amount,
		uint maturityConversionRate,
		uint nextID
	);
	function headYTSellID() external view returns(uint ID);
	function headZCBSellID() external view returns(uint ID);
	function FCP() external view returns(IFixCapitalPool);
	function wrapper() external view returns(IWrapper);
	function IORC() external view returns(IInfoOracle);
	function maturity() external view returns(uint40);
	function YieldRevenue() external view returns(uint);
	function BondRevenue() external view returns(int);


	//------r-a-t-e---o-r-a-c-l-e------------
	function forceRateDataUpdate() external;
	function setOracleMCR(uint _MCR) external;
	//------r-a-t-e---o-r-a-c-l-e---v-i-e-w-s------------
	function impliedYieldToMaturity() external view returns (uint yieldToMaturity);
	function getAPYFromOracle() external view returns (int128 APY);
	function getImpliedMCRFromOracle() external view returns(uint impliedMCR);
	function getOracleData() external view returns (
		uint[31] memory _impliedMCRs,
		uint _lastDatapointCollection,
		uint _oracleMCR,
		uint8 _toSet
	);

}