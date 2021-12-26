// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/BigMath.sol";
import "../../libraries/SafeERC20.sol";
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
	using SafeERC20 for IERC20;


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
		uint64 timestampOpened = uint64(block.timestamp);
		uint64 wrapperFee = info.StabilityFeeAPR(address(this), address(baseBorrowed));
		Vault memory vault = Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, 0, timestampOpened, wrapperFee);

		{
			address copyAssetSupplied = _assetSupplied; //prevent stack too deep
			IERC20(copyAssetSupplied).safeTransferFrom(msg.sender, address(this), _amountSupplied);
		}
		IFixCapitalPool(FCPborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(FCPborrowed, _amountBorrowed);

		SUPPLIED_ASSET_TYPE sType;
		address baseFCP;
		address baseWrapper;
		{
			//scope structure is such that withstands goes out of scope after we require(withstands), prevents stack too deep
			bool withstands;
			(withstands, sType, baseFCP, baseWrapper)
				= vaultWithstandsChange(vault, _priceMultiplier, _suppliedRateChange, _borrowRateChange, info);
			require(withstands);
		}
		int changeAmt = _amountSupplied.toInt();
		editSubAccountStandardVault(false, msg.sender, sType, baseFCP, baseWrapper, changeAmt);

		_vaults[msg.sender].push(vault);
	}

	/*
		@Description: fully repay a vault and withdraw all collateral

		@param uint _index: the vault to close is at vaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeVault(uint _index, address _to) external noReentry {
		uint len = _vaults[msg.sender].length;
		require(len > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0) {
			address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
			uint feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(vault.amountBorrowed, vault.timestampOpened, vault.stabilityFeeAPR);
			IFixCapitalPool(FCPborrowed).burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			lowerShortInterest(FCPborrowed, vault.amountBorrowed);
			uint sFee = vault.amountSFee;
			sFee += feeAdjBorrowAmt - vault.amountBorrowed;
			if (sFee > 0) {
				claimStabilityFee(vault.assetBorrowed, FCPborrowed, sFee);
			}
		}
		if (vault.amountSupplied > 0) {
			IERC20(vault.assetSupplied).safeTransfer(_to, vault.amountSupplied);
			(, SUPPLIED_ASSET_TYPE sType, address baseFCP, address baseWrapper) = suppliedAssetInfo(vault.assetSupplied, IInfoOracle(_infoOracleAddress));
			require(vault.amountSupplied <= uint(type(int256).max));
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
	) external noReentry {
		require(_index < _vaults[_owner].length);

		Vault memory mVault = _vaults[_owner][_index];
		address copyVaultOwner = _owner;
		uint copyIndex = _index;

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
		Vault memory nextVault = _assetBorrowed == mVault.assetBorrowed ?
			Vault(
				_assetSupplied,
				_assetBorrowed,
				_amountSupplied,
				_amountBorrowed,
				0, //nextVault.amountSFee is not ever used, keep 0
				mVault.timestampOpened,
				mVault.stabilityFeeAPR
			)
			 :
			Vault(
				_assetSupplied,
				_assetBorrowed,
				_amountSupplied,
				_amountBorrowed,
				0, //nextVault.amountSFee is not ever used, keep 0
				0, //with no stability fee newVault.timestampOpened is irrelevant
				NO_STABILITY_FEE //new borrow asset has been put in place, no stability has been accumulated yet
			);
		SUPPLIED_ASSET_TYPE sType;
		address baseFCP;
		address baseWrapper;

		if (_assetBorrowed != mVault.assetBorrowed) {
			//ensure that after operations vault will be in good health
			{
				bool withstands;
				uint m0 = uint(_multipliers[0]); // prevent stack too deep
				int128 m1 = _multipliers[1]; // prevent stack too deep
				int128 m2 = _multipliers[2]; // prevent stack too deep
				(withstands, sType, baseFCP, baseWrapper) = vaultWithstandsChange(nextVault, m0, m1, m2, info);
				require(withstands);
			}
			bytes memory copyData = _data;
			address copyReceiverAddr = _receiverAddr;
			adjVaultChangeBorrow(
				mVault,
				_vaults[copyVaultOwner][copyIndex],
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
				nextVault.assetSupplied != mVault.assetSupplied ||
				nextVault.amountSupplied < mVault.amountSupplied ||
				nextVault.amountBorrowed > mVault.amountBorrowed
			) {
				nextVault.timestampOpened = mVault.timestampOpened;
				nextVault.stabilityFeeAPR = mVault.stabilityFeeAPR;
				bool withstands;
				uint m0 = uint(_multipliers[0]); // prevent stack too deep
				int128 m1 = _multipliers[1]; // prevent stack too deep
				int128 m2 = _multipliers[2]; // prevent stack too deep
				(withstands, sType, baseFCP, baseWrapper) = vaultWithstandsChange(nextVault, m0, m1, m2, info);
				require(withstands);
			}
			else {
				(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(nextVault.assetSupplied, info);
			}
			bytes memory copyData = _data;
			address copyReceiverAddr = _receiverAddr;
			adjVaultSameBorrow(
				mVault,
				_vaults[copyVaultOwner][copyIndex],
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
		editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCP, baseWrapper, changeAmt);

		if (mVault.assetSupplied != nextVault.assetSupplied && mVault.assetSupplied != address(0)) {
			(, sType, baseFCP, baseWrapper) = suppliedAssetInfo(mVault.assetSupplied, info);
			require(mVault.amountSupplied <= uint(type(int256).max));
			changeAmt = -int(mVault.amountSupplied);
			editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCP, baseWrapper, changeAmt);
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
				IERC20(mVault.assetSupplied).safeTransfer(_receiverAddr, mVault.amountSupplied);
			}
			sVault.assetSupplied = _assetSupplied;
			sVault.amountSupplied = _amountSupplied;
		}
		else if (mVault.amountSupplied > _amountSupplied) {
			IERC20(_assetSupplied).safeTransfer(_receiverAddr, mVault.amountSupplied - _amountSupplied);
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
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(mVault.timestampOpened, mVault.stabilityFeeAPR);
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
			sVault.timestampOpened = uint64(block.timestamp);
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			FCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(mVault.timestampOpened, mVault.stabilityFeeAPR);
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
			sVault.timestampOpened = uint64(block.timestamp);
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
			IERC20(_assetSupplied).safeTransferFrom(msg.sender, address(this), _amountSupplied);
		}
		else if (mVault.amountSupplied < _amountSupplied) {
			IERC20(_assetSupplied).safeTransferFrom(msg.sender, address(this), _amountSupplied - mVault.amountSupplied);
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
				IERC20(mVault.assetSupplied).safeTransfer(_receiverAddr, mVault.amountSupplied);
			}
			sVault.assetSupplied = _assetSupplied;
			sVault.amountSupplied = _amountSupplied;
		}
		else if (mVault.amountSupplied > _amountSupplied) {
			IERC20(_assetSupplied).safeTransfer(_receiverAddr, mVault.amountSupplied - _amountSupplied);
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
			sVault.timestampOpened = uint64(block.timestamp);
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
			IERC20(_assetSupplied).safeTransferFrom(msg.sender, address(this), _amountSupplied);
		}
		else if (mVault.amountSupplied < _amountSupplied) {
			IERC20(_assetSupplied).safeTransferFrom(msg.sender, address(this), _amountSupplied - mVault.amountSupplied);
		}

		if (mVault.amountBorrowed > 0) {
			uint feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(mVault.amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			oldFCPBorrowed.burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			claimStabilityFee(mVault.assetBorrowed, address(oldFCPBorrowed), mVault.amountSFee + feeAdjBorrowAmt - mVault.amountBorrowed);
		}
	}

}