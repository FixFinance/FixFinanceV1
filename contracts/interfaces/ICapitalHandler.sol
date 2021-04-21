pragma solidity >=0.6.0;
import "./IWrapper.sol";
import "./IERC20.sol";

interface ICapitalHandler {
	function wrappedTokenFree(address _owner) external view returns (uint wrappedTknFree);
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external;
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external;
	function withdrawAll(address _to, bool _unwrap) external;
	function claimBondPayout(address _to) external;
	function enterPayoutPhase() external;
	function inPayoutPhase() external view returns (bool);
	function maturity() external view returns(uint64);
	function maturityConversionRate() external view returns(uint);
	function underlyingAssetAddress() external view returns(address);
	function balanceBonds(address _owner) external view returns(int);
	function balanceYield(address _owner) external view returns(uint);
	function yieldTokenAddress() external view returns(address);
	function zeroCouponBondAddress() external view returns(address);
	function vaultFactoryAddress() external view returns(address);
	function wrapper() external view returns(IWrapper);
	function transferPosition(address _to, uint _yield, int _bond) external;
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external;

	//---------------Yield-Token---------------
	function transferYield(address _from, address _to, uint _amount) external;

	//---------------Zero-Coupon-Bond---------
	function totalBalanceZCB(address _owner) external view returns (uint);
	function transferZCB(address _from, address _to, uint _amount) external;

	//---------------Vault-Factory------------------------------
	function mintZCBTo(address _owner, uint _amount) external;
	function burnZCBFrom(address _owner, uint _amount) external;

	//----------------admin----------------------------
	function isFinalized() external view returns(bool);
	function setVaultFactoryAddress(address _vaultFactoryAddress) external;
	function finalize() external;
}