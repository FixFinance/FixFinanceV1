pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IVaultFactory.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./VaultFactoryData.sol";

contract VaultFactory is VaultFactoryData, IVaultFactory, Ownable {
	using SafeMath for uint;
	using SignedSafeMath for int;

	address delegateAddress;
	address delegate2Address;

	constructor(address _vaultHealthContract, address _delegateAddress, address _delegate2Address) public {
		vaultHealthContract = IVaultHealth(_vaultHealthContract);
		delegateAddress = _delegateAddress;
		delegate2Address = _delegate2Address;
	}

	//-----------------------------------views-------------------------------------

	function vaultsLength(address _owner) external view override returns(uint) {
		return _vaults[_owner].length;
	}

	function YTvaultsLength(address _owner) external view override returns(uint) {
		return _YTvaults[_owner].length;
	}

	function allVaults(address _owner) external view override returns(Vault[] memory __vaults) {
		__vaults = _vaults[_owner];
	}

	function liquidationsLength() external view override returns (uint) {
		return _Liquidations.length;
	}

	function YTLiquidationsLength() external view override returns (uint) {
		return _YTLiquidations.length;
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

	function YTrevenue(address _asset) external view override returns (uint yield, int bond) {
		YTPosition memory pos = _YTRevenue[_asset];
		yield = pos.amountYield;
		bond = pos.amountBond;
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

	function YTvaults(address _owner, uint _index) external view override returns (
		address CHsupplied,
		address CHborrowed,
		uint yieldSupplied,
		int bondSupplied,
		uint amountBorrowed
	) {
		YTVault memory vault = _YTvaults[_owner][_index];
		CHsupplied = vault.CHsupplied;
		CHborrowed = vault.CHborrowed;
		yieldSupplied = vault.yieldSupplied;
		bondSupplied = vault.bondSupplied;
		amountBorrowed = vault.amountBorrowed;
	}

	function YTLiquidations(uint _index) external view override returns (
		address vaultOwner,
		address CHsupplied,
		address CHborrowed,
		int bondRatio,
		uint amountBorrowed,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
	) {
		YTLiquidation memory liq = _YTLiquidations[_index];
		vaultOwner = liq.vaultOwner;
		CHsupplied = liq.CHsupplied;
		CHborrowed = liq.CHborrowed;
		bondRatio = liq.bondRatio;
		amountBorrowed = liq.amountBorrowed;
		bidder = liq.bidder;
		bidAmount = liq.bidAmount;
		bidTimestamp = liq.bidTimestamp;
	}

	function VaultHealthAddress() external view override returns (address) {
		return address(vaultHealthContract);
	}

	//--------------------------------standard vault management-----------------------------------

	/*
		@Description: create a new vault, deposit some asset and borrow some ZCB from it

		@param address _assetSupplied: the asset that will be used as collateral
			this asset may be a ZCB or any other asset that is whitelisted
		@param address _assetBorrowed: the ZCB that is borrowed from the new vault
		@param uint _amountSupplied: the amount of _assetSupplied that is to be posed as collateral
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
		@Description: deposit collateral into an exiting vault

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

	//--------------------------------------YT vault management-----------------------------------

	/*
		@Description: create a new YT vault, deposit some ZCB + YT of a CH and borrow some ZCB from it

		@param address _CHsupplied: the address of the CH contract for which to supply ZCB and YT
		@param address _CHborrowed: the CH that corresponds to theZCB that is borrowed from the new YTVault
		@param uint _yieldSupplied: the amount from the balanceYield mapping in the supplied CH contract
			that is to be supplied to the new YTVault
		@param int _bondSupplied: the amount from the balanceBonds mapping in the supplied CH contract
			that is to be supplied to the new YTVault
		@param uint _amountBorrowed: the amount of ZCB from _CHborrowed to borrow
		@param uint _priceMultiplier: a multiplier > 1
			we ensure the vault will not be sent into the liquidation zone if the cross asset price
			of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1 if _positiveBondSupplied otherwise < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the supplied
			asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the borrow
			asset decreases by a factor of _borrowRateChange
			(in ABDK format)
	*/
	function openYTVault(
		address _CHsupplied,
		address _CHborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"openYTVault(address,address,uint256,int256,uint256,uint256,int128,int128)",
			_CHsupplied,
			_CHborrowed,
			_yieldSupplied,
			_bondSupplied,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
	}

	/*
		@Description: fully repay a YT vault and withdraw all collateral

		@param uint _index: the YT vault to close is at YTvaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeYTVault(uint _index, address _to) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"closeYTVault(uint256,address)",
			_index,
			_to
		));
		require(success);
	}

	function YTremove(
		uint _index,
		uint _amountYield,
		int _amountBond,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"YTremove(uint256,uint256,int256,address,uint256,int128,int128)",
			_index,
			_amountYield,
			_amountBond,
			_to,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
	}

	function YTdeposit(address _owner, uint _index, uint _amountYield, int _amountBond) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"YTdeposit(address,uint256,uint256,int256)",
			_owner,
			_index,
			_amountYield,
			_amountBond
		));
		require(success);
	}

	function YTborrow(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"YTborrow(uint256,uint256,address,uint256,int128,int128)",
			_index,
			_amount,
			_to,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
	}

	function YTrepay(address _owner, uint _index, uint _amount) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"YTrepay(address,uint256,uint256)",
			_owner,
			_index,
			_amount
		));
		require(success);
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
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator would like to liquidate the entire vault
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _maxIn: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param uint _minOut: the minimum amount of assetSupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxIn, uint _minOut, address _to) external override {
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature(
			"instantLiquidation(address,uint256,address,address,uint256,uint256,address)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_maxIn,
			_minOut,
			_to
		));
		require(success);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
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
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
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

	//------------------------------------Y-T---v-a-u-l-t---L-i-q-u-i-d-a-t-i-o-n-s-------------------------------------


	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their YT vault(s) were liquidated
	
		@param address _asset: the address of the CH contract for which to claim the rebate
	*/
	function claimYTRebate(address _asset) external override {
		YTPosition memory position = _YTLiquidationRebates[msg.sender][_asset];
		ICapitalHandler(_asset).transferPosition(msg.sender, position.amountYield, position.amountBond);
		delete _YTLiquidationRebates[msg.sender][_asset];
	}


	/*
		@Description: send a vault that is under the upper collateralization limit to the auction house

		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _CHborrowed: the address of the CH contract corresponding to the borrowed ZCB
		@param address _CHsupplied: the address of the CH contract corresponding to the supplied ZCB & YT
		@param uint _bidYield: the first bid (in YT corresponding _CHsupplied) made by msg.sender on the vault
			ZCB of bid is calculated by finding the corresponding amount of ZCB based on the ratio of YT to ZCB
		@param int _minBondRatio: the miniumum value of vault.bondSupplied/vault.yieldSupplied inflated by (1 ether)
			if ratio is below _minBondRatio tx will revert
		@param uint _amtIn: the amount of the borrowed ZCB to send in
	*/
	function auctionYTLiquidation(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _bidYield, int _minBondRatio, uint _amtIn) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"auctionYTLiquidation(address,uint256,address,address,uint256,int256,uint256)",
			_owner,
			_index,
			_CHborrowed,
			_CHsupplied,
			_bidYield,
			_minBondRatio,
			_amtIn
		));
		require(success);
	}

	/*
		@Description: place a new bid on a YT vault that has already begun an auction

		@param uint _index: the index in _YTLiquidations[] of the auction
		@param uint _bidYield: the bid (in YT corresponding _CHsupplied) made by msg.sender on the vault
			ZCB of bid is calculated by finding the corresponding amount of ZCB based on the ratio of YT to ZCB
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnYTLiquidation(uint _index, uint _bidYield, uint _amtIn) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"bidOnYTLiquidation(uint256,uint256,uint256)",
			_index,
			_bidYield,
			_amtIn
		));
		require(success);
	}

	/*
		@Description: claim the collateral of a YT vault from an auction that was won by msg.sender

		@param uint _index: the index in YTLiquidations[] of the auction
		@param address _to: the address to which to send the proceeds
	*/
	function claimYTLiquidation(uint _index, address _to) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"claimYTLiquidation(uint256,address)",
			_index,
			_to
		));
		require(success);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator would like to liquidate the entire vault
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _CHborrowed: the address of the CH contract corresponding to the borrowed ZCB
		@param address _CHsupplied: the address of the CH contract corresponding to the supplied ZCB & YT
		@param uint _maxIn: the maximum amount of the borrowed asset that msg.sender is willing to send in
		@param int _minBondRatio: the minimum value of vault.bondSupplied / vault.yieldSupplied inflated by (1 ether)
			if the actual bond ratio of the vault is < _minBondRatio tx will revert
		@param uint _minOut: the minimum amount of YT from _CHsupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function instantYTLiquidation(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _maxIn, uint _minOut, int _minBondRatio, address _to) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"instantYTLiquidation(address,uint256,address,address,uint256,uint256,int256,address)",
			_owner,
			_index,
			_CHborrowed,
			_CHsupplied,
			_maxIn,
			_minOut,
			_minBondRatio,
			_to
		));
		require(success);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by providing a specific
			amount of the borrowed asset and receiving the corresponding percentage of the vault's collateral
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _CHborrowed: the address of the CH contract corresponding to the borrowed ZCB
		@param address _CHsupplied: the address of the CH contract corresponding to the supplied ZCB & YT
		@param uint _in: the amount of the borrowed asset to supply to the vault
		@param int _minBondRatio: the minimum value of vault.bondSupplied / vault.yieldSupplied inflated by (1 ether)
			if the actual bond ratio of the vault is < _minBondRatio tx will revert
		@param uint _minOut: the minimum amount of YT from _CHsupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function partialYTLiquidationSpecificIn(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _in, uint _minOut, int _minBondRatio, address _to) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"partialYTLiquidationSpecificIn(address,uint256,address,address,uint256,uint256,int256,address)",
			_owner,
			_index,
			_CHborrowed,
			_CHsupplied,
			_in,
			_minOut,
			_minBondRatio,
			_to
		));
		require(success);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by receiving a specific
			amount of YT corresponding to _CHsupplied and sending the corresponding amount of assetBorrowed
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _CHborrowed: the address of the CH contract corresponding to the borrowed ZCB
		@param address _CHsupplied: the address of the CH contract corresponding to the supplied ZCB & YT
		@param uint _out: the amount of YT corresponding to _CHsupplied to receive from the vault
		@param int _minBondOut: the minimum value of bond when transferPosition is called to payout liquidator
			if the actual bond out is < _minBondOut tx will revert
		@param uint _maxIn: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function partialYTLiquidationSpecificOut(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _out, int _minBondRatio, uint _maxIn, address _to) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"partialYTLiquidationSpecificOut(address,uint256,address,address,uint256,int256,uint256,address)",
			_owner,
			_index,
			_CHborrowed,
			_CHsupplied,
			_out,
			_minBondRatio,
			_maxIn,
			_to
		));
		require(success);
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
	*/
	function claimRevenue(address _asset) external override onlyOwner {
		uint rev = _revenue[_asset];
		IERC20(_asset).transfer(msg.sender, rev);
		delete _revenue[_asset];
	}

	/*
		@Description: admin may call this function to claim YT liquidation revenue

		@param address _CH: the address of the CH contract for which to claim revenue
		@param int _bondIn: the amount of bond to send in to make the transfer position have a
			positive minimum value at maturity
	*/
	function claimYTRevenue(address _CH, int _bondIn) external override onlyOwner {
		require(_bondIn > -1);
		YTPosition memory pos = _YTRevenue[_CH];
		ICapitalHandler(_CH).burnZCBFrom(msg.sender, uint(_bondIn));
		ICapitalHandler(_CH).transferPosition(msg.sender, pos.amountYield, pos.amountBond.add(_bondIn));
		delete _YTRevenue[_CH];
	}
}
