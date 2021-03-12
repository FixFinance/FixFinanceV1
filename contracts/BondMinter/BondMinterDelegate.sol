pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "../libraries/SafeMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/Ownable.sol";
import "./BondMinterData.sol";

contract BondMinterDelegate is BondMinterData {
	using SafeMath for uint;

	function raiseShortInterest(address _capitalHandlerAddress, uint _amount) internal {
		address underlyingAssetAddress = ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress();
		uint temp = _shortInterestAllDurations[underlyingAssetAddress].add(_amount);
		require(vaultHealthContract.maximumShortInterest(underlyingAssetAddress) >= temp);
		_shortInterestAllDurations[underlyingAssetAddress] = temp;
	}

	function lowerShortInterest(address _capitalHandlerAddress, uint _amount) internal {
		address underlyingAssetAddress = ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress();
		_shortInterestAllDurations[underlyingAssetAddress] = _shortInterestAllDurations[underlyingAssetAddress].sub(_amount);
	}

	function passInfoToVaultManager(address _suppliedAsset, uint _suppliedAmount) internal view returns (address addr, uint amt) {
		addr = _wrapperToUnderlyingAsset[_suppliedAsset];
		if (addr == address(0)) {
			addr = _suppliedAsset;
			amt = _suppliedAmount;
		}
		else {
			amt = IWrapper(_suppliedAsset).WrappedAmtToUnitAmt_RoundDown(_suppliedAmount);
		}
	}

	function vaultWithstandsChange(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) internal view returns (bool) {

		require(_priceMultiplier >= TOTAL_BASIS_POINTS);
		require(_suppliedRateChange >= ABDK_1);
		require(_borrowRateChange <= ABDK_1);

		(address _suppliedAddrToPass, uint _suppliedAmtToPass) = passInfoToVaultManager(_assetSupplied, _amountSupplied);

		return vaultHealthContract.vaultWithstandsChange(
			_suppliedAddrToPass,
			_assetBorrowed,
			_suppliedAmtToPass,
			_amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		);
	}

	function satisfiesLimit(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		bool upper
		) internal view returns (bool) {

		(address _suppliedAddrToPass, uint _suppliedAmtToPass) = passInfoToVaultManager(_assetSupplied, _amountSupplied);

		return ( upper ?
			vaultHealthContract.satisfiesUpperLimit(_suppliedAddrToPass, _assetBorrowed, _suppliedAmtToPass, _amountBorrowed)
				:
			vaultHealthContract.satisfiesLowerLimit(_suppliedAddrToPass, _assetBorrowed, _suppliedAmtToPass, _amountBorrowed)
			);
	}


	function openVault(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external {

		require(_capitalHandlerToWrapper[_assetSupplied] != address(0) || _wrapperToUnderlyingAsset[_assetSupplied] != address(0));
		require(vaultWithstandsChange(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed, _priceMultiplier, _suppliedRateChange, _borrowRateChange));

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		ICapitalHandler(_assetBorrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(_assetBorrowed, _amountBorrowed);

		_vaults[msg.sender].push(Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed));
	}

	function closeVault(uint _index, address _to) external {
		uint len = _vaults[msg.sender].length;
		require(len > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0) {
			ICapitalHandler(vault.assetBorrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(vault.assetBorrowed, vault.amountBorrowed);
		}
		if (vault.amountSupplied > 0)
			IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);

		if (len - 1 != _index)
			_vaults[msg.sender][_index] = _vaults[msg.sender][len - 1];
		delete _vaults[msg.sender][len - 1];
	}

	function remove(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external {

		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		require(vault.amountSupplied >= _amount);
		require(vaultWithstandsChange(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied - _amount,
			vault.amountBorrowed,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		_vaults[msg.sender][_index].amountSupplied -= _amount;
		IERC20(vault.assetSupplied).transfer(_to, _amount);
	}

	function deposit(address _owner, uint _index, uint _amount) external {
		require(_vaults[_owner].length > _index);
		IERC20(_vaults[_owner][_index].assetSupplied).transferFrom(msg.sender, address(this), _amount);
		_vaults[_owner][_index].amountSupplied += _amount;
	}


	function borrow(
		uint _index,
		uint _amount,
		address _to,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external {

		require(_vaults[msg.sender].length > _index);
		Vault memory vault = _vaults[msg.sender][_index];

		require(vaultWithstandsChange(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			vault.amountBorrowed + _amount,
			_priceMultiplier,
			_suppliedRateChange,
			_borrowRateChange
		));

		_vaults[msg.sender][_index].amountBorrowed += _amount;

		ICapitalHandler(vault.assetBorrowed).mintZCBTo(_to, _amount);
		raiseShortInterest(vault.assetBorrowed, _amount);
	}

	function repay(address _owner, uint _index, uint _amount) external {
		require(_vaults[_owner].length > _index);
		require(_vaults[_owner][_index].amountBorrowed >= _amount);
		address assetBorrowed = _vaults[_owner][_index].assetBorrowed;
		ICapitalHandler(assetBorrowed).burnZCBFrom(msg.sender, _amount);
		lowerShortInterest(assetBorrowed, _amount);
		_vaults[_owner][_index].amountBorrowed -= _amount;
	}

	//----------------------------------------------_Liquidations------------------------------------------

	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _minOut) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _bid);
		require(vault.amountSupplied >= _minOut);
		if (satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, true)) {
			uint maturity = ICapitalHandler(vault.assetBorrowed).maturity();
			require(maturity < block.timestamp + (7 days));
		}
		//burn borrowed ZCB
		ICapitalHandler(vault.assetBorrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
		lowerShortInterest(vault.assetBorrowed, vault.amountBorrowed);
		//any surplus in the bid may be added as _revenue
		if (_bid > vault.amountBorrowed){
			IERC20(vault.assetBorrowed).transferFrom(msg.sender, address(this), _bid - vault.amountBorrowed);
			_revenue[vault.assetBorrowed] += _bid - vault.amountBorrowed;
		}

		delete _vaults[_owner][_index];
		_Liquidations.push(Liquidation(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			msg.sender,
			_bid,
			block.timestamp
		));
	}

	function bidOnLiquidation(uint _index, uint _bid) external {
		require(_Liquidations.length > _index);
		Liquidation memory liquidation = _Liquidations[_index];
		require(_bid > liquidation.bidAmount);

		ICapitalHandler(liquidation.assetBorrowed).burnZCBFrom(msg.sender, _bid);
		ICapitalHandler(liquidation.assetBorrowed).mintZCBTo(liquidation.bidder, liquidation.bidAmount);
		ICapitalHandler(liquidation.assetBorrowed).mintZCBTo(address(this), _bid - liquidation.bidAmount);

		_revenue[liquidation.assetBorrowed] += _bid - liquidation.bidAmount;
		_Liquidations[_index].bidAmount = _bid;
		_Liquidations[_index].bidder = msg.sender;
		_Liquidations[_index].bidTimestamp = block.timestamp;
	}

	function claimLiquidation(uint _index, address _to) external {
		require(_Liquidations.length > _index);
		Liquidation memory liquidation = _Liquidations[_index];
		require(msg.sender == liquidation.bidder);
		require(block.timestamp - liquidation.bidTimestamp >= 10 minutes);

		delete _Liquidations[_index];

		IERC20(liquidation.assetSupplied).transfer(_to, liquidation.amountSupplied);
	}

	/*
		@Description: when there is less than 1 day until maturity or _vaults are under the lower collateralisation limit _vaults may be liquidated instantly without going through the auction process
	*/
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxBid, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _maxBid);
		require(vault.amountSupplied >= _minOut);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		ICapitalHandler(_assetBorrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(_assetBorrowed, vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);

		delete _vaults[_owner][_index];
	}

	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(_in <= vault.amountBorrowed);
		uint amtOut = _in*vault.amountSupplied/vault.amountBorrowed;
		require(vault.amountSupplied >= amtOut);
		require(amtOut >= _minOut);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB

		ICapitalHandler(_assetBorrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(_assetBorrowed, _in);
		IERC20(_assetSupplied).transfer(_to, amtOut);

		_vaults[_owner][_index].amountBorrowed -= _in;
		_vaults[_owner][_index].amountSupplied -= amtOut;
	}

	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external {
		require(_vaults[_owner].length > _index);
		Vault memory vault = _vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountSupplied >= _out);
		uint amtIn = _out*vault.amountBorrowed;
		amtIn = amtIn/vault.amountSupplied + (amtIn%vault.amountSupplied == 0 ? 0 : 1);
		require(amtIn <= _maxIn);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!satisfiesLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed, false));

		//burn borrowed ZCB
		IERC20(_assetBorrowed).transferFrom(msg.sender, address(0), amtIn);
		IERC20(_assetSupplied).transfer(_to, _out);

		_vaults[_owner][_index].amountBorrowed -= amtIn;
		_vaults[_owner][_index].amountSupplied -= _out;
	}

}