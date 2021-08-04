// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../libraries/BigMath.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/IDBSFYTVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./DBSFVaultFactoryDelegateParent.sol";

/*
	This contract is specifically for handling YTVault functionality
*/
contract DBSFVaultFactoryDelegate3 is DBSFVaultFactoryDelegateParent {
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
		address baseWrapperSupplied = IInfoOracle(_infoOracleAddress).FCPtoWrapper(address(this), _FCPsupplied);
		uint _unitYieldSupplied = wrappedToUnitAmount(baseWrapperSupplied, _yieldSupplied);

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

		editSubAccountYTVault(false, msg.sender, _FCPsupplied, baseWrapperSupplied, int(_yieldSupplied), _bondSupplied);

		IWrapper baseBorrowed = IFixCapitalPool(_FCPborrowed).wrapper();
		uint64 timestampOpened = uint64(block.timestamp);
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
			uint feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(vault.amountBorrowed, vault.timestampOpened, vault.stabilityFeeAPR);
			IFixCapitalPool(vault.FCPborrowed).burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			lowerShortInterest(vault.FCPborrowed, vault.amountBorrowed);
			uint sFee = vault.amountSFee;
			sFee += feeAdjBorrowAmt - vault.amountBorrowed;
			if (sFee > 0) {
				claimStabilityFee(IFixCapitalPool(vault.FCPborrowed).zeroCouponBondAddress(), vault.FCPborrowed, sFee);
			}
		}
		if (vault.yieldSupplied > 0 || vault.bondSupplied != 0) {
			require(vault.yieldSupplied <= uint(type(int256).max));
			//we already know the vault would pass the check so no need to check
			IFixCapitalPool(vault.FCPsupplied).transferPosition(_to, vault.yieldSupplied, vault.bondSupplied);
			address baseWrapperSupplied = address(IFixCapitalPool(vault.FCPsupplied).wrapper());
			editSubAccountYTVault(false, msg.sender, vault.FCPsupplied, baseWrapperSupplied, -int(vault.yieldSupplied), vault.bondSupplied.mul(-1));
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
			vaultHealthContract.YTvaultWithstandsChange
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

		require(_yieldSupplied <= uint(type(int256).max));
		require(mVault.yieldSupplied <= uint(type(int256).max));
		address copyVaultOwner = _owner; //prevent stack too deep
		address copyFCPsupplied = _FCPsupplied; //prevent stack too deep
		if (mVault.FCPsupplied == _FCPsupplied || mVault.FCPsupplied == address(0)) {
			int yieldChange = int(_yieldSupplied).sub(int(mVault.yieldSupplied));
			int bondChange = _bondSupplied.sub(mVault.bondSupplied);
			address baseWrapperSupplied = address(IFixCapitalPool(copyFCPsupplied).wrapper());
			editSubAccountYTVault(false, copyVaultOwner, copyFCPsupplied, baseWrapperSupplied, yieldChange, bondChange);
		}
		else {
			int yieldChange = int(_yieldSupplied);
			int bondChange = _bondSupplied;
			address baseWrapperSupplied = IInfoOracle(_infoOracleAddress).FCPtoWrapper(address(this), copyFCPsupplied);
			editSubAccountYTVault(false, copyVaultOwner, copyFCPsupplied, baseWrapperSupplied, yieldChange, bondChange);
			yieldChange = -int(mVault.yieldSupplied);
			bondChange = mVault.bondSupplied.mul(-1);
			baseWrapperSupplied = address(IFixCapitalPool(mVault.FCPsupplied).wrapper());
			editSubAccountYTVault(false, copyVaultOwner, mVault.FCPsupplied, baseWrapperSupplied, yieldChange, bondChange);
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
		int[2] memory changes;
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
			changes[0] = int(_yieldSupplied).sub(int(mVault.yieldSupplied));
			changes[1] = _bondSupplied.sub(mVault.bondSupplied).add(changes[0].mul(int(conversionRate)) / (1 ether));
			if (changes[0] < 0) {
				IFixCapitalPool(_FCPsupplied).transferYT(address(this), msg.sender, uint(-changes[0]));
				changes[1]++; //offset rounding error when updating bond balance amounts
			}
			if (changes[1] < 0) {
				IFixCapitalPool(_FCPsupplied).transferZCB(address(this), msg.sender, uint(-changes[1]));
			}
			if (mVault.yieldSupplied != _yieldSupplied) {
				sVault.yieldSupplied = _yieldSupplied;
			}
			if (mVault.bondSupplied != _bondSupplied) {
				sVault.bondSupplied = _bondSupplied;
			}
		}
		uint change;
		uint adjSFee;
		if (mVault.amountBorrowed < _amountBorrowed) {
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(mVault.timestampOpened, mVault.stabilityFeeAPR);
			change = stabilityFeeMultiplier.mul(_amountBorrowed - mVault.amountBorrowed) / (1 ether);
			IFixCapitalPool(_FCPborrowed).mintZCBTo(_receiverAddr, change);
			uint adjBorrowed = stabilityFeeMultiplier.mul(_amountBorrowed) / (1 ether);
			raiseShortInterest(_FCPborrowed, adjBorrowed - mVault.amountBorrowed);
			sVault.amountBorrowed = adjBorrowed;
			{
				uint temp = mVault.amountBorrowed; // prevent stack too deep
				temp = stabilityFeeMultiplier.sub(1 ether).mul(temp) / (1 ether);
				adjSFee = mVault.amountSFee; //prevent stack too deep
				adjSFee = adjSFee.add(temp);
				sVault.amountSFee = adjSFee;
			}
			sVault.timestampOpened = uint64(block.timestamp);
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(mVault.timestampOpened, mVault.stabilityFeeAPR);
			change = stabilityFeeMultiplier.mul(mVault.amountBorrowed - _amountBorrowed) / (1 ether); //amt to burn
			uint adjBorrowed = stabilityFeeMultiplier.mul(_amountBorrowed) / (1 ether);
			if (adjBorrowed > mVault.amountBorrowed) {
				raiseShortInterest(_FCPborrowed, adjBorrowed - mVault.amountBorrowed);
			}
			else {
				uint mVaultAmtBorrowed = mVault.amountBorrowed;
				lowerShortInterest(_FCPborrowed, mVaultAmtBorrowed - adjBorrowed);
			}
			sVault.amountBorrowed = adjBorrowed;
			{
				uint temp = mVault.amountBorrowed; // prevent stack too deep
				temp = stabilityFeeMultiplier.sub(1 ether).mul(temp) / (1 ether);
				adjSFee = mVault.amountSFee; // prevent stack too deep
				adjSFee = adjSFee.add(temp);
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
			address FCPsupplied = mVault.FCPsupplied;
			address FCPborrowed = mVault.FCPborrowed;
			bytes32[3] memory toPass;
			toPass[0] = bytes32(mVault.yieldSupplied);
			toPass[1] = bytes32(mVault.bondSupplied);
			toPass[2] = bytes32(mVault.amountBorrowed);
			if (change == 0) {
				toPass[2] = bytes32(0);
			}
			else if (uint(toPass[2]) > _amountBorrowed) {
				toPass[2] = bytes32(int(change));
			}
			else {
				toPass[2] = bytes32(-int(change));
			}
			bytes memory data = _data;
			IDBSFYTVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				FCPsupplied,
				FCPborrowed,
				uint(toPass[0]),
				int(toPass[1]),
				int(toPass[2]),
				data
			);
		}

		//-----------------------------get funds-------------------------
		if (mVault.FCPsupplied != _FCPsupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		}
		else {
			if (changes[0] > 0) {
				IFixCapitalPool(_FCPsupplied).transferYT(msg.sender, address(this), uint(changes[0]));
			}
			if (changes[1] > 0) {
				IFixCapitalPool(_FCPsupplied).transferZCB(msg.sender, address(this), uint(changes[1]));
			}
		}
		if (mVault.amountBorrowed > _amountBorrowed) {
			IFixCapitalPool(_FCPborrowed).burnZCBFrom(msg.sender,  change);
			claimStabilityFee(IFixCapitalPool(mVault.FCPborrowed).zeroCouponBondAddress(), _FCPborrowed, adjSFee < change ? adjSFee : change);
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
		int[2] memory changes;
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
			changes[0] = int(_yieldSupplied).sub(int(mVault.yieldSupplied));
			changes[1] = _bondSupplied.sub(mVault.bondSupplied).add(changes[0].mul(int(conversionRate)) / (1 ether));
			if (changes[0] < 0) {
				IFixCapitalPool(_FCPsupplied).transferYT(address(this), msg.sender, uint(-changes[0]));
				changes[1]++; //offset rounding error when updating bond balance amounts
			}
			if (changes[1] < 0) {
				IFixCapitalPool(_FCPsupplied).transferZCB(address(this), msg.sender, uint(-changes[1]));
			}
			if (mVault.yieldSupplied != _yieldSupplied) {
				sVault.yieldSupplied = _yieldSupplied;
			}
			if (mVault.bondSupplied != _bondSupplied) {
				sVault.bondSupplied = _bondSupplied;
			}
		}

		if (_FCPborrowed != address(0)) {
			raiseShortInterest(_FCPborrowed, _amountBorrowed);
			IWrapper wrapper = IFixCapitalPool(_FCPborrowed).wrapper();
			sVault.timestampOpened = uint64(block.timestamp);
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
			address FCPsupplied = mVault.FCPsupplied;
			address FCPborrowed = mVault.FCPborrowed;
			uint yieldSupplied = mVault.yieldSupplied;
			int bondSupplied = mVault.bondSupplied;
			int changeBorrowed = -int(mVault.amountBorrowed);
			IDBSFYTVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				FCPsupplied,
				FCPborrowed,
				yieldSupplied,
				bondSupplied,
				changeBorrowed,
				_data
			);
		}

		//-----------------------------get funds-------------------------
		if (mVault.FCPsupplied != _FCPsupplied) {
			IFixCapitalPool(_FCPsupplied).transferPositionFrom(msg.sender, address(this), _yieldSupplied, _bondSupplied);
		}
		else {
			if (changes[0] > 0) {
				IFixCapitalPool(_FCPsupplied).transferYT(msg.sender, address(this), uint(changes[0]));
			}
			if (changes[1] > 0) {
				IFixCapitalPool(_FCPsupplied).transferZCB(msg.sender, address(this), uint(changes[1]));
			}
		}

		if (mVault.amountBorrowed > 0) {
			uint toBurn = stabilityFeeAdjAmountBorrowed(mVault.amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			IFixCapitalPool(mVault.FCPborrowed).burnZCBFrom(msg.sender, toBurn);
			claimStabilityFee(IFixCapitalPool(mVault.FCPborrowed).zeroCouponBondAddress(), mVault.FCPborrowed, toBurn - mVault.amountBorrowed);
		}
	}
}