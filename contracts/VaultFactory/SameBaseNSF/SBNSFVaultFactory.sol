// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/ISBNSFVaultFactory.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/nonReentrant.sol";
import "./SBNSFVaultFactoryData.sol";

contract SBNSFVaultFactory is SBNSFVaultFactoryData, ISBNSFVaultFactory, nonReentrant {
	using SafeMath for uint;
	using SignedSafeMath for int;

	address delegate1Address;
	address delegate2Address;
	address delegate3Address;
	address delegate4Address;
	address delegate5Address;

	constructor(
		address _vaultHealthContract,
		address _infoOracleAddr,
		address _delegate1Address,
		address _delegate2Address,
		address _delegate3Address,
		address _delegate4Address,
		address _delegate5Address
	) public {
		vaultHealthContract = IVaultHealth(_vaultHealthContract);
		_infoOracleAddress = _infoOracleAddr;
		delegate1Address = _delegate1Address;
		delegate2Address = _delegate2Address;
		delegate3Address = _delegate3Address;
		delegate4Address = _delegate4Address;
		delegate5Address = _delegate5Address;
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

	function wrapperToUnderlyingAsset(address _wrapperAddress) external view override returns (address) {
		return _wrapperToUnderlyingAsset[_wrapperAddress];
	}

	function fixCapitalPoolToWrapper(address _fixCapitalPoolAddress) external view override returns (address) {
		return _fixCapitalPoolToWrapper[_fixCapitalPoolAddress];
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

	function liquidationRebates(address _owner, address _asset) external view override returns(uint) {
		return _liquidationRebates[_owner][_asset];
	}

	function YTLiquidationRebates(address _owner, address _FCP) external view override returns(uint yield, int bond) {
		YTPosition memory pos = _YTLiquidationRebates[_owner][_FCP];
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
		address FCPsupplied,
		address FCPborrowed,
		uint yieldSupplied,
		int bondSupplied,
		uint amountBorrowed
	) {
		YTVault memory vault = _YTvaults[_owner][_index];
		FCPsupplied = vault.FCPsupplied;
		FCPborrowed = vault.FCPborrowed;
		yieldSupplied = vault.yieldSupplied;
		bondSupplied = vault.bondSupplied;
		amountBorrowed = vault.amountBorrowed;
	}

	function YTLiquidations(uint _index) external view override returns (
		address vaultOwner,
		address FCPsupplied,
		address FCPborrowed,
		int bondRatio,
		uint amountBorrowed,
		address bidder,
		uint bidAmount,
		uint bidTimestamp
	) {
		YTLiquidation memory liq = _YTLiquidations[_index];
		vaultOwner = liq.vaultOwner;
		FCPsupplied = liq.FCPsupplied;
		FCPborrowed = liq.FCPborrowed;
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

		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
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
		emit OpenVault(msg.sender, _vaults[msg.sender].length-1);
	}

	/*
		@Description: fully repay a vault and withdraw all collateral

		@param uint _index: the vault to close is at vaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeVault(uint _index, address _to) external override noReentry {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"closeVault(uint256,address)",
			_index,
			_to
		));
		require(success);
		emit CloseVault(msg.sender, _index);
	}

	/*
		@Description: adjust the state of a vault by either changing the assets in it
			or paying down/increasing debt or supplying/withdrawing collateral
			for any call where funds would be transfered out of the vault msg.sender must be the vault owner
			if the _data param has length > 0, assets sent out by the vault will be sent via flashloan
			and repayment must be made in the required collateral assets 

		@param address _owner: the owner of the vault to adjust
		@param uint _index: the index of the vault in vaults[_owner]
		@param address _assetSupplied: the new asset(may be the same as previous) that is to be used as
			collateral in the vault
		@param address _assetBorrowed: the new asset(may be the same as previous) that is to be borrowed
			from the vault
		@param uint _amountSupplied: the total amount of collateral that shall be in the vault after execution
		@param uint _amountBorrowed: the total amount of debt of the vault after execution
		@param int128[3] calldata _multipliers: the 3 multipliers used on call to
			vaultHealthContract.vaultWithstandsChange
				uint(_multipliers[0]) is priceMultiplier
				_multipliers[1] is suppliedRateMultiplier
				_multipliers[2] is borrowedRateMultiplier
		@param bytes calldata _data: data to be send to the flashloan receiver if a flashloan is to be done
			if _data.length == 0 there will be no flashloan
		@param  address _receiverAddr: the address of the flashloan receiver contract
	*/
	function adjustVault(
		address _owner,
		uint _index,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		int128[3] calldata _multipliers,
		bytes calldata _data,
		address _receiverAddr
	) external override noReentry {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"adjustVault(address,uint256,address,address,uint256,uint256,int128[3],bytes,address)",
			_owner,
			_index,
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed,
			_multipliers,
			_data,
			_receiverAddr
		));
		require(success);
		emit AdjustVault(_owner, _index);
	}

	//--------------------------------------YT vault management-----------------------------------

	/*
		@Description: create a new YT vault, deposit some ZCB + YT of a FCP and borrow some ZCB from it

		@param address _FCPsupplied: the address of the FCP contract for which to supply ZCB and YT
		@param address _FCPborrowed: the FCP that corresponds to theZCB that is borrowed from the new YTVault
		@param uint _yieldSupplied: the amount from the balanceYield mapping in the supplied FCP contract
			that is to be supplied to the new YTVault
		@param int _bondSupplied: the amount from the balanceBonds mapping in the supplied FCP contract
			that is to be supplied to the new YTVault
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed to borrow
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
		address _FCPsupplied,
		address _FCPborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external override {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
			"openYTVault(address,address,uint256,int256,uint256,uint256,int128,int128)",
			_FCPsupplied,
			_FCPborrowed,
			_yieldSupplied,
			_bondSupplied,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));
		require(success);
		emit OpenYTVault(msg.sender, _YTvaults[msg.sender].length-1);
	}

	/*
		@Description: fully repay a YT vault and withdraw all collateral

		@param uint _index: the YT vault to close is at YTvaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeYTVault(uint _index, address _to) external override noReentry {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
			"closeYTVault(uint256,address)",
			_index,
			_to
		));
		require(success);
		emit CloseYTVault(msg.sender, _index);
	}

	/*
		@Description: adjust the state of a YT vault by either changing the assets in it
			or paying down/increasing debt or supplying/withdrawing collateral
			for any call where funds would be transfered out of the vault msg.sender must be the vault owner
			if the _data param has length > 0, assets sent out by the vault will be sent via flashloan
			and repayment must be made in the required collateral assets 

		@param address _owner: the owner of the YT vault to adjust
		@param uint _index: the index of the YT vault in YTvaults[_owner]
		@param address _FCPsupplied: the new FCP (may be the same as previous) corresponding to the vault's
			ZCB & YT collateral
		@param address _FCPborrowed: the new FCP (may be the same as previous) corresponding to the ZCB
			that is to be borrowed from the vault
		@param uint _yieldSupplied: the amount from the balanceYield mapping in the supplied FCP contract
			that will be supplied as collateral to the YTVault after execution
		@param int _bondSupplied: the amount from the balanceBonds mapping in the supplied FCP contract
			that will be supplied as collateral to the YTVault after execution
		@param uint _amountBorrowed: the total amount of debt of the vault after execution
		@param int128[3] calldata _multipliers: the 3 multipliers used on call to
			vaultHealthContract.vaultWithstandsChange
				uint(_multipliers[0]) is priceMultiplier
				_multipliers[1] is suppliedRateMultiplier
				_multipliers[2] is borrowedRateMultiplier
		@param bytes calldata _data: data to be send to the flashloan receiver if a flashloan is to be done
			if _data.length == 0 there will be no flashloan
		@param  address _receiverAddr: the address of the flashloan receiver contract
	*/
	function adjustYTVault(
		address _owner,
		uint _index,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		int128[3] calldata _multipliers,
		bytes calldata _data,
		address _receiverAddr
	) external override noReentry {
		(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
			"adjustYTVault(address,uint256,address,address,uint256,int256,uint256,int128[3],bytes,address)",
			_owner,
			_index,
			_FCPsupplied,
			_FCPborrowed,
			_yieldSupplied,
			_bondSupplied,
			_amountBorrowed,
			_multipliers,
			_data,
			_receiverAddr
		));
		require(success);
		emit AdjustYTVault(_owner, _index);
	}

	//--------------------------------f-o-r---b-o-t-h---s-t-a-n-d-a-r-d---v-a-u-l-t-s---a-n-d---Y-T-v-a-u-l-t-s---------------

	/*
		@Description: assign a vault/YTvault to a new owner

		@param uint _index: the index within vaults/YTvaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault/YTvault
		@param bool _isYTVault: true when the vault to transfer is a YTvault, false otherwise
	*/
	function transferVault(uint _index, address _to, bool _isYTVault) external override noReentry {
		(bool success, ) = delegate5Address.delegatecall(abi.encodeWithSignature(
			"transferVault(uint256,address,bool)",
			_index,
			_to,
			_isYTVault
		));
		require(success);
		emit TransferVault(msg.sender, _index, _to, _isYTVault);
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
	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _maxIn) external override noReentry {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"auctionLiquidation(address,uint256,address,address,uint256,uint256)",
			_owner,
			_index,
			_assetBorrowed,
			_assetSupplied,
			_bid,
			_maxIn
		));
		require(success);
		emit AuctionLiquidation(_owner, _index, _Liquidations.length-1);
	}

	/*
		@Description: place a new bid on a vault that has already begun an auction

		@param uint _index: the index in _Liquidations[] of the auction
		@param uint  _bid: the amount of the supplied asset that the liquidator wishes to receive
			in reward if the liquidator wins this auction
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnLiquidation(uint _index, uint _bid, uint _amtIn) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"bidOnLiquidation(uint256,uint256,uint256)",
			_index,
			_bid,
			_amtIn
		));
		require(success);
		emit BidOnLiquidation(_index);
	}

	/*
		@Description: claim the collateral of a vault from an auction that was won by msg.sender

		@param uint _index: the index in Liquidations[] of the auction
		@param address _to: the address to which to send the proceeds
	*/
	function claimLiquidation(uint _index, address _to) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"claimLiquidation(uint256,address)",
			_index,
			_to
		));
		require(success);
		emit ClaimLiquidation(_index);
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
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxIn, uint _minOut, address _to) external override noReentry {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
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
		emit InstantLiquidation(_owner, _index);
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
	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external override noReentry{
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
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
		emit InstantLiquidation(_owner, _index);
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
	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external override noReentry {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
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
		emit InstantLiquidation(_owner, _index);
	}


	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their vault(s) were liquidated

		@param address _asset: the address of the asset for which to claim rebated collateral
	*/
	function claimRebate(address _asset) external override {
		(bool success, ) = delegate5Address.delegatecall(abi.encodeWithSignature(
			"claimRebate(address)",
			_asset
		));
		require(success);
		emit ClaimRebate(msg.sender, _asset);
	}

	//------------------------------------Y-T---v-a-u-l-t---L-i-q-u-i-d-a-t-i-o-n-s-------------------------------------


	/*
		@Description: allows a user to claim the excess collateral that was received as a rebate
			when their YT vault(s) were liquidated
	
		@param address _FCP: the address of the FCP contract for which to claim the rebate
	*/
	function claimYTRebate(address _FCP) external override {
		(bool success, ) = delegate5Address.delegatecall(abi.encodeWithSignature(
			"claimYTRebate(address)",
			_FCP
		));
		require(success);
		emit ClaimYTRebate(msg.sender, _FCP);
	}


	/*
		@Description: send a vault that is under the upper collateralization limit to the auction house

		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _FCPborrowed: the address of the FCP contract corresponding to the borrowed ZCB
		@param address _FCPsupplied: the address of the FCP contract corresponding to the supplied ZCB & YT
		@param uint _bidYield: the first bid (in YT corresponding _FCPsupplied) made by msg.sender on the vault
			ZCB of bid is calculated by finding the corresponding amount of ZCB based on the ratio of YT to ZCB
		@param int _minBondRatio: the miniumum value of vault.bondSupplied/vault.yieldSupplied inflated by (1 ether)
			if ratio is below _minBondRatio tx will revert
		@param uint _amtIn: the amount of the borrowed ZCB to send in
	*/
	function auctionYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _bidYield, int _minBondRatio, uint _amtIn) external override noReentry {
		(bool success, ) = delegate4Address.delegatecall(abi.encodeWithSignature(
			"auctionYTLiquidation(address,uint256,address,address,uint256,int256,uint256)",
			_owner,
			_index,
			_FCPborrowed,
			_FCPsupplied,
			_bidYield,
			_minBondRatio,
			_amtIn
		));
		require(success);
		emit AuctionYTLiquidation(_owner, _index, _YTLiquidations.length-1);
	}

	/*
		@Description: place a new bid on a YT vault that has already begun an auction

		@param uint _index: the index in _YTLiquidations[] of the auction
		@param uint _bidYield: the bid (in YT corresponding _FCPsupplied) made by msg.sender on the vault
			ZCB of bid is calculated by finding the corresponding amount of ZCB based on the ratio of YT to ZCB
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnYTLiquidation(uint _index, uint _bidYield, uint _amtIn) external override {
		(bool success, ) = delegate4Address.delegatecall(abi.encodeWithSignature(
			"bidOnYTLiquidation(uint256,uint256,uint256)",
			_index,
			_bidYield,
			_amtIn
		));
		require(success);
		emit BidOnYTLiquidation(_index);
	}

	/*
		@Description: claim the collateral of a YT vault from an auction that was won by msg.sender

		@param uint _index: the index in YTLiquidations[] of the auction
		@param address _to: the address to which to send the proceeds
	*/
	function claimYTLiquidation(uint _index, address _to) external override {
		(bool success, ) = delegate4Address.delegatecall(abi.encodeWithSignature(
			"claimYTLiquidation(uint256,address)",
			_index,
			_to
		));
		require(success);
		emit ClaimYTLiquidation(_index);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator would like to liquidate the entire vault
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _FCPborrowed: the address of the FCP contract corresponding to the borrowed ZCB
		@param address _FCPsupplied: the address of the FCP contract corresponding to the supplied ZCB & YT
		@param uint _maxIn: the maximum amount of the borrowed asset that msg.sender is willing to send in
		@param int _minBondRatio: the minimum value of vault.bondSupplied / vault.yieldSupplied inflated by (1 ether)
			if the actual bond ratio of the vault is < _minBondRatio tx will revert
		@param uint _minOut: the minimum amount of YT from _FCPsupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function instantYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _maxIn, uint _minOut, int _minBondRatio, address _to) external override noReentry {
		(bool success, ) = delegate4Address.delegatecall(abi.encodeWithSignature(
			"instantYTLiquidation(address,uint256,address,address,uint256,uint256,int256,address)",
			_owner,
			_index,
			_FCPborrowed,
			_FCPsupplied,
			_maxIn,
			_minOut,
			_minBondRatio,
			_to
		));
		require(success);
		emit InstantLiquidation(_owner, _index);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by providing a specific
			amount of the borrowed asset and receiving the corresponding percentage of the vault's collateral
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _FCPborrowed: the address of the FCP contract corresponding to the borrowed ZCB
		@param address _FCPsupplied: the address of the FCP contract corresponding to the supplied ZCB & YT
		@param uint _in: the amount of the borrowed asset to supply to the vault
		@param int _minBondRatio: the minimum value of vault.bondSupplied / vault.yieldSupplied inflated by (1 ether)
			if the actual bond ratio of the vault is < _minBondRatio tx will revert
		@param uint _minOut: the minimum amount of YT from _FCPsupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function partialYTLiquidationSpecificIn(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _in, uint _minOut, int _minBondRatio, address _to) external override noReentry {
		(bool success, ) = delegate4Address.delegatecall(abi.encodeWithSignature(
			"partialYTLiquidationSpecificIn(address,uint256,address,address,uint256,uint256,int256,address)",
			_owner,
			_index,
			_FCPborrowed,
			_FCPsupplied,
			_in,
			_minOut,
			_minBondRatio,
			_to
		));
		require(success);
		emit InstantLiquidation(_owner, _index);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by receiving a specific
			amount of YT corresponding to _FCPsupplied and sending the corresponding amount of assetBorrowed
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _FCPborrowed: the address of the FCP contract corresponding to the borrowed ZCB
		@param address _FCPsupplied: the address of the FCP contract corresponding to the supplied ZCB & YT
		@param uint _out: the amount of YT corresponding to _FCPsupplied to receive from the vault
		@param int _minBondOut: the minimum value of bond when transferPosition is called to payout liquidator
			if the actual bond out is < _minBondOut tx will revert
		@param uint _maxIn: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function partialYTLiquidationSpecificOut(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _out, int _minBondRatio, uint _maxIn, address _to) external override noReentry {
		(bool success, ) = delegate4Address.delegatecall(abi.encodeWithSignature(
			"partialYTLiquidationSpecificOut(address,uint256,address,address,uint256,int256,uint256,address)",
			_owner,
			_index,
			_FCPborrowed,
			_FCPsupplied,
			_out,
			_minBondRatio,
			_maxIn,
			_to
		));
		require(success);
		emit InstantLiquidation(_owner, _index);
	}


	//-------------------------------------a-d-m-i-n---m-a-n-a-g-e-m-e-n-t----------------------------------------------

	function manage(address _addr, int _num, MANAGE_METHOD _manageMethod) external override {
		(bool success, ) = delegate5Address.delegatecall(abi.encodeWithSignature(
			"manage(address,int256,uint8)",
			_addr,
			_num,
			_manageMethod
		));
		require(success);
	}
}

