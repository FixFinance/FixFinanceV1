// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/BigMath.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IYTVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./DBSFVaultFactoryData.sol";

/*
	This contract is specifically for handling YTVault functionality
*/
contract DBSFVaultFactoryDelegate4 is DBSFVaultFactoryData {
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
		@param address _FCPaddr: the address of the fix capital pool for which to distribte surplus
		@param uint _yieldAmount: value to add to rebate.amountYield
		@param int _bondAmount: value to add to rebate.amountBond
	*/
	function distributeYTSurplus(address _vaultOwner, address _FCPaddr, uint _yieldAmount, int _bondAmount) internal {
		YTPosition storage rebate = _YTLiquidationRebates[_vaultOwner][_FCPaddr];
		YTPosition storage revenue = _YTRevenue[_FCPaddr];
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
		IFixCapitalPool(_asset).mintZCBTo(_bidder, _amount);
	}

	/*
		@Description: when a bidder makes a bid collect collateral for their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the asset that the bidder is posing as collateral
		@param uint _amount: the amount of _asset that the bidder is required to post
	*/
	function collectBid(address _bidder, address _asset, uint _amount) internal {
		IFixCapitalPool(_asset).burnZCBFrom(_bidder, _amount);
	}

	/*
		@Description: when stability fee is encured pay out to holders

		@param address _ZCBaddr: the ZCB for which to distribute the stability fee
		@param address _FCPaddr: the FCP which corresponds to the ZCB which the stability fee is paid in
		@param uint _amount: the amount of ZCB which has been collected from the stability fee
	*/
	function claimStabilityFee(address _ZCBaddr, address _FCPaddr, uint _amount) internal {
		if (_amount > 0) {
			IFixCapitalPool(_FCPaddr).mintZCBTo(address(this), _amount);
			_revenue[_ZCBaddr] += _amount;
		}
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
		addr = IInfoOracle(_infoOracleAddress).collateralWhitelist(address(this), _suppliedAsset);
		if (addr == address(0) || addr == address(1)) {
			addr = _suppliedAsset;
			amt = _suppliedAmount;
		}
		else {
			amt = IWrapper(_suppliedAsset).WrappedAmtToUnitAmt_RoundDown(_suppliedAmount);
		}
	}


	/*
		@Description: given a fix capital pool and a balance from the balanceYield mapping
			convert the value from wrapped amount to unit amount

		@param address _FCP: the address of the FCP contract
		@param uint _amountYield: the wrapper amount to convert to unit amount

		@return uint unitAmountYield: _amountYield of FCP wrapped yield converted to unit amount
	*/
	function getUnitValueYield(address _FCP, uint _amountYield) internal view returns (uint unitAmountYield) {
		address wrapperAddr = address(IFixCapitalPool(_FCP).wrapper());
		require(wrapperAddr != address(0));
		unitAmountYield = IWrapper(wrapperAddr).WrappedAmtToUnitAmt_RoundDown(_amountYield);
	}

	/*
		@Description: given an amount of wrapped token and a FCP contract which is based on the same wrapper
			convert an amount of wrapped token into the current amount of ZCB that is a subasset of the wrapped token

		@param address _FCP: the address of the FCP contract for which to find the amount of ZCB
		@param uint _amountWrapped: the amount of wrapped token for which to find the amount of ZCB as a subasset
	*/
	function getZCBcontainedInWrappedAmt(address _FCP, uint _amountWrapped) internal view returns (uint amountZCB) {
		if (IFixCapitalPool(_FCP).inPayoutPhase()) {
			uint conversionRate = IFixCapitalPool(_FCP).maturityConversionRate();
			amountZCB = conversionRate.mul(_amountWrapped) / (1 ether);
		}
		else {
			amountZCB = getUnitValueYield(_FCP, _amountWrapped);
		}
	}

	/*
		@Description: if a YTVault has the same FCPborrowed and FCPsupplied pay back as much debt as possible
			with the zcb contained as collateral in the vault
			this can only be done where FCPborrowed == FCPsupplied because the ZCB that is collateral is the
			same ZCB as the debt, this will not be true for any other type of Vault or YTVault

		@param address _owner: the owner of the YTVault for which to pay back debt
		@param uint _index: the index of the YTVault swithin YTvaults[_owner]
		@param YTVault memory _vault: this parameter will be modified if debt is paid back
			when this function is finished executing all member variables of _vault will == the member variables of
			the storage vault which _vault is a copy of
	*/
	function autopayYTVault(address _owner, uint _index, YTVault memory _vault) internal {
		if (_vault.FCPborrowed == _vault.FCPsupplied) {
			uint unitValueYield = getZCBcontainedInWrappedAmt(_vault.FCPborrowed, _vault.yieldSupplied);
			uint difference = _vault.bondSupplied >= 0 ? unitValueYield.add(uint(_vault.bondSupplied)) : unitValueYield.sub(uint(-_vault.bondSupplied));
			difference = difference > _vault.amountBorrowed ? _vault.amountBorrowed : difference;
			if (difference > 0) {
				_vault.bondSupplied -= int(difference);
				_vault.amountBorrowed -= difference;
				_YTvaults[_owner][_index].bondSupplied = _vault.bondSupplied;
				_YTvaults[_owner][_index].amountBorrowed = _vault.amountBorrowed;
			}
		}
	}

	/*
		@Description: find the multiplier which is multiplied with amount borrowed (when vault was opened)
			to find the current liability

		@param address _FCPborrrowed: the address of the FCP contract associated with the debt asset of the Vault
		@param uint64 _timestampOpened: the time at which the vault was opened
		@param uint64 _stabilityFeeAPR: the annual rate which must be paid for stability fees

		@return uint: the stability rate debt multiplier
			inflated by (1 ether)
	*/
	function getStabilityFeeMultiplier(address _FCPborrrowed, uint64 _timestampOpened, uint64 _stabilityFeeAPR) internal view returns(uint) {
		if (_stabilityFeeAPR == 0 || _stabilityFeeAPR == NO_STABILITY_FEE)
			return (1 ether);
		uint lastUpdate = IFixCapitalPool(_FCPborrrowed).lastUpdate();
		int128 yearsOpen = int128((uint(lastUpdate - _timestampOpened) << 64) / BigMath.SecondsPerYear);
		if (yearsOpen == 0)
			return (1 ether);
		int128 stabilityFeeMultiplier = BigMath.Pow(int128(uint(_stabilityFeeAPR) << 32), yearsOpen);
		return uint(stabilityFeeMultiplier).mul(1 ether) >> 64;
	}

	/*
		@Description: find the new amount of ZCBs which is a vault's obligation

		@param address _FCPborrrowed: the address of the FCP contract associated with the debt asset of the Vault
		@param uint _amountBorrowed: the Vault's previous obligation in ZCBs at _timestampOpened
		@param uint64 _timestampOpened: the time at which the vault was opened
		@param uint64 _stabilityFeeAPR: the annual rate which must be paid for stability fees

		@return uint: the stability rate debt multiplier
			inflated by (1 ether)
	*/
	function stabilityFeeAdjAmountBorrowed(address _FCPborrrowed, uint _amountBorrowed, uint64 _timestampOpened, uint64 _stabilityFeeAPR) internal view returns (uint) {
		uint ratio = getStabilityFeeMultiplier(_FCPborrrowed, _timestampOpened, _stabilityFeeAPR);
		return ratio.mul(_amountBorrowed) / (1 ether);
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
	function auctionYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _bidYield, int _minBondRatio, uint _amtIn) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		autopayYTVault(_owner, _index, vault);
		require(vault.FCPborrowed == _FCPborrowed);
		require(vault.FCPsupplied == _FCPsupplied);
		require(vault.amountBorrowed >= _amtIn && _amtIn > 0);
		uint maxBid = vault.yieldSupplied * _amtIn / vault.amountBorrowed;
		require(maxBid >= _bidYield);

		//add 1 to ratio to account for rounding error
		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied)) + 1;
		require(bondRatio >= _minBondRatio);


		if (vaultHealthContract.YTvaultSatisfiesUpperLimit(vault.FCPsupplied, vault.FCPborrowed, getUnitValueYield(vault.FCPsupplied, vault.yieldSupplied), vault.bondSupplied, vault.amountBorrowed)) {
			uint maturity = IFixCapitalPool(vault.FCPborrowed).maturity();
			require(maturity < block.timestamp + MAX_TIME_TO_MATURITY);
		}
		//burn borrowed ZCB
		uint feeAdjAmtIn = stabilityFeeAdjAmountBorrowed(_FCPborrowed, _amtIn, vault.timestampOpened, vault.stabilityFeeAPR);
		collectBid(msg.sender, _FCPborrowed, feeAdjAmtIn);
		claimStabilityFee(IFixCapitalPool(_FCPborrowed).zeroCouponBondAddress(), _FCPborrowed, feeAdjAmtIn - _amtIn);
		lowerShortInterest(_FCPborrowed, _amtIn);
		//any surplus in the bid may be added as _revenue
		if (_bidYield < maxBid){
			int bondBid = bondRatio.mul(int(_bidYield)) / (1 ether);
			//int bondCorrespondingToMaxBid = bondRatio.mul(int(maxBid)) / (1 ether);
			int bondCorrespondingToMaxBid = vault.bondSupplied.mul(int(_amtIn)).div(int(vault.amountBorrowed));
			distributeYTSurplus(_owner, vault.FCPsupplied, maxBid - _bidYield, bondCorrespondingToMaxBid - bondBid);
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
			vault.FCPsupplied,
			vault.FCPborrowed,
			bondRatio,
			feeAdjAmtIn,
			msg.sender,
			_bidYield,
			block.timestamp
		));
	}

	/*
		@Description: place a new bid on a YT vault that has already begun an auction

		@param uint _index: the index in _YTLiquidations[] of the auction
		@param uint _bidYield: the bid (in YT corresponding _FCPsupplied) made by msg.sender on the vault
			ZCB of bid is calculated by finding the corresponding amount of ZCB based on the ratio of YT to ZCB
		@param uint _amtIn: the amount of borrowed asset that the liquidator will be sending in
	*/
	function bidOnYTLiquidation(uint _index, uint _bidYield, uint _amtIn) external {
		require(_YTLiquidations.length > _index);
		YTLiquidation memory liq = _YTLiquidations[_index];
		require(0 < _amtIn && _amtIn <= liq.amountBorrowed);
		uint maxBid = liq.bidAmount * _amtIn / liq.amountBorrowed;
		require(_bidYield < maxBid);

		refundBid(liq.bidder, liq.FCPborrowed, _amtIn);
		collectBid(msg.sender, liq.FCPborrowed, _amtIn);

		int bondCorrespondingToMaxBid = liq.bondRatio.mul(int(maxBid)) / (1 ether);
		int bondBid = (liq.bondRatio.mul(int(_bidYield)) / (1 ether)) + 1;
		distributeYTSurplus(liq.vaultOwner, liq.FCPsupplied, maxBid - _bidYield, bondCorrespondingToMaxBid - bondBid);

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
				liq.FCPsupplied,
				liq.FCPborrowed,
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
		IFixCapitalPool(liq.FCPsupplied).transferPosition(_to, bidAmt, bondBid);

		delete _YTLiquidations[_index];
	}

	/*
		@Description: when there is less than 1 day until maturity or vaults are under the lower collateralisation limit 
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
	function instantYTLiquidation(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _maxIn, uint _minOut, int _minBondRatio, address _to) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		autopayYTVault(_owner, _index, vault);
		require(vault.FCPborrowed == _FCPborrowed);
		require(vault.FCPsupplied == _FCPsupplied);
		require(vault.amountBorrowed <= _maxIn);
		require(vault.yieldSupplied >= _minOut && _minOut > 0);

		//when we find bondRatio here we don't need to account for the rounding error because the only prupose of this variable is 
		//the require statement below, other than that it has no impact on the distribution of funds
		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied));
		require(bondRatio >= _minBondRatio);


		if (IFixCapitalPool(_FCPborrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
			uint unitAmountYield = getUnitValueYield(vault.FCPsupplied, vault.yieldSupplied);
	
			require(!vaultHealthContract.YTvaultSatisfiesLowerLimit(
				vault.FCPsupplied,
				vault.FCPborrowed,
				unitAmountYield,
				vault.bondSupplied,
				vault.amountBorrowed
			));
		}

		//burn borrowed ZCB
		IFixCapitalPool(_FCPborrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(_FCPborrowed, vault.amountBorrowed);
		IFixCapitalPool(_FCPsupplied).transferPosition(_to, vault.yieldSupplied, vault.bondSupplied);

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
		@param address _FCPborrowed: the address of the FCP contract corresponding to the borrowed ZCB
		@param address _FCPsupplied: the address of the FCP contract corresponding to the supplied ZCB & YT
		@param uint _in: the amount of the borrowed asset to supply to the vault
		@param int _minBondRatio: the minimum value of vault.bondSupplied / vault.yieldSupplied inflated by (1 ether)
			if the actual bond ratio of the vault is < _minBondRatio tx will revert
		@param uint _minOut: the minimum amount of YT from _FCPsupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function partialYTLiquidationSpecificIn(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _in, uint _minOut, int _minBondRatio, address _to) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		autopayYTVault(_owner, _index, vault);
		require(vault.FCPborrowed == _FCPborrowed);
		require(vault.FCPsupplied == _FCPsupplied);
		require(0 < _in && _in <= vault.amountBorrowed);

		//when we find bondRatio here we don't need to account for the rounding error because the only prupose of this variable is 
		//the require statement below, other than that it has no impact on the distribution of funds
		int bondRatio = vault.bondSupplied.mul(1 ether).div(int(vault.yieldSupplied));
		require(bondRatio >= _minBondRatio);
		uint yieldOut = vault.yieldSupplied.mul(_in).div(vault.amountBorrowed);
		require(yieldOut >= _minOut);
		int bondOut = vault.bondSupplied.mul(int(_in)).div(int(vault.amountBorrowed));

		if (IFixCapitalPool(_FCPborrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
			uint unitAmountYield = getUnitValueYield(vault.FCPsupplied, vault.yieldSupplied);
	
			require(!vaultHealthContract.YTvaultSatisfiesLowerLimit(
				vault.FCPsupplied,
				vault.FCPborrowed,
				unitAmountYield,
				vault.bondSupplied,
				vault.amountBorrowed
			));
		}
		//burn borrowed ZCB
		IFixCapitalPool(_FCPborrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(_FCPborrowed, _in);
		IFixCapitalPool(_FCPsupplied).transferPosition(_to, yieldOut, bondOut);

		_YTvaults[_owner][_index].amountBorrowed -= _in;
		_YTvaults[_owner][_index].yieldSupplied -= yieldOut;
		_YTvaults[_owner][_index].bondSupplied -= bondOut;
	}

	/*
		@Description: when there is less than 1 day until maturity or vaults are under the lower collateralisation limit 
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
	function partialYTLiquidationSpecificOut(address _owner, uint _index, address _FCPborrowed, address _FCPsupplied, uint _out, int _minBondOut, uint _maxIn, address _to) external {
		require(_YTvaults[_owner].length > _index);
		YTVault memory vault = _YTvaults[_owner][_index];
		autopayYTVault(_owner, _index, vault);
		require(vault.FCPborrowed == _FCPborrowed);
		require(vault.FCPsupplied == _FCPsupplied);
		require(vault.yieldSupplied >= _out);
		uint amtIn = _out*vault.amountBorrowed;
		amtIn = amtIn/vault.yieldSupplied + (amtIn%vault.yieldSupplied == 0 ? 0 : 1);
		require(0 < amtIn && amtIn <= _maxIn);

		int bondOut = vault.bondSupplied.mul(int(_out)).div(int(vault.yieldSupplied));
		require(bondOut >= _minBondOut);

		if (IFixCapitalPool(_FCPborrowed).maturity() >= block.timestamp + CRITICAL_TIME_TO_MATURITY) {
			uint unitAmountYield = getUnitValueYield(vault.FCPsupplied, vault.yieldSupplied);

			require(!vaultHealthContract.YTvaultSatisfiesLowerLimit(
				vault.FCPsupplied,
				vault.FCPborrowed,
				unitAmountYield,
				vault.bondSupplied,
				vault.amountBorrowed
			));
		}

		//burn borrowed ZCB
		IFixCapitalPool(_FCPborrowed).burnZCBFrom(_to, amtIn);
		lowerShortInterest(_FCPborrowed, amtIn);
		IFixCapitalPool(_FCPsupplied).transferPosition(_to, _out, bondOut);

		_YTvaults[_owner][_index].amountBorrowed -= amtIn;
		_YTvaults[_owner][_index].yieldSupplied -= _out;
		_YTvaults[_owner][_index].bondSupplied -= bondOut;
	}

}