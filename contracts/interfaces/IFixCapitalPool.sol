// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IFCPFlashLender.sol";
import "./IWrapper.sol";
import "./IERC20.sol";

interface IFixCapitalPool is IFCPFlashLender {
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external;
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external;
	function withdrawAll(address _to, bool _unwrap) external;
	function claimBondPayout(address _to, bool _unwrap) external;
	function enterPayoutPhase() external;
	function transferPosition(address _to, uint _yield, int _bond) external;
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external;
	function transferYT(address _from, address _to, uint _amount) external;
	function transferZCB(address _from, address _to, uint _amount) external;

	function wrappedTokenFree(address _owner) external view returns (uint wrappedTknFree);
	function inPayoutPhase() external view returns (bool);
	function maturity() external view returns(uint40);
	function maturityConversionRate() external view returns(uint);
	function underlyingAssetAddress() external view returns(address);
	function balanceBonds(address _owner) external view returns(int);
	function balanceYield(address _owner) external view returns(uint);
	function yieldTokenAddress() external view returns(address);
	function zeroCouponBondAddress() external view returns(address);
	function whitelistedVaultFactories(address _vaultFactoryAddress) external view returns(bool whitelisted);
	function infoOracleAddress() external view returns(address);
	function wrapper() external view returns(IWrapper);
	function lastUpdate() external view returns(uint);
	function currentConversionRate() external view returns(uint);
	function totalBalanceZCB(address _owner) external view returns (uint);

	//----------------rewards-system--------
	function TotalRewardsPerWassetAtMaturity(uint _index) external view returns(uint);

	//---------------Vault-Factory------------------------------
	function mintZCBTo(address _owner, uint _amount) external;
	function burnZCBFrom(address _owner, uint _amount) external;

	//----------------admin----------------------------
	function isFinalized() external view returns(bool);
	function setVaultFactoryAddress(address _vaultFactoryAddress) external;
	function finalize() external;
}