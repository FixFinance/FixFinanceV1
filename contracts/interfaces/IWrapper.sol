// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./IERC20.sol";
import "./IERC3156FlashLender.sol";

interface IWrapper is IERC20, IERC3156FlashLender {
	function underlyingAssetAddress() external view returns(address);
	function underlyingIsStatic() external view returns(bool);
	function infoOracleAddress() external view returns(address);

	function depositUnitAmount(address _to, uint _amount) external returns (uint _amountWrapped);
	function depositWrappedAmount(address _to, uint _amount) external returns (uint _unitAmount);
	function withdrawUnitAmount(address _to, uint _amount, bool _claimRewards) external returns (uint _amountWrapped);
	function withdrawWrappedAmount(address _to, uint _amount, bool _claimRewards) external returns (uint _unitAmount);

	function forceHarvest() external;

	function lastUpdate() external view returns (uint timestamp);
	function UnitAmtToWrappedAmt_RoundDown(uint _unitAmount) external view returns (uint _amountWrapped);
	function UnitAmtToWrappedAmt_RoundUp(uint _unitAmount) external view returns (uint _amountWrapped);
	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrapped) external view returns (uint _unitAmount);
	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrapped) external view returns (uint _unitAmount);
	function getStatus() external view returns (uint updateTimestamp, uint ratio);

	function flashLoanFee() external view returns(uint256);

	//---Distribution-of-Rewards-in-Seperate-Assets-----
	function forceRewardsCollection() external;
	function numRewardsAssets() external view returns(uint);
	function rewardsAssets(uint _index) external view returns(address);
	function immutableRewardsAssets(uint _index) external view returns(address);
	function prevContractBalance(uint _index) external view returns(uint);
	function totalRewardsPerWasset(uint _index) external view returns(uint);
	function prevTotalRewardsPerWasset(uint _index, address _wassetHolder) external view returns(uint);
	//---s-u-b-a-c-c-o-u-n-t---d-i-s-t-r-i-b-u-t-i-o-n---m-o-d-e-l-----
	function registerAsDistributionAccount() external;
	function delistDistributionAccount() external;
	function editSubAccountPosition(bool _claimRewards, address _subAccount, address _FCPaddr, int changeYield, int changeBond) external;
	function forceClaimSubAccountRewards(address _distributionAccount, address _subAccount, address _FCPaddr) external;
    function FCPDirectClaimSubAccountRewards(bool _inPayoutPhase, bool _claimRewards, address _subAcct, uint _yield, uint _wrappedClaim) external;
    function FCPDirectDoubleClaimSubAccountRewards(
        bool _inPayoutPhase,
        bool _claimRewards,
        address[2] calldata _subAccts,
        uint[2] calldata _yieldArr,
        uint[2] calldata _wrappedClaims
    ) external;
	function isDistributionAccount(address _addr) external view returns(bool);
	function totalUnspentDistributionAccountRewards(uint _index) external view returns(uint);
	function distributionAccountRewards(uint _index, address _distributionAccount) external view returns(uint);
	function hasClaimedAllYTRewards(address _distributionAccount, address _subAccount, address _FCPaddr) external view returns(bool);
	function subAccountPrevTotalReturnsPerWasset(uint _index, address _distributionAccount, address _subAccount, address _FCPaddr) external view returns(uint);
	function subAccountPositions(address _distributionAccount, address _subAccount, address _FCPaddr) external view returns(
		uint yield,
		int bond
	);
}