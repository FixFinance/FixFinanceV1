pragma solidity >=0.6.0;
import "./IAaveWrapper.sol";
import "./IERC20.sol";

interface ICapitalHandler is IERC20 {
	function wrappedTokenFree(address _owner) external view returns (uint wrappedTknFree);
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external;
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external;
	function withdrawAll(address _to, bool _unwrap) external;
	function claimBondPayout(address _to) external;
	function enterPayoutPhase() external;
	function mintZCBTo(address _owner, uint _amount) external;
	function transferYield(address _from, address _to, uint _amount) external;
	function inPayoutPhase() external view returns (bool);
	function maturity() external view returns(uint64);
	function maturityConversionRate() external view returns(uint);
	function aToken() external view returns(address);
	function balanceBonds(address _owner) external view returns(int);
	function balanceYield(address _owner) external view returns(uint);
	function yieldTokenAddress() external view returns(address);
	function bondMinterAddress() external view returns(address);
	function aw() external view returns(IAaveWrapper);
}