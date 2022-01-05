// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IYTVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./NSFVaultFactoryDelegateParent.sol";

contract NSFVaultFactoryDelegate3 is NSFVaultFactoryDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;

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
		require(_yieldSupplied >= MIN_YIELD_SUPPLIED && _yieldSupplied <= uint(type(int256).max));
		validateYTvaultMultipliers(_priceMultiplier, _suppliedRateChange, _borrowRateChange, _bondSupplied > 0);
		address baseWrapperSupplied = _fixCapitalPoolToWrapper[_FCPsupplied];
		require(baseWrapperSupplied != address(0));
		uint _unitYieldSupplied = getUnitValueYield(_FCPsupplied, _yieldSupplied);

		require(vaultHealthContract.YTvaultWithstandsChange(
			false,
			_FCPsupplied,
			_FCPborrowed,
			_unitYieldSupplied,
			_bondSupplied,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		IFixCapitalPool(_FCPborrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(_FCPborrowed, _amountBorrowed);

		editSubAccountYTVault(false, msg.sender, _FCPsupplied, baseWrapperSupplied, int(_yieldSupplied), _bondSupplied);

		_YTvaults[msg.sender].push(YTVault(_FCPsupplied, _FCPborrowed, _yieldSupplied, _bondSupplied, _amountBorrowed));

	}

	/*
		@Description: fully repay a YT vault and withdraw all collateral

		@param uint _index: the YT vault to close is at YTvaults[msg.sender][_index]
		@param address _to: the address to which to send all collateral after closing the vault
	*/
	function closeYTVault(uint _index, address _to) external noReentry {
		uint len = _YTvaults[msg.sender].length;
		require(_index < len);
		YTVault memory vault = _YTvaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0) {
			IFixCapitalPool(vault.FCPborrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(vault.FCPborrowed, vault.amountBorrowed);
		}
		if (vault.yieldSupplied > 0 || vault.bondSupplied != 0) {
			require(vault.yieldSupplied <= uint(type(int256).max));
			//we already know the vault would pass the check so no need to check
			IFixCapitalPool(vault.FCPsupplied).transferPosition(_to, vault.yieldSupplied, vault.bondSupplied);
			address baseWrapperSupplied = address(IFixCapitalPool(vault.FCPsupplied).wrapper());
			editSubAccountYTVault(false, msg.sender, vault.FCPsupplied, baseWrapperSupplied, -int(vault.yieldSupplied), vault.bondSupplied.neg());
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
	) external noReentry {
		require(_index < _YTvaults[_owner].length);

		YTVault memory mVault = _YTvaults[_owner][_index];
		YTVault storage sVault = _YTvaults[_owner][_index];

		//ensure that after operations vault will be in good health
		//only check health if at any point funds are being removed from the vault
		if (
			_FCPborrowed != mVault.FCPborrowed ||
			_FCPsupplied != mVault.FCPsupplied ||
			_yieldSupplied < mVault.yieldSupplied ||
			_amountBorrowed > mVault.amountBorrowed ||
			(_yieldSupplied == mVault.yieldSupplied && _bondSupplied < mVault.bondSupplied)
		) {
			//index 0 in multipliers that must be converted to uint
			require(_multipliers[0] > 0);
			require(msg.sender == _owner);
			require(vaultHealthContract.YTvaultWithstandsChange(
				false,
				_FCPsupplied,
				_FCPborrowed,
				_yieldSupplied,
				_bondSupplied,
				_amountBorrowed,
				uint(_multipliers[0]),
				_multipliers[1],
				_multipliers[2]
			));
		}

		//------------------distribute funds----------------------
		int changeYTsupplied;
		int changeZCBsupplied;
		if (mVault.FCPsupplied != _FCPsupplied) {
			if (mVault.FCPsupplied != address(0)) {
				IFixCapitalPool(mVault.FCPsupplied).transferPosition(_receiverAddr, mVault.yieldSupplied, mVault.bondSupplied);
			}
			sVault.FCPsupplied = _FCPsupplied;
			sVault.yieldSupplied = _yieldSupplied;
			sVault.bondSupplied = _bondSupplied;
		}
		else if (mVault.yieldSupplied != _yieldSupplied || mVault.bondSupplied != _bondSupplied) {
			uint conversionRate = IFixCapitalPool(_FCPsupplied).currentConversionRate();
			require(_bondSupplied >= 0 || _yieldSupplied.mul(conversionRate) / (1 ether) >= uint(-_bondSupplied));
			//write change in YT & ZCB into yield supplied & bond supplied respectively on mVault to save stack space
			changeYTsupplied = _yieldSupplied.toInt().sub(mVault.yieldSupplied.toInt());
			changeZCBsupplied = _bondSupplied.sub(mVault.bondSupplied).add(changeYTsupplied.mul(conversionRate.toInt()) / (1 ether));
			if (changeYTsupplied < 0) {
				IFixCapitalPool(_FCPsupplied).transferYT(address(this), msg.sender, changeYTsupplied.neg().toUint());
				changeZCBsupplied++; //offset rounding error when updating bond balance amounts
			}
			if (changeZCBsupplied < 0) {
				IFixCapitalPool(_FCPsupplied).transferZCB(address(this), msg.sender, changeZCBsupplied.neg().toUint());
			}
			if (mVault.yieldSupplied != _yieldSupplied) {
				sVault.yieldSupplied = _yieldSupplied;
			}
			if (mVault.bondSupplied != _bondSupplied) {
				sVault.bondSupplied = _bondSupplied;
			}
		}

		if (mVault.FCPborrowed != _FCPborrowed) {
			if (_FCPborrowed != address(0)) {
				raiseShortInterest(_FCPborrowed, _amountBorrowed);
			}
			if (mVault.FCPborrowed != address(0)) {
				lowerShortInterest(mVault.FCPborrowed, mVault.amountBorrowed);
			}
			IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, _amountBorrowed);
			sVault.FCPborrowed = _FCPborrowed;
			sVault.amountBorrowed = _amountBorrowed;
		}
		else if (mVault.amountBorrowed < _amountBorrowed) {
			IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, _amountBorrowed - mVault.amountBorrowed);
			raiseShortInterest(_FCPborrowed, _amountBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = _amountBorrowed;
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			sVault.amountBorrowed = _amountBorrowed;
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			bytes memory data = _data; //prevent stack too deep
			address mVaultFCPsupplied = mVault.FCPsupplied;
			address mVaultFCPborrowed = mVault.FCPborrowed;
			uint mVaultYieldSupplied = mVault.yieldSupplied;
			int mVaultBondSupplied = mVault.bondSupplied;
			uint mVaultAmountBorrowed = mVault.amountBorrowed;
			IYTVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				mVaultFCPsupplied,
				mVaultFCPborrowed,
				mVaultYieldSupplied,
				mVaultBondSupplied,
				mVaultAmountBorrowed,
				data
			);

			//prevent memory tempering attack
			mVault.FCPsupplied = mVaultFCPsupplied;
			mVault.FCPborrowed = mVaultFCPborrowed;
			mVault.yieldSupplied = mVaultYieldSupplied;
			mVault.bondSupplied = mVaultBondSupplied;
			mVault.amountBorrowed = mVaultAmountBorrowed;
		}

		//-----------------------------get funds-------------------------
		if (mVault.FCPsupplied != _FCPsupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		}
		else {
			if (changeYTsupplied > 0) {
				IFixCapitalPool(_FCPsupplied).transferYT(msg.sender, address(this), uint(changeYTsupplied));
			}
			if (changeZCBsupplied > 0) {
				IFixCapitalPool(_FCPsupplied).transferZCB(msg.sender, address(this), uint(changeZCBsupplied));
			}
		}

		if (mVault.FCPborrowed != _FCPborrowed) {
			if (mVault.amountBorrowed > 0) {
				IFixCapitalPool(mVault.FCPborrowed).burnZCBFrom(msg.sender, mVault.amountBorrowed);
			}
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			lowerShortInterest(_FCPborrowed, mVault.amountBorrowed.sub(_amountBorrowed));
			IFixCapitalPool(_FCPborrowed).burnZCBFrom(msg.sender,  mVault.amountBorrowed.sub(_amountBorrowed));
		}

		require(_yieldSupplied <= uint(type(int256).max));
		address copyVaultOwner = _owner; //prevent stack too deep
		address copyFCPsupplied = _FCPsupplied; //prevent stack too deep
		if (mVault.FCPsupplied == _FCPsupplied || mVault.FCPsupplied == address(0)) {
			int yieldChange = int(_yieldSupplied).sub(mVault.yieldSupplied.toInt());
			int bondChange = _bondSupplied.sub(mVault.bondSupplied);
			address baseWrapperSupplied = address(IFixCapitalPool(copyFCPsupplied).wrapper());
			editSubAccountYTVault(false, copyVaultOwner, copyFCPsupplied, baseWrapperSupplied, yieldChange, bondChange);
		}
		else {
			int yieldChange = int(_yieldSupplied);
			int bondChange = _bondSupplied;
			address baseWrapperSupplied = _fixCapitalPoolToWrapper[copyFCPsupplied];
			editSubAccountYTVault(false, copyVaultOwner, copyFCPsupplied, baseWrapperSupplied, yieldChange, bondChange);
			if (mVault.FCPsupplied != address(0)) {
				yieldChange = mVault.yieldSupplied.toInt().neg();
				bondChange = mVault.bondSupplied.neg();
				baseWrapperSupplied = address(IFixCapitalPool(mVault.FCPsupplied).wrapper());
				editSubAccountYTVault(false, copyVaultOwner, mVault.FCPsupplied, baseWrapperSupplied, yieldChange, bondChange);
			}
		}
	}
}
