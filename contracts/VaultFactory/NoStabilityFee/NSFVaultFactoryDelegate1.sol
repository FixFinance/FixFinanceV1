// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./NSFVaultFactoryDelegateParent.sol";

contract NSFVaultFactoryDelegate1 is NSFVaultFactoryDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;

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
	) external {

		require(_assetSupplied != _assetBorrowed && _amountSupplied <= uint(type(int256).max));
		require(_fixCapitalPoolToWrapper[_assetSupplied] != address(0) || _wrapperToUnderlyingAsset[_assetSupplied] != address(0));

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(FCPborrowed, _amountBorrowed);
		Vault memory vault = Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed);
		{
			(bool withstands, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = vaultWithstandsChange(vault, _priceMultiplier, _suppliedRateChange, _borrowRateChange);
			require(withstands);
			editSubAccountStandardVault(false, msg.sender, sType, baseFCP, baseWrapper, int(vault.amountSupplied));
		}

		_vaults[msg.sender].push(vault);
	}

	/*
		@Description: fully repay a vault and withdraw all collateral

		@param uint _index: the vault to close is at vaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeVault(uint _index, address _to) external {
		uint len = _vaults[msg.sender].length;
		require(len > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0) {
			address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
			IFixCapitalPool(FCPborrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(FCPborrowed, vault.amountBorrowed);
		}
		if (vault.amountSupplied > 0) {
			require(vault.amountSupplied <= uint(type(int256).max));
			bool success = IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);
			require(success);
			(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(vault.assetSupplied);
			editSubAccountStandardVault(false, msg.sender, sType, baseFCP, baseWrapper, -int(vault.amountSupplied));
		}

		delete _vaults[msg.sender][_index];
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
	) external {
		require(_index < _vaults[_owner].length);

		Vault memory mVault = _vaults[_owner][_index];
		Vault storage sVault = _vaults[_owner][_index];
		Vault memory newVault = Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed);
		address copyVaultOwner = _owner; //prevent stack too deep

		//ensure that after operations vault will be in good health
		//only check health if at any point funds are being removed from the vault
		SUPPLIED_ASSET_TYPE sType;
		address baseFCPsupplied;
		address baseWrapperSupplied;
		if (
			_assetBorrowed != mVault.assetBorrowed ||
			_assetSupplied != mVault.assetSupplied ||
			_amountSupplied < mVault.amountSupplied ||
			_amountBorrowed > mVault.amountBorrowed
		) {
			//index 0 in multipliers that must be converted to uint
			require(_multipliers[0] > 0);
			require(msg.sender == copyVaultOwner);
			{
				bool withstands;
				(withstands, sType, baseFCPsupplied, baseWrapperSupplied) = vaultWithstandsChange(
					newVault,
					uint(_multipliers[0]),
					_multipliers[1],
					_multipliers[2]
				);
				require(withstands);
			}
		}
		else {
			(, sType, baseFCPsupplied, baseWrapperSupplied) = suppliedAssetInfo(_assetSupplied);
		}

		//------------------distribute funds----------------------
		if (mVault.assetSupplied != _assetSupplied) {
			if (mVault.amountSupplied != 0) {
				bool success = IERC20(mVault.assetSupplied).transfer(_receiverAddr, mVault.amountSupplied);
				require(success);
			}
			sVault.assetSupplied =  newVault.assetSupplied;
			sVault.amountSupplied = newVault.amountSupplied;
		}
		else if (mVault.amountSupplied > newVault.amountSupplied) {
			bool succes = IERC20(_assetSupplied).transfer(_receiverAddr, mVault.amountSupplied - newVault.amountSupplied);
			require(succes);
			sVault.amountSupplied = newVault.amountSupplied;
		}
		else if (mVault.amountSupplied < newVault.amountSupplied) {
			sVault.amountSupplied = newVault.amountSupplied;
		}

		IFixCapitalPool oldFCPBorrowed;
		if (mVault.assetBorrowed != newVault.assetBorrowed) {
			if (newVault.assetBorrowed != address(0)) {
				IFixCapitalPool newFCPBorrowed = IFixCapitalPool(IZeroCouponBond(newVault.assetBorrowed).FixCapitalPoolAddress());
				raiseShortInterest(address(newFCPBorrowed), newVault.amountBorrowed);
				newFCPBorrowed.mintZCBTo(_receiverAddr, newVault.amountBorrowed);
			}
			if (address(mVault.assetBorrowed) != address(0)) {
				oldFCPBorrowed = IFixCapitalPool(IZeroCouponBond(mVault.assetBorrowed).FixCapitalPoolAddress());
				lowerShortInterest(address(oldFCPBorrowed), mVault.amountBorrowed);
			}
			sVault.assetBorrowed = newVault.assetBorrowed;
			sVault.amountBorrowed = newVault.amountBorrowed;
		}
		else if (mVault.amountBorrowed < newVault.amountBorrowed) {
			oldFCPBorrowed = IFixCapitalPool(IZeroCouponBond(newVault.assetBorrowed).FixCapitalPoolAddress());
			raiseShortInterest(address(oldFCPBorrowed), newVault.amountBorrowed - mVault.amountBorrowed);
			oldFCPBorrowed.mintZCBTo(_receiverAddr, newVault.amountBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = newVault.amountBorrowed;
		}
		else if (mVault.amountBorrowed > newVault.amountBorrowed) {
			oldFCPBorrowed = IFixCapitalPool(IZeroCouponBond(newVault.assetBorrowed).FixCapitalPoolAddress());
			sVault.amountBorrowed = newVault.amountBorrowed;
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			bytes memory copyData = _data; //prevent stack too deep
			IVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(msg.sender,
				mVault.assetSupplied,
				mVault.assetBorrowed,
				mVault.amountSupplied,
				mVault.amountBorrowed,
				copyData
			);
		}

		//-----------------------------get funds-------------------------
		if (mVault.assetSupplied != newVault.assetSupplied) {
			bool success = IERC20(newVault.assetSupplied).transferFrom(msg.sender, address(this), newVault.amountSupplied);
			require(success);
			require(newVault.amountSupplied <= uint(type(int256).max));
			require(mVault.amountSupplied <= uint(type(int256).max));
			int changeAmt = int(newVault.amountSupplied);
			editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCPsupplied, baseWrapperSupplied, changeAmt);
			if (mVault.assetSupplied != address(0)) {
				changeAmt = -int(mVault.amountSupplied);
				(, sType, baseFCPsupplied, baseWrapperSupplied) = suppliedAssetInfo(mVault.assetSupplied);
				editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCPsupplied, baseWrapperSupplied, changeAmt);
			}
		}
		else {
			if (mVault.amountSupplied < newVault.amountSupplied) {
				bool success = IERC20(newVault.assetSupplied).transferFrom(msg.sender, address(this), newVault.amountSupplied - mVault.amountSupplied);
				require(success);
			}
			require(newVault.amountSupplied <= uint(type(int256).max));
			require(mVault.amountSupplied <= uint(type(int256).max));
			int changeAmt = int(newVault.amountSupplied).sub(int(mVault.amountSupplied));
			editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCPsupplied, baseWrapperSupplied, changeAmt);
		}

		if (mVault.assetBorrowed != newVault.assetBorrowed) {
			if (mVault.amountBorrowed > 0) {
				oldFCPBorrowed.burnZCBFrom(msg.sender, mVault.amountBorrowed);
			}
		}
		else if (mVault.amountBorrowed > newVault.amountBorrowed) {
			lowerShortInterest(address(oldFCPBorrowed), mVault.amountBorrowed - _amountBorrowed);
			oldFCPBorrowed.burnZCBFrom(msg.sender,  mVault.amountBorrowed - _amountBorrowed);
		}
	}

	//----------------------------------------------Liquidations------------------------------------------

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
			distributeSurplus(_owner, vault.assetSupplied, maxBid - _bid);
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
		distributeSurplus(liq.vaultOwner, liq.assetSupplied, maxBid - _bid);

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
		require(IZeroCouponBond(_assetBorrowed).maturity() < block.timestamp + CRITICAL_TIME_TO_MATURITY || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(FCPborrowed, vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);

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
		require(IFixCapitalPool(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(FCPborrowed, _in);
		IERC20(_assetSupplied).transfer(_to, amtOut);

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
		require(IFixCapitalPool(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, amtIn);
		lowerShortInterest(FCPborrowed, amtIn);
		IERC20(_assetSupplied).transfer(_to, _out);

		_vaults[_owner][_index].amountBorrowed -= amtIn;
		_vaults[_owner][_index].amountSupplied -= _out;
	}

	/*
		@Description: assign a vault/YTvault to a new owner

		@param uint _index: the index within vaults/YTvaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault/YTvault
		@param bool _isYTVault: true when the vault to transfer is a YTvault, false otherwise
	*/
	function transferVault(uint _index, address _to, bool _isYTVault) external {
		if (_isYTVault) {
			transferYTVault(_index, _to);
		}
		else {
			transferStandardVault(_index, _to);
		}
	}

	/*
		@Description: assign a vault to a new owner

		@param uint _index: the index within vaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault
	*/
	function transferStandardVault(uint _index, address _to) internal {
		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];
		_vaults[_to].push(vault);
		delete _vaults[msg.sender][_index];
	}

	/*
		@Description: assign a YT vault to a new owner

		@param uint _index: the index within YTvaults[msg.sender] at which the YT vault to transfer is located
		@param address _to: the new owner of the YT vault
	*/
	function transferYTVault(uint _index, address _to) internal {
		require(_YTvaults[msg.sender].length > _index);
		YTVault memory vault = _YTvaults[msg.sender][_index];
		_YTvaults[_to].push(vault);
		delete _YTvaults[msg.sender][_index];
	}

	/*
		@Description: admin may call this function to claim YT liquidation revenue

		@param address _FCP: the address of the FCP contract for which to claim revenue
		@param int _bondIn: the amount of bond to send in to make the transfer position have a
			positive minimum value at maturity
	*/
	function claimYTRevenue(address _FCP, int _bondIn) external onlyOwner {
		require(_bondIn > -1);
		YTPosition memory pos = _YTRevenue[_FCP];
		IFixCapitalPool(_FCP).burnZCBFrom(msg.sender, uint(_bondIn));
		uint yieldToTreasury = pos.amountYield >> 1;
		int bondToTreasury = pos.amountBond.add(_bondIn) / 2;
		IFixCapitalPool(_FCP).transferPosition(_treasuryAddress, yieldToTreasury, bondToTreasury);
		IFixCapitalPool(_FCP).transferPosition(msg.sender, pos.amountYield - yieldToTreasury, (pos.amountBond + _bondIn) - bondToTreasury);
		delete _YTRevenue[_FCP];
	}

}