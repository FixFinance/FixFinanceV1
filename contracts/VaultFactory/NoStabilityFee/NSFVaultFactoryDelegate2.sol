// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IYTVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./NSFVaultFactoryDelegateParent.sol";

/*
	This contract is specifically for handling YTVault functionality
*/
contract NSFVaultFactoryDelegate2 is NSFVaultFactoryDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;

	/*
		@Description: send a vault that is under the upper collateralization limit to the auction house

		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _bid: the first bid (in _assetSupplied) made by msg.sender
		@param uint _amtIn: the amount of _assetBorrowed to send in
	*/
	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _amtIn) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed >= _amtIn && _amtIn > 0);
		uint maxBid = vault.amountSupplied * _amtIn / vault.amountBorrowed;
		require(maxBid >= _bid);
		if (satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, true)) {
			uint maturity = IZeroCouponBond(vault.assetBorrowed).maturity();
			require(maturity < block.timestamp + MAX_TIME_TO_MATURITY);
		}
		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		collectBid(msg.sender, FCPborrowed, _amtIn);
		lowerShortInterest(FCPborrowed, _amtIn);
		//any surplus in the bid may be added as _revenue
		if (_bid < maxBid){
			distributeSurplus(_owner, vault.assetSupplied, maxBid - _bid, true);
		}
		if (_amtIn == vault.amountBorrowed) {
			delete _vaults[_owner][_index];
		}
		else {
			_vaults[_owner][_index].amountBorrowed -= _amtIn;
			_vaults[_owner][_index].amountSupplied -= maxBid;
		}
		_Liquidations.push(Liquidation(
			_owner,
			vault.assetSupplied,
			vault.assetBorrowed,
			_amtIn,
			msg.sender,
			_bid,
			block.timestamp
		));
	}

	/*
		@Description: place a new bid on a vault that has already begun an auction

		@param uint _index: the index in _Liquidations[] of the auction
		@param uint  _bid: the amount of the supplied asset that the liquidator wishes to receive
			in reward if the liquidator wins this auction
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnLiquidation(uint _index, uint _bid, uint _amtIn) external {
		require(_Liquidations.length > _index);
		Liquidation memory liq = _Liquidations[_index];
		require(0 < _amtIn && _amtIn <= liq.amountBorrowed);
		uint maxBid = liq.bidAmount * _amtIn / liq.amountBorrowed;
		require(_bid < maxBid);

		address FCPborrowed = IZeroCouponBond(liq.assetBorrowed).FixCapitalPoolAddress();
		refundBid(liq.bidder, FCPborrowed, _amtIn);
		collectBid(msg.sender, FCPborrowed, _amtIn);
		distributeSurplus(liq.vaultOwner, liq.assetSupplied, maxBid - _bid, true);

		if (_amtIn == liq.amountBorrowed) {
			_Liquidations[_index].bidAmount = _bid;
			_Liquidations[_index].bidTimestamp = block.timestamp;
			_Liquidations[_index].bidder = msg.sender;
		}
		else {
			_Liquidations[_index].bidAmount -= maxBid;
			_Liquidations[_index].amountBorrowed -= _amtIn;

			_Liquidations.push(Liquidation(
				liq.vaultOwner,
				liq.assetSupplied,
				liq.assetBorrowed,
				_amtIn,
				msg.sender,
				_bid,
				block.timestamp
			));
		}
	}

	/*
		@Description: claim the collateral of a vault from an auction that was won by msg.sender

		@param uint _index: the index in Liquidations[] of the auction
		@param address _to: the address to which to send the proceeds
	*/
	function claimLiquidation(uint _index, address _to) external {
		require(_Liquidations.length > _index);
		Liquidation memory liq = _Liquidations[_index];
		require(msg.sender == liq.bidder);
		require(block.timestamp >= AUCTION_COOLDOWN + liq.bidTimestamp);

		delete _Liquidations[_index];

		IERC20(liq.assetSupplied).transfer(_to, liq.bidAmount);

		(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(liq.assetSupplied);
		require(liq.bidAmount <= uint(type(int256).max));
		editSubAccountStandardVault(false, liq.vaultOwner, sType, baseFCP, baseWrapper, -int(liq.bidAmount));
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
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxIn, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _maxIn);
		require(vault.amountSupplied >= _minOut && _minOut > 0);

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(FCPborrowed, vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);

		{
			SUPPLIED_ASSET_TYPE sType;
			address baseFCP;
			address baseWrapper;
			if (IZeroCouponBond(_assetBorrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
				bool satisfies;
				(satisfies, sType, baseFCP, baseWrapper) = satisfiesLimitRetAllData(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false);
				require(!satisfies);
			}
			else {
				(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(_assetSupplied);
			}
			require(vault.amountSupplied <= uint(type(int256).max));
			int changeAmt = -int(vault.amountSupplied);
			editSubAccountStandardVault(false, _owner, sType, baseFCP, baseWrapper, changeAmt);
		}

		delete _vaults[_owner][_index];
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
	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(0 < _in && _in <= vault.amountBorrowed);
		uint amtOut = _in*vault.amountSupplied/vault.amountBorrowed;
		require(amtOut >= _minOut);

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(FCPborrowed, _in);
		IERC20(_assetSupplied).transfer(_to, amtOut);

		{
			SUPPLIED_ASSET_TYPE sType;
			address baseFCP;
			address baseWrapper;
			if (IZeroCouponBond(_assetBorrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
				bool satisfies;
				(satisfies, sType, baseFCP, baseWrapper) = satisfiesLimitRetAllData(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false);
				require(!satisfies);
			}
			else {
				(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(_assetSupplied);
			}
			require(amtOut <= uint(type(int256).max));
			int changeAmt = -int(amtOut);
			editSubAccountStandardVault(false, _owner, sType, baseFCP, baseWrapper, changeAmt);
		}

		_vaults[_owner][_index].amountBorrowed -= _in;
		_vaults[_owner][_index].amountSupplied -= amtOut;
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
		@param uint _out: the amount of assetSupplied to receive from the vault
		@param uint _maxIn: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountSupplied >= _out);
		uint amtIn = _out*vault.amountBorrowed;
		amtIn = amtIn/vault.amountSupplied + (amtIn%vault.amountSupplied == 0 ? 0 : 1);
		require(0 < amtIn && amtIn <= _maxIn);

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, amtIn);
		lowerShortInterest(FCPborrowed, amtIn);
		IERC20(_assetSupplied).transfer(_to, _out);

		{
			SUPPLIED_ASSET_TYPE sType;
			address baseFCP;
			address baseWrapper;
			if (IZeroCouponBond(_assetBorrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
				bool satisfies;
				(satisfies, sType, baseFCP, baseWrapper) = satisfiesLimitRetAllData(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false);
				require(!satisfies);
			}
			else {
				(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(_assetSupplied);
			}
			require(_out <= uint(type(int256).max));
			int changeAmt = -int(_out);
			editSubAccountStandardVault(false, _owner, sType, baseFCP, baseWrapper, changeAmt);
		}

		_vaults[_owner][_index].amountBorrowed -= amtIn;
		_vaults[_owner][_index].amountSupplied -= _out;
	}

}