pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./MarginManagerData.sol";

contract MarginManagerDelegate is MarginManagerData {
	using SafeMath for uint;
	using SignedSafeMath for int;

	/*
		@Description: ensure that short interst rasing by a specific amount does not push an asset over the debt ceiling

		@param address _capitalHandlerAddress: address of the ZCB for which to raise short interst
		@param uint _amount: amount ny which to raise short interst
	*/
	function raiseShortInterest(address _capitalHandlerAddress, uint _amount) internal {
		address underlyingAssetAddress = ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress();
		uint temp = _shortInterestAllDurations[underlyingAssetAddress].add(_amount);
		require(vaultHealthContract.maximumShortInterest(underlyingAssetAddress) >= temp);
		_shortInterestAllDurations[underlyingAssetAddress] = temp;
	}

	/*
		@Description: decrease short interest

		@param address _capitalHandlerAddress: address of the ZCB for which to decrease short interest
		@param uint _amount: the amount by which to decrease short interest
	*/
	function lowerShortInterest(address _capitalHandlerAddress, uint _amount) internal {
		address underlyingAssetAddress = ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress();
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
		@param address _asset: the address of the asset that the bidder posted with their bid in
		@param uint _amount: the amount of _asset that was posted by the bidder
	*/
	function refundBid(address _bidder, address _asset, uint _amount) internal {
		ICapitalHandler(_asset).mintZCBTo(_bidder, _amount);
	}

	/*
		@Description: when a bidder makes a bid collect collateral for their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the asset that the bidder is posing as collateral
		@param uint _amount: the amount of _asset that the bidder is required to post
	*/
	function collectBid(address _bidder, address _asset, uint _amount) internal {
		ICapitalHandler(_asset).burnZCBFrom(_bidder, _amount);
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
		@Description: given a capital handler and a balance from the balanceYield mapping
			convert the value from wrapped amount to unit amount
	*/
	function getUnitValueYield(address _CH, uint _amountYield) internal view returns (uint unitAmountYield) {
		IWrapper wrapper = ICapitalHandler(_CH).wrapper();
		unitAmountYield = wrapper.WrappedAmtToUnitAmt_RoundDown(_amountYield);
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
		@Description: ensure that args for YTvaultWithstandsChange() never increase vault health
			all multipliers should have either no change on vault health or decrease vault health
			we make this a function and not a modifier because we will not always have the
			necessary data ready before execution of the functions in which we want to use this

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
		@param bool _positiveBondSupplied: (ZCB supplied to vault > YT supplied to vault)
	*/
	function validateYTvaultMultipliers(
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange,
		bool _positiveBondSupplied
	) internal pure {
		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_borrowRateChange <= ABDK_1);
		require(
			(_suppliedRateChange == ABDK_1) ||
			(_positiveBondSupplied ? _suppliedRateChange > ABDK_1: _suppliedRateChange < ABDK_1)
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

		require(_capitalHandlerToWrapper[_assetSupplied] != address(0) || _wrapperToUnderlyingAsset[_assetSupplied] != address(0));
		require(vaultWithstandsChange(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, _priceMultiplier, _suppliedRateChange, _borrowRateChange));

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		ICapitalHandler(_assetBorrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(_assetBorrowed, _amountBorrowed);

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
			ICapitalHandler(vault.assetBorrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(vault.assetBorrowed, vault.amountBorrowed);
		}
		if (vault.amountSupplied > 0)
			IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);

		if (len - 1 != _index)
			_vaults[msg.sender][_index] = _vaults[msg.sender][len - 1];
		delete _vaults[msg.sender][len - 1];
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
		) external {

		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		require(vault.amountSupplied >= _amount);
		require(vaultWithstandsChange(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied - _amount,
			vault.amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		_vaults[msg.sender][_index].amountSupplied -= _amount;
		IERC20(vault.assetSupplied).transfer(_to, _amount);
	}

	/*
		@Description: deposit collateral into an exiting vault

		@param address _owner: the owner of the vault to which to supply collateral
		@param uint _index: the index of the vault in vaults[_owner] to which to supply collateral
		@param uint _amount: the amount of the supplied asset to provide as collateral to the vault
	*/
	function deposit(address _owner, uint _index, uint _amount) external {
		require(_vaults[_owner].length > _index);
		IERC20(_vaults[_owner][_index].assetSupplied).transferFrom(msg.sender, address(this), _amount);
		_vaults[_owner][_index].amountSupplied += _amount;
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
		) external {

		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		require(vaultWithstandsChange(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			vault.amountBorrowed + _amount,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		_vaults[msg.sender][_index].amountBorrowed += _amount;

		ICapitalHandler(vault.assetBorrowed).mintZCBTo(_to, _amount);
		raiseShortInterest(vault.assetBorrowed, _amount);
	}

	/*
		@Description: repay the borrowed asset back into a vault

		@param address _owner: the owner of the vault to which to reapy
		@param uint _index: the index of the vault in vaults[_owner] to which to repay
		@param uint _amount: the amount of the borrowed asset to reapy to the vault
	*/
	function repay(address _owner, uint _index, uint _amount) external {
		require(_vaults[_owner].length > _index);
		require(_vaults[_owner][_index].amountBorrowed >= _amount);
		address assetBorrowed = _vaults[_owner][_index].assetBorrowed;
		ICapitalHandler(assetBorrowed).burnZCBFrom(msg.sender, _amount);
		lowerShortInterest(assetBorrowed, _amount);
		_vaults[_owner][_index].amountBorrowed -= _amount;
	}

	//----------------------------------------------YT vault management-----------------------------------

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
	) external {
		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, _bondSupplied > 0);
		uint _unitYieldSupplied = getUnitValueYield(_CHsupplied, _yieldSupplied);

		require(vaultHealthContract.YTvaultWithstandsChange(
			_CHsupplied,
			_CHborrowed,
			_unitYieldSupplied,
			_bondSupplied,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		ICapitalHandler(_CHsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		ICapitalHandler(_CHborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(_CHborrowed, _amountBorrowed);

		_YTvaults[msg.sender].push(YTVault(_CHsupplied, _CHborrowed, _yieldSupplied, _bondSupplied, _amountBorrowed));

	}

	/*
		@Description: fully repay a YT vault and withdraw all collateral

		@param uint _index: the YT vault to close is at YTvaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeYTVault(uint _index, address _to) external {
		uint len = _YTvaults[msg.sender].length;
		require(_index < len);
		YTVault memory vault = _YTvaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0) {
			ICapitalHandler(vault.CHborrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(vault.CHborrowed, vault.amountBorrowed);
		}
		if (vault.yieldSupplied > 0 || vault.bondSupplied != 0) {
			//we already know the vault would pass the check so no need to check
			ICapitalHandler(vault.CHsupplied).transferPosition(_to, vault.yieldSupplied, vault.bondSupplied);
		}

		if (len - 1 != _index)
			_YTvaults[msg.sender][_index] = _YTvaults[msg.sender][len - 1];
		delete _YTvaults[msg.sender][len - 1];
	}

	/*
		@Description: withdraw collateral from an existing vault

		@param uint _index: the vault to close is at vaults[msg.sender][_index]
		@param uint _amountYield: the amount to decrease from vault.yieldSupplied
		@param int _amountBond: the amount to decrease from vault.bondSupplied
		@param address _to: the address to which to send the removed collateral
		@param uint _priceMultiplier: a multiplier > 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			cross asset price of _assetBorrowed to _assetSupplied increases by a factor of _priceMultiplier
			(in terms of basis points)
		@param int128 _suppliedRateChange: a multiplier > 1 if vault.amountBond is positive after change
			otherwise < 1
			we ensure the vault will not be sent into the liquidation zone if the rate on the supplied
			asset increases by a factor of _suppliedRateChange
			(in ABDK format)
		@param int128 _borrowRateChange: a multiplier < 1
			we ensure that after this action the vault will not be sent into the liquidation zone if the
			rate on the borrow asset decreases by a factor of _borrowRateChange
			(in ABDK format)
	*/
	function YTremove(
		uint _index,
		uint _amountYield,
		int _amountBond,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external {
		require(_YTvaults[msg.sender].length > _index);
		YTVault memory vault = _YTvaults[msg.sender][_index];

		//vault is stored in memory does not change state
		vault.yieldSupplied = vault.yieldSupplied.sub(_amountYield);
		vault.bondSupplied = vault.bondSupplied.sub(_amountBond);

		uint unitAmountYield = getUnitValueYield(vault.CHsupplied, vault.yieldSupplied);

		//ensure resultant collateral in vault has valid minimum possible value at maturity
		require(vault.bondSupplied >= 0 || unitAmountYield >= uint(-vault.bondSupplied));

		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, vault.bondSupplied > 0);
		require(vaultHealthContract.YTvaultWithstandsChange(
			vault.CHsupplied,
			vault.CHborrowed,
			unitAmountYield,
			vault.bondSupplied,
			vault.amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		_YTvaults[msg.sender][_index].yieldSupplied = vault.yieldSupplied;
		_YTvaults[msg.sender][_index].bondSupplied = vault.bondSupplied;
		ICapitalHandler(vault.CHsupplied).transferPosition(_to, _amountYield, _amountBond);
	}

	/*
		@Description: deposit collateral into an exiting YT vault

		@param address _owner: the owner of the YT vault to which to supply collateral
		@param uint _index: the index of the vault in YTvaults[_owner] to which to supply collateral
		@param uint _amountYield: the amount to increase vault.yieldSupplied
		@param int _amountBond: the amount to increase vault.bondSupplied
	*/
	function YTdeposit(address _owner, uint _index, uint _amountYield, int _amountBond) external {
		require(_YTvaults[_owner].length > _index);
		YTVault storage storageVault =  _YTvaults[_owner][_index];
		uint resultantYield = storageVault.yieldSupplied.add(_amountYield);
		int resultantBond = storageVault.bondSupplied.add(_amountBond);
		address _CHsupplied = storageVault.CHsupplied;
		uint unitAmountYield = getUnitValueYield(_CHsupplied, resultantYield);
		//ensure vault collateral has positive minimum possible value at maturity
		require(resultantBond >= 0 || unitAmountYield >= uint(-resultantBond));
		//we ensure that the vault has valid balances thus it does not matter if the position passes the check
		ICapitalHandler(_CHsupplied).transferPositionFrom(msg.sender, address(this), _amountYield, _amountBond);
		storageVault.yieldSupplied = resultantYield;
		storageVault.bondSupplied = resultantBond;
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
	function YTborrow(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external {
		require(_YTvaults[msg.sender].length > _index);
		YTVault memory vault = _YTvaults[msg.sender][_index];

		uint resultantBorrowed = vault.amountBorrowed.add(_amount);

		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, vault.bondSupplied > 0);
		require(vaultHealthContract.YTvaultWithstandsChange(
			vault.CHsupplied,
			vault.CHborrowed,
			vault.yieldSupplied,
			vault.bondSupplied,
			resultantBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		_YTvaults[msg.sender][_index].amountBorrowed = resultantBorrowed;

		ICapitalHandler(vault.CHborrowed).mintZCBTo(_to, _amount);
		raiseShortInterest(vault.CHborrowed, _amount);
	}

	/*
		@Description: repay the borrowed asset back into a YT vault

		@param address _owner: the owner of the YT vault to which to reapy
		@param uint _index: the index of the YT vault in YTvaults[_owner] to which to repay
		@param uint _amount: the amount of the borrowed asset to reapy to the YT vault
	*/
	function YTrepay(address _owner, uint _index, uint _amount) external {
		require(_YTvaults[_owner].length > _index);
		require(_YTvaults[_owner][_index].amountBorrowed >= _amount);
		address CHborrowed = _YTvaults[_owner][_index].CHborrowed;
		ICapitalHandler(CHborrowed).burnZCBFrom(msg.sender, _amount);
		lowerShortInterest(CHborrowed, _amount);
		_vaults[_owner][_index].amountBorrowed -= _amount;
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
		require(vault.amountBorrowed >= _amtIn);
		uint maxBid = vault.amountSupplied * _amtIn / vault.amountBorrowed;
		require(maxBid >= _bid);
		if (satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, true)) {
			uint maturity = ICapitalHandler(vault.assetBorrowed).maturity();
			require(maturity < block.timestamp + MAX_TIME_TO_MATURITY);
		}
		//burn borrowed ZCB
		collectBid(msg.sender, vault.assetBorrowed, _amtIn);
		lowerShortInterest(vault.assetBorrowed, _amtIn);
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
		require(_amtIn <= liq.amountBorrowed);
		uint maxBid = liq.bidAmount * _amtIn / liq.amountBorrowed;
		require(_bid < maxBid);

		refundBid(liq.bidder, liq.assetBorrowed, _amtIn);
		collectBid(msg.sender, liq.assetBorrowed, _amtIn);
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
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxBid, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _maxBid);
		require(vault.amountSupplied >= _minOut);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + CRITICAL_TIME_TO_MATURITY || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		ICapitalHandler(_assetBorrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(_assetBorrowed, vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);

		delete _vaults[_owner][_index];
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
	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(_in <= vault.amountBorrowed);
		uint amtOut = _in*vault.amountSupplied/vault.amountBorrowed;
		require(vault.amountSupplied >= amtOut);
		require(amtOut >= _minOut);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB

		ICapitalHandler(_assetBorrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(_assetBorrowed, _in);
		IERC20(_assetSupplied).transfer(_to, amtOut);

		_vaults[_owner][_index].amountBorrowed -= _in;
		_vaults[_owner][_index].amountSupplied -= amtOut;
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
	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountSupplied >= _out);
		uint amtIn = _out*vault.amountBorrowed;
		amtIn = amtIn/vault.amountSupplied + (amtIn%vault.amountSupplied == 0 ? 0 : 1);
		require(amtIn <= _maxIn);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		IERC20(_assetBorrowed).transferFrom(msg.sender, address(0), amtIn);
		IERC20(_assetSupplied).transfer(_to, _out);

		_vaults[_owner][_index].amountBorrowed -= amtIn;
		_vaults[_owner][_index].amountSupplied -= _out;
	}


	//----------------------------------------------------Y-T-V-a-u-l-t---L-i-q-u-i-d-a-t-i-o-n-s-------------------------------------

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
	function auctionYTLiquidation(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _bidYield, int _minBondRatio, uint _amtIn) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		require(vault.CHborrowed == _CHborrowed);
		require(vault.CHsupplied == _CHsupplied);
		require(vault.amountBorrowed >= _amtIn);
		uint maxBid = vault.yieldSupplied * _amtIn / vault.amountBorrowed;
		require(maxBid >= _bidYield);

		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied));
		require(bondRatio >= _minBondRatio);
		int bondBid = bondRatio.mul(int(_bidYield)) / (1 ether);


		if (vaultHealthContract.YTvaultSatisfiesUpperLimit(vault.CHsupplied, vault.CHborrowed, vault.yieldSupplied, vault.bondSupplied, vault.amountBorrowed)) {
			uint maturity = ICapitalHandler(vault.CHborrowed).maturity();
			require(maturity < block.timestamp + MAX_TIME_TO_MATURITY);
		}
		//burn borrowed ZCB
		collectBid(msg.sender, vault.CHborrowed, _amtIn);
		lowerShortInterest(vault.CHborrowed, _amtIn);
		//any surplus in the bid may be added as _revenue
		if (_bidYield < maxBid){
			distributeSurplus(_owner, vault.CHsupplied, maxBid - _bidYield);
		}
		if (_amtIn == vault.amountBorrowed) {
			delete _YTvaults[_owner][_index];
		}
		else {
			_YTvaults[_owner][_index].amountBorrowed -= _amtIn;
			_YTvaults[_owner][_index].yieldSupplied -= maxBid;
			int maxBidBond = bondRatio.mul(int(maxBid)) / (1 ether);
			_YTvaults[_owner][_index].bondSupplied -= maxBidBond;
		}
		_YTLiquidations.push(YTLiquidation(
			_owner,
			vault.CHsupplied,
			vault.CHborrowed,
			bondBid,
			_amtIn,
			msg.sender,
			_bidYield,
			block.timestamp
		));
	}

}