// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

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
contract DBSFVaultFactoryDelegate3 is DBSFVaultFactoryData {
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
	*/
	function getUnitValueYield(address _FCP, uint _amountYield) internal view returns (uint unitAmountYield) {
		address wrapperAddr = _fixCapitalPoolToWrapper[_FCP];
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

	function YTvaultWithstandsChange(YTVault memory vault, uint _priceMultiplier, int128 _suppliedRateChange, int128 _borrowRateChange) internal view returns (bool) {
		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, vault.bondSupplied > 0);
		return vaultHealthContract.YTvaultWithstandsChange(
			false,
			vault.FCPsupplied,
			vault.FCPborrowed,
			getUnitValueYield(vault.FCPsupplied, vault.yieldSupplied),
			vault.bondSupplied,
			stabilityFeeAdjAmountBorrowed(vault.FCPborrowed, vault.amountBorrowed, vault.timestampOpened, vault.stabilityFeeAPR),
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		);
	}

	/*
		@Description: create a new YT vault, deposit some ZCB + YT of a FCP and borrow some ZCB from it

		@param address _FCPsupplied: the address of the FCP contract for which to supply ZCB and YT
		@param address _FCPborrowed: the FCP that corresponds to the ZCB that is borrowed from the new YTVault
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
	) external {
		require(_yieldSupplied >= MIN_YIELD_SUPPLIED);
		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, _bondSupplied > 0);
		uint _unitYieldSupplied = getUnitValueYield(_FCPsupplied, _yieldSupplied);

		require(YTvaultWithstandsChange(
			YTVault(
				_FCPsupplied,
				_FCPborrowed,
				_unitYieldSupplied,
				_bondSupplied,
				_amountBorrowed,
				0,
				NO_STABILITY_FEE
			),
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		IFixCapitalPool(_FCPborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(_FCPborrowed, _amountBorrowed);

		IWrapper baseBorrowed = IFixCapitalPool(_FCPborrowed).wrapper();
		uint64 timestampOpened = uint64(baseBorrowed.lastUpdate());
		uint64 wrapperFee = IInfoOracle(_infoOracleAddress).StabilityFeeAPR(address(this), address(baseBorrowed));

		_YTvaults[msg.sender].push(YTVault(_FCPsupplied, _FCPborrowed, _yieldSupplied, _bondSupplied, _amountBorrowed, timestampOpened, wrapperFee));

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
			uint feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(vault.FCPborrowed, vault.amountBorrowed, vault.timestampOpened, vault.stabilityFeeAPR);
			IFixCapitalPool(vault.FCPborrowed).burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			lowerShortInterest(vault.FCPborrowed, vault.amountBorrowed);
		}
		if (vault.yieldSupplied > 0 || vault.bondSupplied != 0) {
			//we already know the vault would pass the check so no need to check
			IFixCapitalPool(vault.FCPsupplied).transferPosition(_to, vault.yieldSupplied, vault.bondSupplied);
		}

		delete _YTvaults[msg.sender][_index];
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
	) external {
		require(_index < _YTvaults[_owner].length);

		YTVault memory mVault = _YTvaults[_owner][_index];
		YTVault storage sVault = _YTvaults[_owner][_index];

		if (mVault.FCPborrowed == _FCPborrowed) {
			//ensure that after operations vault will be in good health
			//only check health if at any point funds are being removed from the vault
			if (
				_FCPsupplied != mVault.FCPsupplied ||
				_yieldSupplied < mVault.yieldSupplied ||
				_amountBorrowed > mVault.amountBorrowed ||
				(_yieldSupplied == mVault.yieldSupplied && _bondSupplied < mVault.bondSupplied)
			) {
				require(_multipliers[0] > 0);
				require(msg.sender == _owner);
				require(YTvaultWithstandsChange(
					YTVault(
						_FCPsupplied,
						_FCPborrowed,
						_yieldSupplied,
						_bondSupplied,
						_amountBorrowed,
						mVault.timestampOpened,
						mVault.stabilityFeeAPR
					),
					uint(_multipliers[0]),
					_multipliers[1],
					_multipliers[2]
				));
			}
			adjYTVaultSameBorrow(
				mVault,
				sVault,
				_FCPsupplied,
				_FCPborrowed,
				_yieldSupplied,
				_bondSupplied,
				_amountBorrowed,
				_data,
				_receiverAddr
			);
		}
		else {
			require(_multipliers[0] > 0);
			require(msg.sender == _owner);
			require(YTvaultWithstandsChange(
				YTVault(
					_FCPsupplied,
					_FCPborrowed,
					_yieldSupplied,
					_bondSupplied,
					_amountBorrowed,
					0,
					NO_STABILITY_FEE
				),
				uint(_multipliers[0]),
				_multipliers[1],
				_multipliers[2]
			));
			adjYTVaultChangeBorrow(
				mVault,
				sVault,
				_FCPsupplied,
				_FCPborrowed,
				_yieldSupplied,
				_bondSupplied,
				_amountBorrowed,
				_data,
				_receiverAddr
			);
		}
	}

	function adjYTVaultSameBorrow(
		YTVault memory mVault,
		YTVault storage sVault,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		bytes memory _data,
		address _receiverAddr
	) internal {
		if (mVault.FCPsupplied != _FCPsupplied) {
			if (mVault.FCPsupplied != address(0)) {
				IFixCapitalPool(mVault.FCPsupplied).transferPosition(_receiverAddr, mVault.yieldSupplied, mVault.bondSupplied);
			}
			sVault.FCPsupplied = _FCPsupplied;
			sVault.yieldSupplied = _yieldSupplied;
			sVault.bondSupplied = _bondSupplied;
		}
		else if (mVault.yieldSupplied != _yieldSupplied) {
			if (mVault.yieldSupplied > _yieldSupplied) {
				IFixCapitalPool(_FCPsupplied).transferPosition(_receiverAddr, mVault.yieldSupplied - _yieldSupplied, mVault.bondSupplied.sub(_bondSupplied));
			}
			sVault.yieldSupplied = _yieldSupplied;
		}
		if (mVault.bondSupplied != _bondSupplied) {
			if (mVault.bondSupplied > _bondSupplied && mVault.yieldSupplied == _yieldSupplied) {
				IFixCapitalPool(_FCPsupplied).transferPosition(_receiverAddr, 0, mVault.bondSupplied.sub(_bondSupplied));
			}
			sVault.bondSupplied = _bondSupplied;
		}

		if (mVault.amountBorrowed < _amountBorrowed) {
			uint toMint = stabilityFeeAdjAmountBorrowed(_FCPborrowed, _amountBorrowed - mVault.amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, toMint);
			raiseShortInterest(_FCPborrowed, _amountBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = _amountBorrowed;
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			sVault.amountBorrowed = _amountBorrowed;
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			IYTVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				mVault.FCPsupplied,
				mVault.FCPborrowed,
				mVault.yieldSupplied,
				mVault.bondSupplied,
				mVault.amountBorrowed,
				_data
			);
		}

		//-----------------------------get funds-------------------------
		if (mVault.FCPsupplied != _FCPsupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		}
		else if (mVault.yieldSupplied != _yieldSupplied) {
			if (mVault.yieldSupplied < _yieldSupplied) {
				IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied - mVault.yieldSupplied, _bondSupplied.sub(mVault.bondSupplied));
			}
		}
		else if (mVault.bondSupplied < _bondSupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(_receiverAddr, address(this), 0, _bondSupplied.sub(mVault.bondSupplied));
		}

		if (mVault.amountBorrowed > _amountBorrowed) {
			lowerShortInterest(_FCPborrowed, mVault.amountBorrowed - _amountBorrowed);
			uint toBurn = stabilityFeeAdjAmountBorrowed(_FCPborrowed, mVault.amountBorrowed - _amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			IFixCapitalPool(_FCPborrowed).burnZCBFrom(msg.sender,  toBurn);
			address ZCBborrowed = IFixCapitalPool(_FCPborrowed).zeroCouponBondAddress();
			claimStabilityFee(ZCBborrowed, address(_FCPborrowed), toBurn - (mVault.amountBorrowed - _amountBorrowed));
		}
	}

	function adjYTVaultChangeBorrow(
		YTVault memory mVault,
		YTVault storage sVault,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _yieldSupplied,
		int _bondSupplied,
		uint _amountBorrowed,
		bytes memory _data,
		address _receiverAddr
	) internal {
		if (mVault.FCPsupplied != _FCPsupplied) {
			if (mVault.FCPsupplied != address(0)) {
				IFixCapitalPool(mVault.FCPsupplied).transferPosition(_receiverAddr, mVault.yieldSupplied, mVault.bondSupplied);
			}
			sVault.FCPsupplied = _FCPsupplied;
			sVault.yieldSupplied = _yieldSupplied;
			sVault.bondSupplied = _bondSupplied;
		}
		else if (mVault.yieldSupplied != _yieldSupplied) {
			if (mVault.yieldSupplied > _yieldSupplied) {
				IFixCapitalPool(_FCPsupplied).transferPosition(_receiverAddr, mVault.yieldSupplied - _yieldSupplied, mVault.bondSupplied.sub(_bondSupplied));
			}
			sVault.yieldSupplied = _yieldSupplied;
		}
		if (mVault.bondSupplied != _bondSupplied) {
			if (mVault.bondSupplied > _bondSupplied && mVault.yieldSupplied == _yieldSupplied) {
				IFixCapitalPool(_FCPsupplied).transferPosition(_receiverAddr, 0, mVault.bondSupplied.sub(_bondSupplied));
			}
			sVault.bondSupplied = _bondSupplied;
		}

		if (_FCPborrowed != address(0)) {
			raiseShortInterest(_FCPborrowed, _amountBorrowed);
		}
		if (mVault.FCPborrowed != address(0)) {
			lowerShortInterest(mVault.FCPborrowed, mVault.amountBorrowed);
		}
		IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, _amountBorrowed);
		sVault.FCPborrowed = _FCPborrowed;
		sVault.amountBorrowed = _amountBorrowed;
		{
			IWrapper wrapper = IFixCapitalPool(_FCPborrowed).wrapper();
			sVault.timestampOpened = uint64(wrapper.lastUpdate());
			sVault.stabilityFeeAPR = IInfoOracle(_infoOracleAddress).StabilityFeeAPR(address(this), address(wrapper));
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			IYTVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				mVault.FCPsupplied,
				mVault.FCPborrowed,
				mVault.yieldSupplied,
				mVault.bondSupplied,
				mVault.amountBorrowed,
				_data
			);
		}

		//-----------------------------get funds-------------------------
		if (mVault.FCPsupplied != _FCPsupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		}
		else if (mVault.yieldSupplied != _yieldSupplied) {
			if (mVault.yieldSupplied < _yieldSupplied) {
				IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied - mVault.yieldSupplied, _bondSupplied.sub(mVault.bondSupplied));
			}
		}
		else if (mVault.bondSupplied < _bondSupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(_receiverAddr, address(this), 0, _bondSupplied.sub(mVault.bondSupplied));
		}

		if (mVault.amountBorrowed > 0) {
			uint toBurn = stabilityFeeAdjAmountBorrowed(mVault.FCPborrowed, mVault.amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			IFixCapitalPool(mVault.FCPborrowed).burnZCBFrom(msg.sender, toBurn);
			address ZCBborrowed = IFixCapitalPool(mVault.FCPborrowed).zeroCouponBondAddress();
			claimStabilityFee(ZCBborrowed, mVault.FCPborrowed, toBurn - mVault.amountBorrowed);
		}
	}

	//----------------------------------------------------Y-T-V-a-u-l-t---L-i-q-u-i-d-a-t-i-o-n-s-------------------------------------

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


		if (vaultHealthContract.YTvaultSatisfiesUpperLimit(vault.FCPsupplied, vault.FCPborrowed, vault.yieldSupplied, vault.bondSupplied, vault.amountBorrowed)) {
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