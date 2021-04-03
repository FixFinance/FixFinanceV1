pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../libraries/SafeMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IMarginManager.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./MarginManagerData.sol";

contract MarginManager is MarginManagerData, IMarginManager, Ownable {
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
		address vaultOwner,
		address assetSupplied,
		address assetBorrowed,
		uint amountBorrowed,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
	) {
		Liquidation memory lq = _Liquidations[_index];
		vaultOwner = lq.vaultOwner;
		assetSupplied = lq.assetSupplied;
		assetBorrowed = lq.assetBorrowed;
		amountBorrowed = lq.amountBorrowed;
		bidder = lq.bidder;
		bidAmount = lq.bidAmount;
		bidTimestamp = lq.bidTimestamp;
	}

	function VaultHealthAddress() external view override returns (address) {
		return address(vaultHealthContract);
	}

	//------------------------------------vault management-----------------------------------

	/*
		@Description: create a new vault, deposit some asset and borrow some ZCB from it

		@param address _assetSupplied: the asset that will be used as collateral
			this asset may be a ZCB or any other asset that is whitelisted
		@param address _assetBorrowed: the ZCB that is borrowed from the new vault
`		@param uint _amountSupplied: the amount of _assetSupplied that is to be posed as collateral
		@param uint _amountBorrowed: the amount of _assetBorrowed to borrow
		@param uint _priceMultiplier: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the cross asset price
			of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the supplied
			asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the borrow
			asset decreases by a factor of _borrowRateChange
			(in ABDK format)
	*/
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

	/*
		@Description: fully repay a vault and withdraw all collateral

		@param uint _index: the vault to close is at vaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeVault(uint _index, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"closeVault(uint256,address)",
			_index,
			_to
		));
		require(success);
		emit CloseVault(msg.sender, _index);
	}

	/*
		@Description: withdraw collateral from an existing vault

		@param uint _index: the vault to close is at vaults[msg.sender][_index]
		@param uint _amount: the amount of the supplied asset to remove from the vault
		@param address _to: the address to which to send the removed collateral
		@param uint _priceMultiplier: a multiplier > 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			cross asset price of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			rate on the supplied asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			rate on the borrow asset decreases by a factor of _borrowRateChange
			(in ABDK format)
	*/
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

	/*
		@Description: deposit vollateral into an exiting vault

		@param address _owner: the owner of the vault to which to supply collateral
		@param uint _index: the index of the vault in vaults[_owner] to which to supply collateral
		@param uint _amount: the amount of the supplied asset to provide as collateral to the vault
	*/
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

	/*
		@Description: withdraw more of the borrowed asset from an existing vault

		@param uint _index: the index of the vault in vaults[msg.sender] to which to supply collateral
		@param uint _amount: the amount of the borrowed asset to withdraw from the vault
		@param address _to: the address to which to send the newly borrowed funds
		@param uint _priceMultiplier: a multiplier > 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			cross asset price of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			rate on the supplied asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			rate on the borrow asset decreases by a factor of _borrowRateChange
			(in ABDK format)
	*/
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

	/*
		@Description: repay the borrowed asset back into a vault

		@param address _owner: the owner of the vault to which to reapy
		@param uint _index: the index of the vault in vaults[_owner] to which to repay
		@param uint _amount: the amount of the borrowed asset to reapy to the vault
	*/
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

	/*
		@Description: send a vault that is under the upper collateralization limit to the auction house

		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _bid: the first bid (in _assetSupplied) made by msg.sender
		@param uint _maxIn: the maximum amount of _assetBorrowed to send in
	*/
	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _maxIn) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"auctionLiquidation(address,uint256,address,address,uint256,uint256)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_bid,
			_maxIn
		));
		require(success);
	}

	/*
		@Description: place a new bid on a vault that has already begun an auction

		@param uint _index: the index in _Liquidations[] of the auction
		@param uint  _bid: the amount of the supplied asset that the liquidator wishes to receive
			in reward if the liquidator wins this auction
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnLiquidation(uint _index, uint _bid, uint _amtIn) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"bidOnLiquidation(uint256,uint256,uint256)",
			_index,
			_bid,
			_amtIn
		));
		require(success);
	}

	/*
		@Description: claim the collateral of a vault from an auction that was won by msg.sender

		@param uint _index: the index in Liquidations[] of the auction
		@param address _to: the address to which to send the proceeds
	*/
	function claimLiquidation(uint _index, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"claimLiquidation(uint256,address)",
			_index,
			_to
		));
		require(success);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the MarginManager
			keep solvency in the event of a market crisis
			this function is used when a liquidator would like to liquidate the entire vault
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _maxBid: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param uint _minOut: the minimum amount of assetSupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
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

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the MarginManager
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by providing a specific
			amount of assetBorrowed and receiving the corresponding amount of assetSupplied
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _in: the amount of assetBorrowed to supply to the vault
		@param uint _minOut: the minimum amount of assetSupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
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

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the MarginManager
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by receiving a specific
			amount of assetSupplied and sending the corresponding amount of assetBorrowed
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _ouot: the amount of assetSupplied to receive from the vault
		@param uint _maxIn: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param address _to: the address to which to send all of the collateral from the vault
	*/
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


	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their vault(s) were liquidated

		@param address _asset: the address of the asset for which to claim rebated collateral
	*/
	function claimRebate(address _asset) external override {
		uint amt = _liquidationRebates[msg.sender][_asset];
		IERC20(_asset).transfer(msg.sender, amt);
		delete _liquidationRebates[msg.sender][_asset];
	}

	//-------------------------------------a-d-m-i-n---m-a-n-a-g-e-m-e-n-t----------------------------------------------

	/*
		@Description: admin may call this function to allow a specific wrapped asset to be provided as collateral

		@param address _wrapperAddress: address of the wrapper asset to whitelist
	*/
	function whitelistWrapper(address _wrapeprAddress) external override onlyOwner {
		_wrapperToUnderlyingAsset[_wrapeprAddress] = IWrapper(_wrapeprAddress).underlyingAssetAddress();
	}

	/*
		@Description: admin may call this function to allow a non wrapped asset to be provided as collateral

		@param address _asset: address of the asset that will be allows to be provided as collateral
	*/
	function whitelistAsset(address _assetAddress) external override onlyOwner {
		//all non wrapped assets have a pair value of address(1) in the _wrapperToUnderlyingAsset mapping
		_wrapperToUnderlyingAsset[_assetAddress] = address(1);
	}

	/*
		@Description: admin may call this function to allow a specific ZCB to be provided as collateral

		@param address _capitalHandlerAddress: address of the ZCB to whitelist
	*/
	function whitelistCapitalHandler(address _capitalHandlerAddress) external override onlyOwner {
		_capitalHandlerToWrapper[_capitalHandlerAddress] = address(ICapitalHandler(_capitalHandlerAddress).wrapper());
	}

	/*
		@Description: admin may call this function to set the percentage of excess collateral that is retained
			by vault owners in the event of a liquidation

		@param uint _rebateBips: the percentage (in basis points) of excess collateral that is retained
			by vault owners in the event of a liquidation
	*/
	function setLiquidationRebate(uint _rebateBips) external override onlyOwner {
		require(_rebateBips <= TOTAL_BASIS_POINTS);
		_liquidationRebateBips = _rebateBips;
	}

	/*
		@Description: admin may call this function to claim liquidation revenue

		@address _asset: the address of the asset for which to claim revenue
		@address _amount: the amount of revenue (in _asset) to claim
	*/
	function claimRevenue(address _asset, uint _amount) external override onlyOwner {
		require(_revenue[_asset] >= _amount);
		IERC20(_asset).transfer(msg.sender, _amount);
		_revenue[_asset] -= _amount;
	}
}

