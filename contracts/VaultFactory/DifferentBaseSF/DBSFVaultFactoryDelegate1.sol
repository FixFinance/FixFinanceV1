// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../../libraries/SafeMath.sol";
import "../../libraries/SignedSafeMath.sol";
import "../../libraries/BigMath.sol";
import "../../interfaces/IVaultManagerFlashReceiver.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../interfaces/IVaultHealth.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/Ownable.sol";
import "./DBSFVaultFactoryData.sol";

contract DBSFVaultFactoryDelegate1 is DBSFVaultFactoryData {
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
		@Description: when a bidder is outbid return their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the FCP corresponding to the ZCB that the bidder
			posted with their bid in
		@param uint _amount: the amount of _asset that was posted by the bidder
	*/
	function refundBid(address _bidder, address _FCPaddr, uint _amount) internal {
		IFixCapitalPool(_FCPaddr).mintZCBTo(_bidder, _amount);
	}

	/*
		@Description: when a bidder makes a bid collect collateral for their bid

		@param address _bidder: the address of the bidder
		@param address _asset: the address of the FCP corresponding to the ZCB that the bidder
			posted with their bid in
		@param uint _amount: the amount of _asset that the bidder is required to post
	*/
	function collectBid(address _bidder, address _FCPaddr, uint _amount) internal {
		IFixCapitalPool(_FCPaddr).burnZCBFrom(_bidder, _amount);
	}

	/*
		@Description: find the multiplier which is multiplied with amount borrowed (when vault was opened)
			to find the current liability

		@param address _FCPborrrowed: the address of the FCP contract associated with the debt asset of the Vault
		@param uint64 _timestampOpened: the time at which the vault was opened
		@param uint64 _stabiliityFeeAPR: the annual rate which must be paid for stability fees

		@return uint: the stability rate debt multiplier
			inflated by (1 ether)
	*/
	function getStabilityFeeMultiplier(address _FCPborrrowed, uint64 _timestampOpened, uint64 _stabilityFeeAPR) internal view returns(uint) {
		uint lastUpdate = IFixCapitalPool(_FCPborrrowed).lastUpdate();
		int128 yearsOpen = int128(uint((lastUpdate - _timestampOpened) << 64) / BigMath.SecondsPerYear);
		if (yearsOpen == 0)
			return (1 ether);
		int128 stabilityFeeMultiplier = BigMath.Pow(int128(_stabilityFeeAPR << 32), yearsOpen);
		return uint(stabilityFeeMultiplier).mul(1 ether) >> 64;
	}

	/*
		@Description: find the new amount of ZCBs which is a vault's obligation

		@param address _FCPborrrowed: the address of the FCP contract associated with the debt asset of the Vault
		@param uint _amountBorrowed: the Vault's previous obligation in ZCBs at _timestampOpened
		@param uint64 _timestampOpened: the time at which the vault was opened
		@param uint64 _stabiliityFeeAPR: the annual rate which must be paid for stability fees

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

		@return address addr: the address for assetSupplied to pass to the vault health contract
		@return uint sAmt: the amount for amountSupplied to pass to the vault health contract
		@return uint bAmt: the amounf for amountBorrowed to pass to the vault health contract
	*/
	function passInfoToVaultManager(Vault memory _vault) internal view returns (address addr, uint sAmt, uint bAmt) {
		addr = _wrapperToUnderlyingAsset[_vault.assetSupplied];
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
		Vault memory vault,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) internal view returns (bool) {

		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_suppliedRateChange >= ABDK_1);
		require(_borrowRateChange <= ABDK_1);

		(address _suppliedAddrToPass, uint _suppliedAmtToPass, uint _borrowAmtToPass) = passInfoToVaultManager(vault);

		return vaultHealthContract.vaultWithstandsChange(
			false,
			_suppliedAddrToPass,
			vault.assetBorrowed,
			_suppliedAmtToPass,
			_borrowAmtToPass,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		);
	}

	/*
		@Description: check if a vault is above the upper or lower collateralization limit

		@param Vault memory _vault: vault for which to check if limit is satisfied
		@param bool _upper: true if we are to check the upper collateralization limit,
			false otherwise

		@return bool: true if vault satisfies the limit,
			false otherwise
	*/
	function satisfiesLimit(
		Vault memory _vault,
		bool _upper
	) internal view returns (bool) {

		(address _suppliedAddrToPass, uint _suppliedAmtToPass, uint _borrowAmtToPass) = passInfoToVaultManager(_vault);

		return ( _upper ?
			vaultHealthContract.satisfiesUpperLimit(_suppliedAddrToPass, _vault.assetBorrowed, _suppliedAmtToPass, _borrowAmtToPass)
				:
			vaultHealthContract.satisfiesLowerLimit(_suppliedAddrToPass, _vault.assetBorrowed, _suppliedAmtToPass, _borrowAmtToPass)
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

		require(_assetSupplied != _assetBorrowed);
		require(_fixCapitalPoolToWrapper[_assetSupplied] != address(0) || _wrapperToUnderlyingAsset[_assetSupplied] != address(0));

		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IWrapper baseBorrowed = IFixCapitalPool(FCPborrowed).wrapper();
		uint64 timestampOpened = uint64(baseBorrowed.lastUpdate());
		uint64 wrapperFee = _wrapperStabilityFees[address(baseBorrowed)];
		Vault memory vault = Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, timestampOpened, wrapperFee);

		require(vaultWithstandsChange(vault, _priceMultiplier, _suppliedRateChange, _borrowRateChange));

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
			IFixCapitalPool(FCPborrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(FCPborrowed, vault.amountBorrowed);
		}
		if (vault.amountSupplied > 0)
			IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);

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

		if (_assetBorrowed != mVault.assetBorrowed) {
			//ensure that after operations vault will be in good health
			require(_multipliers[0] > 0);
			require(msg.sender == _owner);
			require(vaultWithstandsChange(
				Vault(
					_assetSupplied,
					_assetBorrowed,
					_amountSupplied,
					_amountBorrowed,
					0,
					NO_STABILITY_FEE
				),
				uint(_multipliers[0]),
				_multipliers[1],
				_multipliers[2]
			));
			adjVaultChangeBorrow(
				mVault,
				sVault,
				_assetSupplied,
				_assetBorrowed,
				_amountSupplied,
				_amountBorrowed,
				_data,
				_receiverAddr
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
				//index 0 in multipliers that must be converted to uint
				require(_multipliers[0] > 0);
				require(msg.sender == _owner);
				require(vaultWithstandsChange(
					Vault(
						_assetSupplied,
						_assetBorrowed,
						_amountSupplied,
						_amountBorrowed,
						mVault.timestampOpened,
						mVault.stabilityFeeAPR
					),
					uint(_multipliers[0]),
					_multipliers[1],
					_multipliers[2]
				));
			}
			adjVaultSameBorrow(
				mVault,
				sVault,
				_assetSupplied,
				_assetBorrowed,
				_amountSupplied,
				_amountBorrowed,
				_data,
				_receiverAddr
			);
		}
	}

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
		if (mVault.amountBorrowed < _amountBorrowed) {
			FCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			raiseShortInterest(address(FCPBorrowed), _amountBorrowed - mVault.amountBorrowed);
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(address(FCPBorrowed), mVault.timestampOpened, mVault.stabilityFeeAPR);
			uint toMint = (_amountBorrowed - mVault.amountBorrowed).mul(stabilityFeeMultiplier) / (1 ether);
			FCPBorrowed.mintZCBTo(_receiverAddr, toMint);
			sVault.amountBorrowed = _amountBorrowed;
		}
		else if (mVault.amountBorrowed > _amountBorrowed) {
			FCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			sVault.amountBorrowed = _amountBorrowed;
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			IVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				mVault.assetSupplied,
				mVault.assetBorrowed,
				mVault.amountSupplied,
				mVault.amountBorrowed,
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
			lowerShortInterest(address(FCPBorrowed), mVault.amountBorrowed - _amountBorrowed);
			uint stabilityFeeMultiplier = getStabilityFeeMultiplier(address(FCPBorrowed), mVault.timestampOpened, mVault.stabilityFeeAPR);
			uint toBurn = (mVault.amountBorrowed - _amountBorrowed).mul(stabilityFeeMultiplier) / (1 ether);
			FCPBorrowed.burnZCBFrom(msg.sender,  toBurn);
		}
	}

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
		uint feeAdjBorrowAmt;
		if (address(_assetBorrowed) != address(0)) {
			IFixCapitalPool newFCPBorrowed = IFixCapitalPool(IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress());
			raiseShortInterest(address(newFCPBorrowed), _amountBorrowed);
			newFCPBorrowed.mintZCBTo(_receiverAddr, _amountBorrowed);
		}
		if (mVault.amountBorrowed > 0) {
			oldFCPBorrowed = IFixCapitalPool(IZeroCouponBond(mVault.assetBorrowed).FixCapitalPoolAddress());
			feeAdjBorrowAmt = stabilityFeeAdjAmountBorrowed(address(oldFCPBorrowed), mVault.amountBorrowed, mVault.timestampOpened, mVault.stabilityFeeAPR);
			lowerShortInterest(address(oldFCPBorrowed), mVault.amountBorrowed);
		}
		sVault.assetBorrowed = _assetBorrowed;
		sVault.amountBorrowed = _amountBorrowed;
		{
			address wrapperAddr = IZeroCouponBond(_assetBorrowed).WrapperAddress();
			sVault.stabilityFeeAPR = _wrapperStabilityFees[wrapperAddr];
			sVault.timestampOpened = uint64(IWrapper(wrapperAddr).lastUpdate());
		}

		//-----------------------------flashloan------------------
		if (_data.length > 0) {
			IVaultManagerFlashReceiver(_receiverAddr).onFlashLoan(
				msg.sender,
				mVault.assetSupplied,
				mVault.assetBorrowed,
				mVault.amountSupplied,
				mVault.amountBorrowed,
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
			oldFCPBorrowed.burnZCBFrom(msg.sender, feeAdjBorrowAmt);
			claimStabilityFee(mVault.assetBorrowed, address(oldFCPBorrowed), feeAdjBorrowAmt - mVault.amountBorrowed);
		}
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
		require(vault.amountBorrowed >= _amtIn && _amtIn > 0);
		uint maxBid = vault.amountSupplied * _amtIn / vault.amountBorrowed;
		require(maxBid >= _bid);
		if (satisfiesLimit(vault, true)) {
			uint maturity = IZeroCouponBond(vault.assetBorrowed).maturity();
			require(maturity < block.timestamp + MAX_TIME_TO_MATURITY);
		}
		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		uint feeAdjAmtIn = stabilityFeeAdjAmountBorrowed(FCPborrowed, _amtIn, vault.timestampOpened, vault.stabilityFeeAPR);
		collectBid(msg.sender, FCPborrowed, feeAdjAmtIn);
		claimStabilityFee(vault.assetBorrowed, FCPborrowed, feeAdjAmtIn - _amtIn);
		lowerShortInterest(FCPborrowed, _amtIn);
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
		require(0 < _amtIn && _amtIn <= liq.amountBorrowed);
		uint maxBid = liq.bidAmount * _amtIn / liq.amountBorrowed;
		require(_bid < maxBid);

		address FCPborrowed = IZeroCouponBond(liq.assetBorrowed).FixCapitalPoolAddress();
		refundBid(liq.bidder, FCPborrowed, _amtIn);
		collectBid(msg.sender, FCPborrowed, _amtIn);
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
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator would like to liquidate the entire vault
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _maxIn: the maximum amount of assetBorrowed that msg.sender is willing to bid on the vault
		@param uint _minOut: the minimum amount of assetSupplied that msg.sender wants to receive from this liquidation
		@param address _to: the address to which to send all of the collateral from the vault
	*/
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxIn, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _maxIn);
		require(vault.amountSupplied >= _minOut && _minOut > 0);
		require(IZeroCouponBond(_assetBorrowed).maturity() < block.timestamp + CRITICAL_TIME_TO_MATURITY || 
			!satisfiesLimit(vault, false));

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(FCPborrowed, vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);

		delete _vaults[_owner][_index];
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
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
		require(0 < _in && _in <= vault.amountBorrowed);
		uint amtOut = _in*vault.amountSupplied/vault.amountBorrowed;
		require(amtOut >= _minOut);
		require(IFixCapitalPool(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault, false));

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(vault.assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(FCPborrowed, _in);
		IERC20(_assetSupplied).transfer(_to, amtOut);

		_vaults[_owner][_index].amountBorrowed -= _in;
		_vaults[_owner][_index].amountSupplied -= amtOut;
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit 
			vaults may be liquidated instantly without going through the auction process, this is intended to help the VaultFactory
			keep solvency in the event of a market crisis
			this function is used when a liquidator whould like to only partially liquidate the vault by receiving a specific
			amount of assetSupplied and sending the corresponding amount of assetBorrowed
		@param address _owner: the owner of the vault to send to auction
		@param uint _index: the index of the vault in vaults[_owner] to send to auction
		@param address _assetBorrowed: the address of the expected borrow asset of the vault
		@param address _assetSupplied: the address of the expected supplied asset of the vault
		@param uint _out: the amount of assetSupplied to receive from the vault
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
		require(0 < amtIn && amtIn <= _maxIn);
		require(IFixCapitalPool(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault, false));

		//burn borrowed ZCB
		address FCPborrowed = IZeroCouponBond(_assetBorrowed).FixCapitalPoolAddress();
		IFixCapitalPool(FCPborrowed).burnZCBFrom(_to, amtIn);
		lowerShortInterest(FCPborrowed, amtIn);
		IERC20(_assetSupplied).transfer(_to, _out);

		_vaults[_owner][_index].amountBorrowed -= amtIn;
		_vaults[_owner][_index].amountSupplied -= _out;
	}

	/*
		@Description: assign a vault/YTvault to a new owner

		@param uint _index: the index within vaults/YTvaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault/YTvault
		@param bool _isYTVault: true when the vault to transfer is a YTvault, false otherwise
	*/
	function transferVault(uint _index, address _to, bool _isYTVault) external {
		if (_isYTVault) {
			transferYTVault(_index, _to);
		}
		else {
			transferStandardVault(_index, _to);
		}
	}

	/*
		@Description: assign a vault to a new owner

		@param uint _index: the index within vaults[msg.sender] at which the vault to transfer is located
		@param address _to: the new owner of the vault
	*/
	function transferStandardVault(uint _index, address _to) internal {
		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];
		_vaults[_to].push(vault);
		delete _vaults[msg.sender][_index];
	}

	/*
		@Description: assign a YT vault to a new owner

		@param uint _index: the index within YTvaults[msg.sender] at which the YT vault to transfer is located
		@param address _to: the new owner of the YT vault
	*/
	function transferYTVault(uint _index, address _to) internal {
		require(_YTvaults[msg.sender].length > _index);
		YTVault memory vault = _YTvaults[msg.sender][_index];
		_YTvaults[_to].push(vault);
		delete _YTvaults[msg.sender][_index];
	}

}