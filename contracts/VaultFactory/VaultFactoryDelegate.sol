pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/IVaultManagerFlashReceiver.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./VaultFactoryData.sol";

contract VaultFactoryDelegate is VaultFactoryData {
	using SafeMath for uint;
	using SignedSafeMath for int;

	/*
		@Description: ensure that short interst rasing by a specific amount does not push an asset over the debt ceiling

		@param address _fixCapitalPoolAddress: address of the ZCB for which to raise short interst
		@param uint _amount: amount ny which to raise short interst
	*/
	function raiseShortInterest(address _fixCapitalPoolAddress, uint _amount) internal {
		address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
		uint temp = _shortInterestAllDurations[underlyingAssetAddress].add(_amount);
		require(vaultHealthContract.maximumShortInterest(underlyingAssetAddress) >= temp);
		_shortInterestAllDurations[underlyingAssetAddress] = temp;
	}

	/*
		@Description: decrease short interest

		@param address _fixCapitalPoolAddress: address of the ZCB for which to decrease short interest
		@param uint _amount: the amount by which to decrease short interest
	*/
	function lowerShortInterest(address _fixCapitalPoolAddress, uint _amount) internal {
		address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
		_shortInterestAllDurations[underlyingAssetAddress] = _shortInterestAllDurations[underlyingAssetAddress].sub(_amount);
	}
	
	/*
		@Description: distribute surplus appropriately between vault owner and contract owner
			this function is called by other liquidation management functions

		@param address _vaultOwner: the owner of the vault that has between liquidated
		@param address _asset: the address of the asset for which surplus has been acquired
		@param uint _amount: the amount of surplus
	*/
	function distributeSurplus(address _vaultOwner, address _asset, uint _amount) internal {
		uint retainedSurplus = _amount * _liquidationRebateBips / TOTAL_BASIS_POINTS;
		_liquidationRebates[_vaultOwner][_asset] += retainedSurplus;
		_revenue[_asset] += _amount-retainedSurplus;
	}

	/*
		@Description: when a bidder is outbid return their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the FCP corresponding to the ZCB that the bidder
			posted with their bid in
		@param uint _amount: the amount of _asset that was posted by the bidder
	*/
	function refundBid(address _bidder, address _FCPaddr, uint _amount) internal {
		IFixCapitalPool(_FCPaddr).mintZCBTo(_bidder, _amount);
	}

	/*
		@Description: when a bidder makes a bid collect collateral for their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the FCP corresponding to the ZCB that the bidder
			posted with their bid in
		@param uint _amount: the amount of _asset that the bidder is required to post
	*/
	function collectBid(address _bidder, address _FCPaddr, uint _amount) internal {
		IFixCapitalPool(_FCPaddr).burnZCBFrom(_bidder, _amount);
	}

	/*
		@Description: ensure that we pass the address of the underlying asset of wrapper assets to
			the vault health contract rather than the address of the wrapper asset
			also ensure that we adjust the amount from the wrapped amount to the non wrapped amount
			if necessary

		@param address _suppliedAsset: the address of the asset that is supplied as collateral
		@param uint _suppliedAmount: the amount of the supplied asset that is being used as collateral

		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint amt: the amount for amountSupplied to pass to the vault health contract
	*/
	function passInfoToVaultManager(address _suppliedAsset, uint _suppliedAmount) internal view returns (address addr, uint amt) {
		addr = _wrapperToUnderlyingAsset[_suppliedAsset];
		if (addr == address(0) || addr == address(1)) {
			addr = _suppliedAsset;
			amt = _suppliedAmount;
		}
		else {
			amt = IWrapper(_suppliedAsset).WrappedAmtToUnitAmt_RoundDown(_suppliedAmount);
		}
	}


	/*
		@Description: ensure that a vault will not be sent into the liquidation zone if the cross asset price
			and the borrow and supplied asset rates change a specific amount

		@param address _assetSupplied: the asset used as collateral
			this asset may be a ZCB or any other asset that is whitelisted
		@param address _assetBorrowed: the ZCB that is borrowed from the new vault
`		@param uint _amountSupplied: the amount of _assetSupplied posed as collateral
		@param uint _amountBorrowed: the amount of _assetBorrowed borrowed
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

		@return bool: true if vault is not sent into liquidation zone from changes,
			false otherwise
	*/
	function vaultWithstandsChange(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) internal view returns (bool) {

		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_suppliedRateChange >= ABDK_1);
		require(_borrowRateChange <= ABDK_1);

		(address _suppliedAddrToPass, uint _suppliedAmtToPass) = passInfoToVaultManager(_assetSupplied, _amountSupplied);

		return vaultHealthContract.vaultWithstandsChange(
			_suppliedAddrToPass,
			_assetBorrowed,
			_suppliedAmtToPass,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		);
	}

	/*
		@Description: check if a vault is above the upper or lower collateralization limit

		@param address _assetSupplied: the asset used as collateral
			this asset may be a ZCB or any other asset that is whitelisted
		@param address _assetBorrowed: the ZCB that is borrowed from the new vault
`		@param uint _amountSupplied: the amount of _assetSupplied posed as collateral
		@param uint _amountBorrowed: the amount of _assetBorrowed borrowed
		@param bool _upper: true if we are to check the upper collateralization limit,
			false otherwise

		@return bool: true if vault satisfies the limit,
			false otherwise
	*/
	function satisfiesLimit(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		bool _upper
		) internal view returns (bool) {

		(address _suppliedAddrToPass, uint _suppliedAmtToPass) = passInfoToVaultManager(_assetSupplied, _amountSupplied);

		return ( _upper ?
			vaultHealthContract.satisfiesUpperLimit(_suppliedAddrToPass, _assetBorrowed, _suppliedAmtToPass, _amountBorrowed)
				:
			vaultHealthContract.satisfiesLowerLimit(_suppliedAddrToPass, _assetBorrowed, _suppliedAmtToPass, _amountBorrowed)
			);
	}


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

		require(_assetSupplied != _assetBorrowed);
		require(_fixCapitalPoolToWrapper[_assetSupplied] != address(0) || _wrapperToUnderlyingAsset[_assetSupplied] != address(0));
		require(vaultWithstandsChange(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, _priceMultiplier, _suppliedRateChange, _borrowRateChange));

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(FCPborrowed, _amountBorrowed);

		_vaults[msg.sender].push(Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed));
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
		if (vault.amountSupplied > 0)
			IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);

		if (len - 1 != _index)
			_vaults[msg.sender][_index] = _vaults[msg.sender][len - 1];
		delete _vaults[msg.sender][len - 1];
	}

	/*
		@Description: adjust the state of a vault by either changing the assets in it
			or paying down/increasing debt or supplying/withdrawing collateral
			for any call where funds would be transfered out of the vault msg.sender must be the vault owner
			if the _data param has length > 0, assets sent out by the vault will be sent via flashloan
			and repayment must be made in the required collateral assets 

		@param address _owner: the owner of the vault to adjust
		@param uint _index: the index of the vault in vaults[_owner] to which to supply collateral
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

		//ensure that after operations vault will be in good health
		//only check health if at any point funds are being removed from the vault
		if (
			_assetBorrowed != mVault.assetBorrowed ||
			_assetSupplied != mVault.assetSupplied ||
			_amountSupplied < mVault.amountSupplied ||
			_amountBorrowed > mVault.amountBorrowed
		) {
			//index 0 in multipliers that must be converted to uint
			require(_multipliers[0] > 0);
			require(msg.sender == _owner);
			require(vaultWithstandsChange(
				_assetSupplied,
				_assetBorrowed,
				_amountSupplied,
				_amountBorrowed,
				uint(_multipliers[0]),
				_multipliers[1],
				_multipliers[2]
			));
		}

		//------------------distribute funds----------------------
		if (mVault.assetSupplied != _assetSupplied) {
			bool success = IERC20(mVault.assetSupplied).transfer(_receiverAddr, mVault.amountSupplied);
			require(success);
			sVault.assetSupplied = _assetSupplied;
			sVault.amountSupplied = _amountSupplied;
		}
		else if (mVault.amountSupplied > _amountSupplied) {
			bool succes = IERC20(_assetSupplied).transfer(_receiverAddr, mVault.amountSupplied - _amountSupplied);
			require(succes);
			sVault.amountSupplied = _amountSupplied;
		}
		else if (mVault.amountSupplied < _amountSupplied) {
			sVault.amountSupplied = _amountSupplied;
		}

		if (mVault.assetBorrowed != _assetBorrowed) {
			IFixCapitalPool fcp = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			fcp.mintZCBTo(_receiverAddr, _amountBorrowed);
			sVault.assetBorrowed = _assetBorrowed;
			sVault.amountBorrowed = _amountBorrowed;
		}
		else if (mVault.amountBorrowed < _amountBorrowed) {
			IFixCapitalPool fcp = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			fcp.mintZCBTo(_receiverAddr, _amountBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = _amountBorrowed;
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			sVault.amountBorrowed = _amountBorrowed;
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			IVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(msg.sender, _data);
		}

		//-----------------------------get funds-------------------------
		if (mVault.assetSupplied != _assetSupplied) {
			bool success = IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
			require(success);
		}
		else if (mVault.amountSupplied < _amountSupplied) {
			bool success = IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied - mVault.amountSupplied);
			require(success);
		}

		if (mVault.assetBorrowed != _assetBorrowed) {
			IFixCapitalPool fcp = IFixCapitalPool(IZeroCouponBond(mVault.assetBorrowed).FixCapitalPoolAddress());
			fcp.burnZCBFrom(msg.sender, mVault.amountBorrowed);
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			IFixCapitalPool fcp = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			fcp.burnZCBFrom(msg.sender,  mVault.amountBorrowed - _amountBorrowed);
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
			uint maturity = IFixCapitalPool(vault.assetBorrowed).maturity();
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
		require(IFixCapitalPool(_assetBorrowed).maturity() < block.timestamp + CRITICAL_TIME_TO_MATURITY || 
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

}