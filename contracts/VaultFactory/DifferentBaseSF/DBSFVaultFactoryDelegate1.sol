// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/BigMath.sol";
import "../../interfaces/IDBSFVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./DBSFVaultFactoryDelegateParent.sol";

contract DBSFVaultFactoryDelegate1 is DBSFVaultFactoryDelegateParent {
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
		if (_amount > 0) {
			address underlyingAssetAddress = IFixCapitalPool(_fixCapitalPoolAddress).underlyingAssetAddress();
			_shortInterestAllDurations[underlyingAssetAddress] = _shortInterestAllDurations[underlyingAssetAddress].sub(_amount);
		}
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
		@Description: ensure that we pass the address of the underlying asset of wrapper assets to
			the vault health contract rather than the address of the wrapper asset
			also ensure that we adjust the amount from the wrapped amount to the non wrapped amount
			if necessary

		@param Vault memory _vault: the vault for which to find the info to pass to the vault health contract
		@param address _whitelistAddr: the output of the collateralWhitelist mapping when the supplied asset is passed

		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint sAmt: the amount for amountSupplied to pass to the vault health contract
		@return uint bAmt: the amounf for amountBorrowed to pass to the vault health contract
	*/
	function passInfoToVaultManager(Vault memory _vault, address _whitelistAddr) internal view returns (address addr, uint sAmt, uint bAmt) {
		addr = _whitelistAddr;
		if (addr == address(0) || addr == address(1)) {
			addr = _vault.assetSupplied;
			sAmt = _vault.amountSupplied;
		}
		else {
			sAmt = IWrapper(_vault.assetSupplied).WrappedAmtToUnitAmt_RoundDown(_vault.amountSupplied);
		}
		if (_vault.stabilityFeeAPR == 0 || _vault.stabilityFeeAPR == NO_STABILITY_FEE) {
			bAmt = _vault.amountBorrowed;
		}
		else {
			address FCPaddr = IZeroCouponBond(_vault.assetBorrowed).FixCapitalPoolAddress();
			bAmt = stabilityFeeAdjAmountBorrowed(FCPaddr, _vault.amountBorrowed, _vault.timestampOpened, _vault.stabilityFeeAPR);
		}
	}


	/*
		@Description: ensure that a vault will not be sent into the liquidation zone if the cross asset price
			and the borrow and supplied asset rates change a specific amount

		@param Vault memory vault: contains the state of the vault which to check
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
		@param IInfoOracle _info: reference to the IInfoOracle that is connected to this DBSFVaultFactory

		@return bool: true if vault is not sent into liquidation zone from changes,
			false otherwise
		@return SUPPLIED_ASSET_TYPE suppliedType: the type of collateral that the supplied asset is
		@return address baseFCP: the base FCP contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
		@return address baseWrapper: the base wrapper contract corresponding to the ZCB contract
			will be address(0) if the collateral type is not ZCB
	*/
	function vaultWithstandsChange(
		Vault memory vault,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange,
		IInfoOracle _info
	) internal view returns (
		bool withstands,
		SUPPLIED_ASSET_TYPE suppliedType,
		address baseFCP,
		address baseWrapper
	) {

		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_suppliedRateChange >= ABDK_1);
		require(_borrowRateChange <= ABDK_1);

		address _suppliedAddrToPass;
		uint _suppliedAmtToPass;
		uint _borrowAmtToPass;
		{
			address whitelistAddr;
			(whitelistAddr, suppliedType, baseFCP, baseWrapper) = suppliedAssetInfo(vault.assetSupplied, _info);
			(_suppliedAddrToPass, _suppliedAmtToPass, _borrowAmtToPass) = passInfoToVaultManager(vault, whitelistAddr);
		}

		address pass2 = vault.assetBorrowed;
		uint pass5 = _priceMultiplier;
		int128 pass6 = _suppliedRateChange;
		int128 pass7 = _borrowRateChange;
		withstands = vaultHealthContract.vaultWithstandsChange(
			false,
			_suppliedAddrToPass,
			pass2,
			_suppliedAmtToPass,
			_borrowAmtToPass,
			pass5,
			pass6,
			pass7
		);
	}

	/*
		@Description: returns only the bool from the vaultWithstandsChange function
			uses SLOAD to get the IInofOracle contract to pass
	*/
	function simpleVaultWithstandsChange(
		Vault memory vault,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) internal view returns(bool withstands) {
		(withstands, , , ) = vaultWithstandsChange(vault, _priceMultiplier, _suppliedRateChange, _borrowRateChange, IInfoOracle(_infoOracleAddress));
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
		IInfoOracle info = IInfoOracle(_infoOracleAddress);

		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IWrapper baseBorrowed = IFixCapitalPool(FCPborrowed).wrapper();
		uint64 timestampOpened = uint64(baseBorrowed.lastUpdate());
		uint64 wrapperFee = info.StabilityFeeAPR(address(this), address(baseBorrowed));
		Vault memory vault = Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, 0, timestampOpened, wrapperFee);

		{
			(bool withstands, SUPPLIED_ASSET_TYPE suppliedType, address baseFCP, address baseWrapper)
				= vaultWithstandsChange(vault, _priceMultiplier, _suppliedRateChange, _borrowRateChange, info);
			require(withstands);
			require(_amountSupplied <= uint(type(int256).max));
			int intAmtSupplied = int(_amountSupplied);
			if (suppliedType == SUPPLIED_ASSET_TYPE.WASSET) {
				IWrapper(vault.assetSupplied).editSubAccountPosition(msg.sender, address(0), intAmtSupplied, 0);
			}
			else if (suppliedType == SUPPLIED_ASSET_TYPE.ZCB) {
				IWrapper(baseWrapper).editSubAccountPosition(msg.sender, baseFCP, 0, intAmtSupplied);
			}
		}

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		IFixCapitalPool(FCPborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(FCPborrowed, _amountBorrowed);

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
			uint feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(FCPborrowed, vault.amountBorrowed, vault.timestampOpened, vault.stabilityFeeAPR);
			IFixCapitalPool(FCPborrowed).burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			lowerShortInterest(FCPborrowed, vault.amountBorrowed);
			uint sFee = vault.amountSFee;
			sFee += feeAdjBorrowAmt - vault.amountBorrowed;
			if (sFee > 0) {
				claimStabilityFee(vault.assetBorrowed, FCPborrowed, sFee);
			}
		}
		if (vault.amountSupplied > 0) {
			IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);
			(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(vault.assetSupplied, IInfoOracle(_infoOracleAddress));
			require(vault.amountSupplied <= uint(type(int256).max));
			int changeAmt = -int(vault.amountSupplied);
			if (sType == SUPPLIED_ASSET_TYPE.WASSET) {
				IWrapper(vault.assetSupplied).editSubAccountPosition(msg.sender, address(0), changeAmt, 0);
			}
			else if (sType == SUPPLIED_ASSET_TYPE.ZCB) {
				IWrapper(baseWrapper).editSubAccountPosition(msg.sender, baseFCP, 0, changeAmt);
			}
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

		//index 0 in multipliers that must be converted to uint
		require(
			(msg.sender == _owner && _multipliers[0] > 0)
				||
			(
				_assetSupplied == mVault.assetSupplied &&
				_assetBorrowed == mVault.assetBorrowed &&
				_amountSupplied >= mVault.amountSupplied &&
				_amountBorrowed <= mVault.amountBorrowed
			)
		);

		IInfoOracle info = IInfoOracle(_infoOracleAddress);
		Vault memory nextVault = Vault(
			_assetSupplied,
			_assetBorrowed,
			_amountSupplied,
			_amountBorrowed,
			0,
			0,
			NO_STABILITY_FEE
		);
		SUPPLIED_ASSET_TYPE sType;
		address baseFCP;
		address baseWrapper;

		if (_assetBorrowed != mVault.assetBorrowed) {
			//ensure that after operations vault will be in good health
			{
				bool withstands;
				(withstands, sType, baseFCP, baseWrapper) = vaultWithstandsChange(
					nextVault,
					uint(_multipliers[0]),
					_multipliers[1],
					_multipliers[2],
					info
				);
				require(withstands);
			}
			bytes memory copyData = _data;
			address copyReceiverAddr = _receiverAddr;
			adjVaultChangeBorrow(
				mVault,
				sVault,
				nextVault.assetSupplied,
				nextVault.assetBorrowed,
				nextVault.amountSupplied,
				nextVault.amountBorrowed,
				copyData,
				copyReceiverAddr
			);
		}
		else {
			//ensure that after operations vault will be in good health
			//only check health if at any point funds are being removed from the vault
			if (
				_assetSupplied != mVault.assetSupplied ||
				_amountSupplied < mVault.amountSupplied ||
				_amountBorrowed > mVault.amountBorrowed
			) {
				nextVault.timestampOpened = mVault.timestampOpened;
				nextVault.stabilityFeeAPR = mVault.stabilityFeeAPR;
				bool withstands;
				(withstands, sType, baseFCP, baseWrapper) = vaultWithstandsChange(
					nextVault,
					uint(_multipliers[0]),
					_multipliers[1],
					_multipliers[2],
					info
				);
				require(withstands);
			}
			else {
				(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(_assetSupplied, info);
			}
			bytes memory copyData = _data;
			address copyReceiverAddr = _receiverAddr;
			adjVaultSameBorrow(
				mVault,
				sVault,
				nextVault.assetSupplied,
				nextVault.assetBorrowed,
				nextVault.amountSupplied,
				nextVault.amountBorrowed,
				copyData,
				copyReceiverAddr
			);
		}
		require(nextVault.amountSupplied <= uint(type(int256).max));
		int changeAmt = int(nextVault.amountSupplied);
		if (mVault.assetSupplied == nextVault.assetSupplied) {
			require(mVault.amountSupplied <= uint(type(int256).max));
			changeAmt = changeAmt.sub(int(mVault.amountSupplied));
		}
		if (sType == SUPPLIED_ASSET_TYPE.WASSET) {
			IWrapper(nextVault.assetSupplied).editSubAccountPosition(msg.sender, address(0), changeAmt, 0);
		}
		else if (sType == SUPPLIED_ASSET_TYPE.ZCB) {
			IWrapper(baseWrapper).editSubAccountPosition(msg.sender, baseFCP, 0, changeAmt);
		}

		if (mVault.assetSupplied != nextVault.assetSupplied && mVault.assetSupplied != address(0)) {
			(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(mVault.assetSupplied, info);
			require(mVault.amountSupplied <= uint(type(int256).max));
			changeAmt = -int(mVault.amountSupplied);
			if (sType == SUPPLIED_ASSET_TYPE.WASSET) {
				IWrapper(mVault.assetSupplied).editSubAccountPosition(msg.sender, address(0), changeAmt, 0);
			}
			else if (sType == SUPPLIED_ASSET_TYPE.ZCB) {
				IWrapper(baseWrapper).editSubAccountPosition(msg.sender, baseFCP, 0, changeAmt);
			}
		}
	}

	/*
		@Description: performs same task as adjustVault except this function is specific to the case where
			the borrowed asset is not changed

		@param Vault memory mVault: holds the state of the Vault prior to execution
		@param Vault storage sVault: pointer to storage location of the Vault
		@param address _assetSupplied: the new asset(may be the same as previous) that is to be used as
			collateral in the vault
		@param address _assetBorrowed: the new asset(same as previous) that is to be borrowed
			from the vault
		@param uint _amountSupplied: the total amount of collateral that shall be in the vault after execution
		@param uint _amountBorrowed: the total amount of debt of the vault after execution
		@param bytes calldata _data: data to be send to the flashloan receiver if a flashloan is to be done
			if _data.length == 0 there will be no flashloan
		@param  address _receiverAddr: the address of the flashloan receiver contract
	*/
	function adjVaultSameBorrow(
		Vault memory mVault,
		Vault storage sVault,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		bytes memory _data,
		address _receiverAddr
	) internal {

		//------------------distribute funds----------------------
		if (mVault.assetSupplied != _assetSupplied) {
			if (mVault.amountSupplied != 0) {
				bool success = IERC20(mVault.assetSupplied).transfer(_receiverAddr, mVault.amountSupplied);
				require(success);
			}
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

		IFixCapitalPool FCPBorrowed;
		uint change;
		uint adjSFee;
		if (mVault.amountBorrowed < _amountBorrowed) {
			FCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(address(FCPBorrowed), mVault.timestampOpened, mVault.stabilityFeeAPR);
			change = stabilityFeeMultiplier.mul(_amountBorrowed - mVault.amountBorrowed) / (1 ether); //amt to mint
			FCPBorrowed.mintZCBTo(_receiverAddr, change);
			uint adjBorrowed = stabilityFeeMultiplier.mul(_amountBorrowed) / (1 ether);
			raiseShortInterest(address(FCPBorrowed), adjBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = adjBorrowed;
			{
				uint temp = stabilityFeeMultiplier.sub(1 ether).mul(mVault.amountBorrowed) / (1 ether);
				adjSFee = mVault.amountSFee.add(temp);
				sVault.amountSFee = adjSFee;
			}
			sVault.timestampOpened = uint64(FCPBorrowed.lastUpdate());
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			FCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(address(FCPBorrowed), mVault.timestampOpened, mVault.stabilityFeeAPR);
			change = stabilityFeeMultiplier.mul(mVault.amountBorrowed - _amountBorrowed) / (1 ether); //amt to burn
			uint adjBorrowed = stabilityFeeMultiplier.mul(_amountBorrowed) / (1 ether);
			if (adjBorrowed > mVault.amountBorrowed) {
				raiseShortInterest(address(FCPBorrowed), adjBorrowed - mVault.amountBorrowed);
			}
			else {
				lowerShortInterest(address(FCPBorrowed), mVault.amountBorrowed - adjBorrowed);
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
			sVault.timestampOpened = uint64(FCPBorrowed.lastUpdate());
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			address assetSupplied = mVault.assetSupplied;
			address assetBorrowed = mVault.assetBorrowed;
			uint amountSupplied = mVault.amountSupplied;
			int changeBorrowed = change == 0 ? 0 : (mVault.amountBorrowed < _amountBorrowed ? int(change) : -int(change));
			IDBSFVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				assetSupplied,
				assetBorrowed,
				amountSupplied,
				changeBorrowed,
				_data
			);
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

		if (mVault.amountBorrowed > _amountBorrowed) {
			//lowerShortInterest(address(FCPBorrowed), mVault.amountBorrowed - _amountBorrowed);
			FCPBorrowed.burnZCBFrom(msg.sender,  change);
			claimStabilityFee(mVault.assetBorrowed, address(FCPBorrowed), adjSFee < change ? adjSFee : change);
		}
	}

	/*
		@Description: performs same task as adjustVault except this function is specific to the case where
			the borrowed asset is changed

		@param Vault memory mVault: holds the state of the Vault prior to execution
		@param Vault storage sVault: pointer to storage location of the Vault
		@param address _assetSupplied: the new asset(may be the same as previous) that is to be used as
			collateral in the vault
		@param address _assetBorrowed: the new asset(NOT the same as previous) that is to be borrowed
			from the vault
		@param uint _amountSupplied: the total amount of collateral that shall be in the vault after execution
		@param uint _amountBorrowed: the total amount of debt of the vault after execution
		@param bytes calldata _data: data to be send to the flashloan receiver if a flashloan is to be done
			if _data.length == 0 there will be no flashloan
		@param  address _receiverAddr: the address of the flashloan receiver contract
	*/
	function adjVaultChangeBorrow(
		Vault memory mVault,
		Vault storage sVault,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		bytes memory _data,
		address _receiverAddr
	) internal {

		//------------------distribute funds----------------------
		if (mVault.assetSupplied != _assetSupplied) {
			if (mVault.amountSupplied != 0) {
				bool success = IERC20(mVault.assetSupplied).transfer(_receiverAddr, mVault.amountSupplied);
				require(success);
			}
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

		IFixCapitalPool oldFCPBorrowed;
		//nominal value debt at close / nominal value debt now
		if (_assetBorrowed != address(0)) {
			IFixCapitalPool newFCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			raiseShortInterest(address(newFCPBorrowed), _amountBorrowed);
			newFCPBorrowed.mintZCBTo(_receiverAddr, _amountBorrowed);
			address wrapperAddr = IZeroCouponBond(_assetBorrowed).WrapperAddress();
			sVault.stabilityFeeAPR = IInfoOracle(_infoOracleAddress).StabilityFeeAPR(address(this), wrapperAddr);
			sVault.timestampOpened = uint64(IWrapper(wrapperAddr).lastUpdate());
		}
		else {
			require(_amountBorrowed == 0);
		}
		if (mVault.amountBorrowed > 0) {
			oldFCPBorrowed = IFixCapitalPool(IZeroCouponBond(mVault.assetBorrowed).FixCapitalPoolAddress());
			lowerShortInterest(address(oldFCPBorrowed), mVault.amountBorrowed);
		}
		sVault.assetBorrowed = _assetBorrowed;
		sVault.amountBorrowed = _amountBorrowed;
		if (mVault.amountSFee > 0) {
			sVault.amountSFee = 0;
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			IDBSFVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				mVault.assetSupplied,
				mVault.assetBorrowed,
				mVault.amountSupplied,
				-int(mVault.amountBorrowed),
				_data
			);
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

		if (mVault.amountBorrowed > 0) {
			uint feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(address(oldFCPBorrowed), mVault.amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			oldFCPBorrowed.burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			claimStabilityFee(mVault.assetBorrowed, address(oldFCPBorrowed), mVault.amountSFee + feeAdjBorrowAmt - mVault.amountBorrowed);
		}
	}

}