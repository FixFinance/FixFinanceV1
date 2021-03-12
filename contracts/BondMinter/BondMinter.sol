pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../libraries/SafeMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IBondMinter.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./BondMinterData.sol";

contract BondMinter is BondMinterData, IBondMinter, Ownable {
	using SafeMath for uint;

	address delegateAddress;

	constructor(address _vaultHealthContract, address _delegateAddress) public {
		vaultHealthContract = IVaultHealth(_vaultHealthContract);
		delegateAddress = _delegateAddress;
	}

	//-----------------------------------views-------------------------------------

	function vaultsLength(address _owner) external view override returns(uint) {
		return _vaults[_owner].length;
	}

	function allVaults(address _owner) external view override returns(Vault[] memory __vaults) {
		__vaults = _vaults[_owner];
	}

	function liquidationsLength() external view override returns (uint) {
		return _Liquidations.length;
	}

	function wrapperToUnderlyingAsset(address _wrapeprAddress) external view override returns (address) {
		return _wrapperToUnderlyingAsset[_wrapeprAddress];
	}

	function capitalHandlerToWrapper(address _capitalHandlerAddress) external view override returns (address) {
		return _capitalHandlerToWrapper[_capitalHandlerAddress];
	}

	function shortInterestAllDurations(address _wrapper) external view override returns (uint) {
		return _shortInterestAllDurations[_wrapper];
	}

	function revenue(address _asset) external view override returns (uint) {
		return _revenue[_asset];
	}

	function vaults(address _owner, uint _index) external view override returns (
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		uint amountBorrowed
		) {

		Vault memory vault = _vaults[_owner][_index];
		assetSupplied = vault.assetSupplied;
		assetBorrowed = vault.assetBorrowed;
		amountSupplied = vault.amountSupplied;
		amountBorrowed = vault.amountBorrowed;
	}

	function Liquidations(uint _index) external view override returns (
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
		) {
		
		Liquidation memory lq = _Liquidations[_index];
		assetSupplied = lq.assetSupplied;
		assetBorrowed = lq.assetBorrowed;
		amountSupplied = lq.amountSupplied;
		bidder = lq.bidder;
		bidAmount = lq.bidAmount;
		bidTimestamp = lq.bidTimestamp;
	}

	function VaultHealthAddress() external view override returns (address) {
		return address(vaultHealthContract);
	}

	//------------------------------------vault management-----------------------------------

	function openVault(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external override {

		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"openVault(address,address,uint256,uint256,uint256,int128,int128)",
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
		emit OpenVault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed);
	}

	function closeVault(uint _index, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"closeVault(uint256,address)",
			_index,
			_to
		));
		require(success);
		emit CloseVault(msg.sender, _index);
	}

	function remove(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external override {

		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"remove(uint256,uint256,address,uint256,int128,int128)",
			_index,
			_amount,
			_to,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
		emit Remove(msg.sender, _index, _amount);
	}

	function deposit(address _owner, uint _index, uint _amount) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"deposit(address,uint256,uint256)",
			_owner,
			_index,
			_amount
		));
		require(success);
		emit Deposit(_owner, _index, _amount);
	}

	function borrow(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external override {

		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"borrow(uint256,uint256,address,uint256,int128,int128)",
			_index,
			_amount,
			_to,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
		emit Borrow(msg.sender, _index, _amount);
	}

	function repay(address _owner, uint _index, uint _amount) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"repay(address,uint256,uint256)",
			_owner,
			_index,
			_amount
		));
		require(success);
		emit Repay(_owner, _index, _amount);
	}

	//----------------------------------------------_Liquidations------------------------------------------

	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _minOut) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"auctionLiquidation(address,uint256,address,address,uint256,uint256)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_bid,
			_minOut
		));
		require(success);
	}

	function bidOnLiquidation(uint _index, uint _bid) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"bidOnLiquidation(uint256,uint256)",
			_index,
			_bid
		));
		require(success);
	}

	function claimLiquidation(uint _index, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"claimLiquidation(uint256,address)",
			_index,
			_to
		));
		require(success);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit _vaults may be liquidated instantly without going through the auction process
	*/
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxBid, uint _minOut, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"instantLiquidation(address,uint256,address,address,uint256,uint256,address)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_maxBid,
			_minOut,
			_to
		));
		require(success);
	}

	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"partialLiquidationSpecificIn(address,uint256,address,address,uint256,uint256,address)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_in,
			_minOut,
			_to
		));
		require(success);
	}

	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"partialLiquidationSpecificOut(address,uint256,address,address,uint256,uint256,address)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_out,
			_maxIn,
			_to
		));
		require(success);
	}
	//--------------------------------------------management---------------------------------------------

	function whitelistWrapper(address _wrapeprAddress) external override onlyOwner {
		_wrapperToUnderlyingAsset[_wrapeprAddress] = IWrapper(_wrapeprAddress).underlyingAssetAddress();
	}

	function whitelistCapitalHandler(address _capitalHandlerAddress) external override onlyOwner {
		_capitalHandlerToWrapper[_capitalHandlerAddress] = address(ICapitalHandler(_capitalHandlerAddress).wrapper());
	}

	function claimRevenue(address _asset, uint _amount) external override onlyOwner {
		require(_revenue[_asset] >= _amount);
		IERC20(_asset).transfer(msg.sender, _amount);
		_revenue[_asset] -= _amount;
	}
}

