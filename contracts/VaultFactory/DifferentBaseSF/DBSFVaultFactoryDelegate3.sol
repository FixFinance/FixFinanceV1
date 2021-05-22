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
		@Description: when stability fee is encured pay out to holders

		@param address _FCPaddr: the FCP which corresponds to the ZCB which the stability fee is paid in
		@param uint _amount: the amount of ZCB which has been collected from the stability fee
	*/
	function claimStabilityFee(address _FCPaddr, uint _amount) internal {
		address ZCBaddr = IFixCapitalPool(_FCPaddr).zeroCouponBondAddress();
		if (_amount > 0) {
			IFixCapitalPool(_FCPaddr).mintZCBTo(address(this), _amount);
			_revenue[ZCBaddr] += _amount;
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

	/*
		@Description: given a YTVault and change multipliers ensure that if a change of the multipliers would not
			result in the YTVault being in danger of liquidation

		@param YTVault memory vault: the YTVault for which to ensure will not be liquidated
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

		_YTvaults[msg.sender].push(YTVault(_FCPsupplied, _FCPborrowed, _yieldSupplied, _bondSupplied, _amountBorrowed, 0, timestampOpened, wrapperFee));

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
			uint sFee = vault.amountSFee;
			sFee += feeAdjBorrowAmt - vault.amountBorrowed;
			if (sFee > 0) {
				claimStabilityFee(vault.FCPborrowed, sFee);
			}
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
						0,
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

	/*
		@Description: adjust the state of a YT vault by either changing the assets in it
			or paying down/increasing debt or supplying/withdrawing collateral
			if the _data param has length > 0, assets sent out by the vault will be sent via flashloan
			and repayment must be made in the required collateral assets 
			this function specifically handles the case where the borrow asset is not being changed

		@param YTVault memory mVault: stores the state of the vault prior to execution of this function
		@param YTVault storage sVault: reference to the storage location where the data from the vault is located
		@param address _FCPsupplied: the new FCP (may be the same as previous) corresponding to the vault's
			ZCB & YT collateral
		@param address _FCPborrowed: the new FCP (may be the same as previous) corresponding to the ZCB
			that is to be borrowed from the vault
		@param uint _yieldSupplied: the amount from the balanceYield mapping in the supplied FCP contract
			that will be supplied as collateral to the YTVault after execution
		@param int _bondSupplied: the amount from the balanceBonds mapping in the supplied FCP contract
			that will be supplied as collateral to the YTVault after execution
		@param uint _amountBorrowed: the total amount of debt of the vault after execution
		@param bytes calldata _data: data to be send to the flashloan receiver if a flashloan is to be done
			if _data.length == 0 there will be no flashloan
		@param  address _receiverAddr: the address of the flashloan receiver contract
	*/
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


		uint change;
		uint adjSFee;
		if (mVault.amountBorrowed < _amountBorrowed) {
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(_FCPborrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			change = stabilityFeeMultiplier.mul(_amountBorrowed - mVault.amountBorrowed) / (1 ether);
			IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, change);
			uint adjBorrowed = stabilityFeeMultiplier.mul(_amountBorrowed) / (1 ether);
			raiseShortInterest(_FCPborrowed, adjBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = adjBorrowed;
			{
				uint temp = stabilityFeeMultiplier.sub(1 ether).mul(mVault.amountBorrowed) / (1 ether);
				adjSFee = mVault.amountSFee.add(temp);
				sVault.amountSFee = adjSFee;
			}
			sVault.timestampOpened = uint64(IFixCapitalPool(_FCPborrowed).lastUpdate());
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(_FCPborrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			change = stabilityFeeMultiplier.mul(mVault.amountBorrowed - _amountBorrowed) / (1 ether); //amt to burn
			uint adjBorrowed = stabilityFeeMultiplier.mul(_amountBorrowed) / (1 ether);
			if (adjBorrowed > mVault.amountBorrowed) {
				raiseShortInterest(_FCPborrowed, adjBorrowed - mVault.amountBorrowed);
			}
			else {
				lowerShortInterest(_FCPborrowed, mVault.amountBorrowed - adjBorrowed);
			}
			sVault.amountBorrowed = adjBorrowed;
			{
				uint temp = stabilityFeeMultiplier.sub(1 ether).mul(mVault.amountBorrowed) / (1 ether);
				adjSFee = mVault.amountSFee.add(temp);
				if (change > adjSFee) {
					sVault.amountSFee = 0;
				}
				else {
					sVault.amountSFee = adjSFee - change;
				}
			}
			sVault.timestampOpened = uint64(IFixCapitalPool(_FCPborrowed).lastUpdate());
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			address FCPsupplied = mVault.FCPsupplied;
			address FCPborrowed = mVault.FCPborrowed;
			uint yieldSupplied = mVault.yieldSupplied;
			int bondSupplied = mVault.bondSupplied;
			uint amountBorrowed = mVault.amountBorrowed;
			bytes memory data = _data;
			IYTVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				FCPsupplied,
				FCPborrowed,
				yieldSupplied,
				bondSupplied,
				amountBorrowed,
				data
			);
		}

		//-----------------------------get funds-------------------------
		if (mVault.FCPsupplied != _FCPsupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		}
		else if (mVault.yieldSupplied != _yieldSupplied) {
			if (mVault.yieldSupplied < _yieldSupplied) {
				uint yield = _yieldSupplied - mVault.yieldSupplied;
				int bond = _bondSupplied.sub(mVault.bondSupplied);
				IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), yield, bond);
			}
		}
		else if (mVault.bondSupplied < _bondSupplied) {
			int bond = _bondSupplied.sub(mVault.bondSupplied);
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(_receiverAddr, address(this), 0, bond);
		}

		if (mVault.amountBorrowed > _amountBorrowed) {
			IFixCapitalPool(_FCPborrowed).burnZCBFrom(msg.sender,  change);
			claimStabilityFee(_FCPborrowed, adjSFee < change ? adjSFee : change);
		}
	}

	/*
		@Description: adjust the state of a YT vault by either changing the assets in it
			or paying down/increasing debt or supplying/withdrawing collateral
			if the _data param has length > 0, assets sent out by the vault will be sent via flashloan
			and repayment must be made in the required collateral assets 
			this function specifically handles the case where the borrow asset is being changed

		@param YTVault memory mVault: stores the state of the vault prior to execution of this function
		@param YTVault storage sVault: reference to the storage location where the data from the vault is located
		@param address _FCPsupplied: the new FCP (may be the same as previous) corresponding to the vault's
			ZCB & YT collateral
		@param address _FCPborrowed: the new FCP (may be the same as previous) corresponding to the ZCB
			that is to be borrowed from the vault
		@param uint _yieldSupplied: the amount from the balanceYield mapping in the supplied FCP contract
			that will be supplied as collateral to the YTVault after execution
		@param int _bondSupplied: the amount from the balanceBonds mapping in the supplied FCP contract
			that will be supplied as collateral to the YTVault after execution
		@param uint _amountBorrowed: the total amount of debt of the vault after execution
		@param bytes calldata _data: data to be send to the flashloan receiver if a flashloan is to be done
			if _data.length == 0 there will be no flashloan
		@param  address _receiverAddr: the address of the flashloan receiver contract
	*/
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
			IWrapper wrapper = IFixCapitalPool(_FCPborrowed).wrapper();
			sVault.timestampOpened = uint64(wrapper.lastUpdate());
			sVault.stabilityFeeAPR = IInfoOracle(_infoOracleAddress).StabilityFeeAPR(address(this), address(wrapper));
		}
		else {
			require(_amountBorrowed == 0);
		}
		if (mVault.FCPborrowed != address(0)) {
			lowerShortInterest(mVault.FCPborrowed, mVault.amountBorrowed);
		}
		IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, _amountBorrowed);
		sVault.FCPborrowed = _FCPborrowed;
		sVault.amountBorrowed = _amountBorrowed;
		if (mVault.amountSFee > 0) {
			sVault.amountSFee = 0;
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
			claimStabilityFee(mVault.FCPborrowed, toBurn - mVault.amountBorrowed);
		}
	}
}