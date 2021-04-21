pragma solidity >=0.6.0;

import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./VaultFactoryData.sol";

/*
	This contract is specifically for handling YTVault functionality
*/
contract VaultFactoryDelegate2 is VaultFactoryData {
	using SafeMath for uint;
	using SignedSafeMath for int;

	/*
		YTVaults must have at least MIN_YIELD_SUPPLIED yield supplied
		This ensures that there are no problems liquidating vaults

		if a user wishes to have no yield supplied to a vault said user
		should use a normal vault and not use a YTvault
	*/
	uint internal constant MIN_YIELD_SUPPLIED = 1e6;

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
		@param address _CHaddr: the address of the capital handler for which to distribte surplus
		@param uint _yieldAmount: value to add to rebate.amountYield
		@param int _bondAmount: value to add to rebate.amountBond
	*/
	function distributeYTSurplus(address _vaultOwner, address _CHaddr, uint _yieldAmount, int _bondAmount) internal {
		YTPosition storage rebate = _YTLiquidationRebates[_vaultOwner][_CHaddr];
		YTPosition storage revenue = _YTRevenue[_CHaddr];
		uint _rebateBips = _liquidationRebateBips;
		uint yieldRebate = _yieldAmount * _rebateBips / TOTAL_BASIS_POINTS;
		int bondRebate = _bondAmount * int(_rebateBips) / int(TOTAL_BASIS_POINTS);
		rebate.amountYield += yieldRebate;
		rebate.amountBond += bondRebate;
		revenue.amountYield += _yieldAmount - yieldRebate;
		revenue.amountBond += _bondAmount - bondRebate;
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
		address wrapperAddr = _capitalHandlerToWrapper[_CH];
		require(wrapperAddr != address(0));
		unitAmountYield = IWrapper(wrapperAddr).WrappedAmtToUnitAmt_RoundDown(_amountYield);
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
			(_positiveBondSupplied ? _suppliedRateChange > ABDK_1 : _suppliedRateChange < ABDK_1)
		);
	}

	/*
		@Description: create a new YT vault, deposit some ZCB + YT of a CH and borrow some ZCB from it

		@param address _CHsupplied: the address of the CH contract for which to supply ZCB and YT
		@param address _CHborrowed: the CH that corresponds to the ZCB that is borrowed from the new YTVault
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
		require(_yieldSupplied >= MIN_YIELD_SUPPLIED);
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

		require(vault.yieldSupplied >= MIN_YIELD_SUPPLIED || (vault.yieldSupplied == 0 && vault.bondSupplied == 0));

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
		require(resultantYield >= MIN_YIELD_SUPPLIED);
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
		_YTvaults[_owner][_index].amountBorrowed -= _amount;
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

		//add 1 to ratio to account for rounding error
		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied)) + 1;
		require(bondRatio >= _minBondRatio);


		if (vaultHealthContract.YTvaultSatisfiesUpperLimit(vault.CHsupplied, vault.CHborrowed, vault.yieldSupplied, vault.bondSupplied, vault.amountBorrowed)) {
			uint maturity = ICapitalHandler(vault.CHborrowed).maturity();
			require(maturity < block.timestamp + MAX_TIME_TO_MATURITY);
		}
		//burn borrowed ZCB
		collectBid(msg.sender, vault.CHborrowed, _amtIn);
		lowerShortInterest(vault.CHborrowed, _amtIn);
		//any surplus in the bid may be added as _revenue
		if (_bidYield < maxBid){
			int bondBid = bondRatio.mul(int(_bidYield)) / (1 ether);
			//int bondCorrespondingToMaxBid = bondRatio.mul(int(maxBid)) / (1 ether);
			int bondCorrespondingToMaxBid = vault.bondSupplied.mul(int(_amtIn)).div(int(vault.amountBorrowed));
			distributeYTSurplus(_owner, vault.CHsupplied, maxBid - _bidYield, bondCorrespondingToMaxBid - bondBid);
		}
		if (_amtIn == vault.amountBorrowed) {
			delete _YTvaults[_owner][_index];
		}
		else {
			_YTvaults[_owner][_index].amountBorrowed -= _amtIn;
			_YTvaults[_owner][_index].yieldSupplied -= maxBid;
			int bondCorrespondingToMaxBid = bondRatio.mul(int(maxBid)) / (1 ether);
			_YTvaults[_owner][_index].bondSupplied -= bondCorrespondingToMaxBid;
		}
		_YTLiquidations.push(YTLiquidation(
			_owner,
			vault.CHsupplied,
			vault.CHborrowed,
			bondRatio,
			_amtIn,
			msg.sender,
			_bidYield,
			block.timestamp
		));
	}

	/*
		@Description: place a new bid on a YT vault that has already begun an auction

		@param uint _index: the index in _YTLiquidations[] of the auction
		@param uint _bidYield: the bid (in YT corresponding _CHsupplied) made by msg.sender on the vault
			ZCB of bid is calculated by finding the corresponding amount of ZCB based on the ratio of YT to ZCB
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnYTLiquidation(uint _index, uint _bidYield, uint _amtIn) external {
		require(_YTLiquidations.length > _index);
		YTLiquidation memory liq = _YTLiquidations[_index];
		require(_amtIn <= liq.amountBorrowed);
		uint maxBid = liq.bidAmount * _amtIn / liq.amountBorrowed;
		require(_bidYield < maxBid);

		refundBid(liq.bidder, liq.CHborrowed, _amtIn);
		collectBid(msg.sender, liq.CHborrowed, _amtIn);

		int bondCorrespondingToMaxBid = liq.bondRatio.mul(int(maxBid)) / (1 ether);
		int bondBid = (liq.bondRatio.mul(int(_bidYield)) / (1 ether)) + 1;
		distributeYTSurplus(liq.vaultOwner, liq.CHsupplied, maxBid - _bidYield, bondCorrespondingToMaxBid - bondBid);

		if (_amtIn == liq.amountBorrowed) {
			_YTLiquidations[_index].bidAmount = _bidYield;
			_YTLiquidations[_index].bidTimestamp = block.timestamp;
			_YTLiquidations[_index].bidder = msg.sender;
		}
		else {
			_YTLiquidations[_index].amountBorrowed -= _amtIn;
			_YTLiquidations[_index].bidAmount -= maxBid;

			_YTLiquidations.push(YTLiquidation(
				liq.vaultOwner,
				liq.CHsupplied,
				liq.CHborrowed,
				liq.bondRatio,
				_amtIn,
				msg.sender,
				_bidYield,
				block.timestamp
			));
		}
	}

	/*
		@Description: claim the collateral of a YT vault from an auction that was won by msg.sender

		@param uint _index: the index in YTLiquidations[] of the auction
		@param address _to: the address to which to send the proceeds
	*/
	function claimYTLiquidation(uint _index, address _to) external {
		require(_YTLiquidations.length > _index);
		YTLiquidation storage liq = _YTLiquidations[_index];
		require(msg.sender == liq.bidder);
		require(block.timestamp >= AUCTION_COOLDOWN + liq.bidTimestamp);
		uint bidAmt = liq.bidAmount;
		int bondBid = (liq.bondRatio-1).mul(int(bidAmt)) / (1 ether);
		ICapitalHandler(liq.CHsupplied).transferPosition(_to, bidAmt, bondBid);

		delete _YTLiquidations[_index];
	}

	/*
		@Description: when there is less than 1 day until maturity or vaults are under the lower collateralisation limit 
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
	function instantYTLiquidation(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _maxIn, uint _minOut, int _minBondRatio, address _to) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		require(vault.CHborrowed == _CHborrowed);
		require(vault.CHsupplied == _CHsupplied);
		require(vault.amountBorrowed <= _maxIn);
		require(vault.yieldSupplied >= _minOut);

		//when we find bondRatio here we don't need to account for the rounding error because the only prupose of this variable is 
		//the require statement below, other than that it has no impact on the distribution of funds
		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied));
		require(bondRatio >= _minBondRatio);

		if (ICapitalHandler(_CHborrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
			require(!vaultHealthContract.YTvaultSatisfiesLowerLimit(
				vault.CHsupplied,
				vault.CHborrowed,
				vault.yieldSupplied,
				vault.bondSupplied,
				vault.amountBorrowed
			));
		}

		//burn borrowed ZCB
		ICapitalHandler(_CHborrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(_CHborrowed, vault.amountBorrowed);
		ICapitalHandler(_CHsupplied).transferPosition(_to, vault.yieldSupplied, vault.bondSupplied);

		delete _YTvaults[_owner][_index];
	}



	/*
		@Description: when there is less than 1 day until maturity or vaults are under the lower collateralisation limit 
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
	function partialYTLiquidationSpecificIn(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _in, uint _minOut, int _minBondRatio, address _to) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		require(vault.CHborrowed == _CHborrowed);
		require(vault.CHsupplied == _CHsupplied);
		require(_in <= vault.amountBorrowed);

		//when we find bondRatio here we don't need to account for the rounding error because the only prupose of this variable is 
		//the require statement below, other than that it has no impact on the distribution of funds
		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied));
		require(bondRatio >= _minBondRatio);
		uint yieldOut = vault.yieldSupplied.mul(_in).div(vault.amountBorrowed);
		require(yieldOut >= _minOut);
		int bondOut = vault.bondSupplied.mul(int(_in)).div(int(vault.amountBorrowed));

		if (ICapitalHandler(_CHborrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
			require(!vaultHealthContract.YTvaultSatisfiesLowerLimit(
				vault.CHsupplied,
				vault.CHborrowed,
				vault.yieldSupplied,
				vault.bondSupplied,
				vault.amountBorrowed
			));
		}
		//burn borrowed ZCB
		ICapitalHandler(_CHborrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(_CHborrowed, _in);
		ICapitalHandler(_CHsupplied).transferPosition(_to, yieldOut, bondOut);

		_YTvaults[_owner][_index].amountBorrowed -= _in;
		_YTvaults[_owner][_index].yieldSupplied -= yieldOut;
		_YTvaults[_owner][_index].bondSupplied -= bondOut;
	}

	/*
		@Description: when there is less than 1 day until maturity or vaults are under the lower collateralisation limit 
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
	function partialYTLiquidationSpecificOut(address _owner, uint _index, address _CHborrowed, address _CHsupplied, uint _out, int _minBondOut, uint _maxIn, address _to) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		require(vault.CHborrowed == _CHborrowed);
		require(vault.CHsupplied == _CHsupplied);
		require(vault.yieldSupplied >= _out);
		uint amtIn = _out*vault.amountBorrowed;
		amtIn = amtIn/vault.yieldSupplied + (amtIn%vault.yieldSupplied == 0 ? 0 : 1);
		require(amtIn <= _maxIn);

		int bondOut = vault.bondSupplied.mul(int(_out)).div(int(vault.yieldSupplied));
		require(bondOut >= _minBondOut);

		if (ICapitalHandler(_CHborrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
			require(!vaultHealthContract.YTvaultSatisfiesLowerLimit(
				vault.CHsupplied,
				vault.CHborrowed,
				vault.yieldSupplied,
				vault.bondSupplied,
				vault.amountBorrowed
			));
		}

		//burn borrowed ZCB
		ICapitalHandler(_CHborrowed).burnZCBFrom(_to, amtIn);
		lowerShortInterest(_CHborrowed, amtIn);
		ICapitalHandler(_CHsupplied).transferPosition(_to, _out, bondOut);

		_YTvaults[_owner][_index].amountBorrowed -= amtIn;
		_YTvaults[_owner][_index].yieldSupplied -= _out;
		_YTvaults[_owner][_index].bondSupplied -= bondOut;
	}

}