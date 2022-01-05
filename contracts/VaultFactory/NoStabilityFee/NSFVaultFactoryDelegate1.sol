// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/SafeERC20.sol";
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

		require(_assetSupplied != _assetBorrowed && _amountSupplied <= uint(type(int256).max));
		/*
			if asset supplied is a wrapper asset, _wrapperToUnderlyingAsset[_assetSupplied] will be the address of the underlying
			otherwise if the supplied asset is a ZCB or standard ERC20 _wrapperToUnderlyingAsset[_assetSupplied] will be address(1)
			_wrapperToUnderlyingAsset[_assetSupplied] will only be address(0) if the supplied asset is invalid collateral
		*/
		require(_wrapperToUnderlyingAsset[_assetSupplied] != address(0));

		IERC20(_assetSupplied).safeTransferFrom(msg.sender, address(this), _amountSupplied);
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
	function closeVault(uint _index, address _to) external noReentry {
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
			IERC20(vault.assetSupplied).safeTransfer(_to, vault.amountSupplied);
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
	) external noReentry {
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
				IERC20(mVault.assetSupplied).safeTransfer(_receiverAddr, mVault.amountSupplied);
			}
			sVault.assetSupplied =  newVault.assetSupplied;
			sVault.amountSupplied = newVault.amountSupplied;
		}
		else if (mVault.amountSupplied > newVault.amountSupplied) {
			IERC20(newVault.assetSupplied).safeTransfer(_receiverAddr, mVault.amountSupplied - newVault.amountSupplied);
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

			address copyReceiverAddr = _receiverAddr; //prevent stack too deep

			address mVaultAssetSupplied = mVault.assetSupplied;
			address mVaultAssetBorrowed = mVault.assetBorrowed;

			bytes memory copyData = _data; //prevent stack too deep

			uint mVaultAmountSupplied = mVault.amountSupplied;
			uint mVaultAmountBorrowed = mVault.amountBorrowed;

			Vault memory copyMVault = mVault;
			Vault memory copyNewVault = newVault;
			address newVaultAssetSupplied = copyNewVault.assetSupplied;
			address newVaultAssetBorrowed = copyNewVault.assetBorrowed;
			uint newVaultAmountSupplied = copyNewVault.amountSupplied;
			uint newVaultAmountBorrowed = copyNewVault.amountBorrowed;

			IVaultManagerFlashReceiver(copyReceiverAddr).onFlashLoan(
				msg.sender,
				mVaultAssetSupplied,
				mVaultAssetBorrowed,
				mVaultAmountSupplied,
				mVaultAmountBorrowed,
				copyData
			);

			//prevent memory tampering attack
			copyNewVault.assetSupplied = newVaultAssetSupplied;
			copyNewVault.assetBorrowed = newVaultAssetBorrowed;
			copyNewVault.amountSupplied = newVaultAmountSupplied;
			copyNewVault.amountBorrowed = newVaultAmountBorrowed;
			copyMVault.assetSupplied = mVaultAssetSupplied;
			copyMVault.assetBorrowed = mVaultAssetBorrowed;
			copyMVault.amountSupplied = mVaultAmountSupplied;
			copyMVault.amountBorrowed = mVaultAmountBorrowed;
		}

		//-----------------------------get funds-------------------------
		if (mVault.assetSupplied != newVault.assetSupplied) {
			IERC20(newVault.assetSupplied).safeTransferFrom(msg.sender, address(this), newVault.amountSupplied);
			int changeAmt = newVault.amountSupplied.toInt();
			editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCPsupplied, baseWrapperSupplied, changeAmt);
			if (mVault.assetSupplied != address(0)) {
				changeAmt = mVault.amountSupplied.toInt().neg();
				(, sType, baseFCPsupplied, baseWrapperSupplied) = suppliedAssetInfo(mVault.assetSupplied);
				editSubAccountStandardVault(false, copyVaultOwner, sType, baseFCPsupplied, baseWrapperSupplied, changeAmt);
			}
		}
		else {
			if (mVault.amountSupplied < newVault.amountSupplied) {
				IERC20(newVault.assetSupplied).safeTransferFrom(msg.sender, address(this), newVault.amountSupplied - mVault.amountSupplied);
			}
			int changeAmt = newVault.amountSupplied.toInt().sub(mVault.amountSupplied.toInt());
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

}