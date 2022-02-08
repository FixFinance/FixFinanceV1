// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../helpers/Ownable.sol";
import "../interfaces/IOrderbookExchange.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IOrganizer.sol";
import "../interfaces/IVaultHealth.sol";
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../oracle/interfaces/IOracleContainer.sol";
import "./VaultHealthDelegateParent.sol";


contract VaultHealthDelegate2 is VaultHealthDelegateParent {
	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	/*
		@Description: check if a vault is above the upper collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the upper collateralisation limit
			false otherwise
	*/
	function satisfiesUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool) {
		return _amountSupplied > _amountSuppliedAtUpperLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: check if a vault is above the lower collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the lower collateralisation limit
			false otherwise
	*/
	function satisfiesLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external view returns (bool) {
		return _amountSupplied > _amountSuppliedAtLowerLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: check if a YT vault is above the upper collateralisation limit

		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the upper collateralisation limit
			false otherwise
	*/
	function YTvaultSatisfiesUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external view returns (bool) {
		return _amountBorrowed < _YTvaultAmountBorrowedAtUpperLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: check if a YT vault is above the lower collateralisation limit

		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault

		@return bool: returns true if the vault is above the lower collateralisation limit
			false otherwise
	*/
	function YTvaultSatisfiesLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external view returns (bool) {
		return _amountBorrowed < _YTvaultAmountBorrowedAtLowerLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: returns value from _amountSuppliedAtUpperLimit() externally
	*/
	function amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view returns (uint) {
		return _amountSuppliedAtUpperLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: returns value from _amountSuppliedAtLowerLimit() externally
	*/
	function amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view returns (uint) {
		return _amountSuppliedAtLowerLimit(_assetSupplied, _assetBorrowed, _amountBorrowed);
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed for a vault stay above the upper collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault

		@return uint: the maximum amount of borrowed asset that must be borrowed from a vault in order for the vault to stay above the
			upper collateralisation limit
	*/
	function amountBorrowedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external view returns (uint) {
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(1 ether)
			.mul(combinedRateMultipliers_onlyMultiplier(true, true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));
		return term1
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
	}

	/*
		@Description: find the maximum amount of borrowed asset that may be borrowed for a vault stay above the lower collateralisation limit

		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault

		@return uint: the maximum amount of borrowed asset that must be borrowed from a vault in order for the vault to stay above the
			lower collateralisation limit
	*/
	function amountBorrowedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external view returns (uint) {
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint term1 = _amountSupplied
			.mul(1 ether)
			.mul(combinedRateMultipliers_onlyMultiplier(true, false, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));
		return term1
			.div(crossAssetPrice(_baseSupplied, _baseBorrowed))
			.div(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.LOW));
	}

	/*
		@Description: returns _YTvaultAmountBorrowedAtUpperLimit externally
	*/
	function YTvaultAmountBorrowedAtUpperLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) external view returns (uint) {
		return _YTvaultAmountBorrowedAtUpperLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: returns _YTvaultAmountBorrowedAtLowerLimit externally
	*/
	function YTvaultAmountBorrowedAtLowerLimit(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond
	) external view returns (uint) {
		return _YTvaultAmountBorrowedAtLowerLimit(_FCPsupplied, _FCPborrowed, _amountYield, _amountBond);
	}

	/*
		@Description: see description in core VaultHealth contract
	*/
	function upperLimitLiquidationDetails(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
	) external view returns(
		bool satisfies,
		uint amountToLiquidator,
		uint amountToProtocol
	) {
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);

		uint CAP = crossAssetPrice(_baseSupplied, _baseBorrowed);

		//new scope to prevent stack too deep
		{
			uint CCR = crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER);

			//wierd hack to prevent stack too deep
			uint minSupplied = _amountBorrowed.mul(CAP);
			minSupplied = minSupplied.mul(CCR).div(1 ether);
			minSupplied = minSupplied.div(combinedRateMultipliers_onlyMultiplier(true, true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, ABDK_1, ABDK_1));

			if (minSupplied <=  _amountSupplied) {
				return (true, 0, 0);
			}
		}
		uint CRM = combinedRateMultipliers_noAdjuster(true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed);

		//borrowedAmt * CAP * CCR / CRM == minSupplied
		//borrowedAmt == minSupplied * CRM / CAP / CCR
		//suppliedValue == amountSupplied * CRM / CAP / CCR
		//suppliedValue == amountSupplied * CRM / CAP

		uint collateralValue = _amountSupplied * CRM / CAP;
		uint liquidatorBonusMultiplier = uint(liquidatorBonus[_baseSupplied]).add(uint(liquidatorBonus[_baseBorrowed])).add(1 ether);
		amountToLiquidator = collateralValue.mul(liquidatorBonusMultiplier) / (1 ether);
		amountToProtocol = collateralValue.mul(uint(protocolLiqFee[_baseSupplied]).add(uint(protocolLiqFee[_baseBorrowed]))) / (1 ether);
		require(amountToLiquidator.add(amountToProtocol) >= _amountSupplied); // if amountToLiquidator + amountToProtocol < _amountSupplied then instant liquidations at SECURITY.LOW should be performed instead
		satisfies = true;
	}

	/*
		@Description: ensure that a vault will not be sent into liquidation zone if price changes a specified amount
			and rates change by a multiplier

		@param bool _reqSameBase: if true require that base wrapper of supplied and borrowed are the same
		@param address _assetSupplied: the address of the asset supplied to the vault
		@param address _assetBorrowed: the address of the asset borrowed from the vault
		@param uint _amountSupplied: the amount of _assetSupplied that has been supplied to the vault
		@param uint _amountBorrowed: the amount of _assetBorrowed that has been borrowed from the vault
		@param uint _priceMultiplier: the multiplier by which cross asset price of deposit versus borrowed asset changes
			inflated by TOTAL_BASIS_POINTS
		@param int128 _suppliedRateChange: the multiplier by which the rate of the supplied asset will change
			in ABDK64.64 format
		@param int128 _borrowRateChange: the multiplier by which the rate of the borrowed asset will change
			in ABDK64.64 format

		@return bool: returns true if vault will stay above liquidation zone
			false otherwise
	*/
	function vaultWithstandsChange(
		bool _reqSameBase,
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) public view returns(bool) {
		(address _baseSupplied, address _baseBorrowed, address fcpSupplied, address fcpBorrowed) = baseAssetAddresses(_assetSupplied, _assetBorrowed);
		require(!_reqSameBase || _baseSupplied == _baseBorrowed);

		//wierd hack to prevent stack too deep
		_amountBorrowed = _amountBorrowed
			.mul(crossAssetPrice(_baseSupplied, _baseBorrowed));
		_amountBorrowed = _amountBorrowed
			.div(combinedRateMultipliers_onlyMultiplier(true, true, fcpSupplied, _baseSupplied, fcpBorrowed, _baseBorrowed, _suppliedRateChange, _borrowRateChange));
		_amountBorrowed = _amountBorrowed
			.mul(crossCollateralizationRatio(_baseSupplied, _baseBorrowed, Safety.UPPER));
		_amountBorrowed = _amountBorrowed
			.mul(_priceMultiplier)
			.div((1 ether)*TOTAL_BASIS_POINTS);

		return _amountBorrowed < _amountSupplied;
	}

	/*
		@Description: ensure that a vault will not be sent into liquidation zone if price changes a specified amount
			and rates change by a multiplier

		@param bool _reqSameBase: if true require that base wrapper of supplied and borrowed are the same
		@param address _FCPsupplied: the address of the Capitalhandler supplied to the vault
		@param address _FCPborrowed: the address of the asset borrowed from the vault
		@param uint _amountYield: the amount of YT being supplied to the vault (in unit amount)
		@param int _amountBond: the difference between the amount of ZCB supplied to the vault and the amount of YT supplied
			amtZCB - amtYT == _amountBond
		@param uint _amountBorrowed: the amount of ZCB from _FCPborrowed that has been borrowed from the vault
		@param uint _priceMultiplier: the multiplier by which cross asset price of deposit versus borrowed asset changes
			inflated by TOTAL_BASIS_POINTS
		@param int128 _suppliedRateChange: the multiplier by which the rate of the supplied asset will change
			in ABDK64.64 format
		@param int128 _borrowedRateChange: the multiplier by which the rate of the borrowed asset will change
			in ABDK64.64 format

		@return bool: returns true if vault will stay above liquidation zone
			false otherwise
	*/
	function YTvaultWithstandsChange(
		bool _reqSameBase,
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond,
		uint _amountBorrowed,
		uint _priceMultiplier,
		int128 _suppliedRateChange,
		int128 _borrowedRateChange
	) external view returns (bool) {
		(address _baseSupplied, address _baseBorrowed) = bothFCPtoBaseAddresses(_FCPsupplied, _FCPborrowed);
		require(!_reqSameBase || _baseSupplied == _baseBorrowed);

		bool positiveBond = _amountBond >= 0;
		uint maxBorrowed;
		if (!positiveBond && _baseSupplied == _baseBorrowed && getYearsRemaining(_FCPsupplied, _baseSupplied) > 0) {
			maxBorrowed = YTvaultAmtBorrowedUL_1(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, _suppliedRateChange, _borrowedRateChange);
		}
		else {
			maxBorrowed = YTvaultAmtBorrowedUL_0(_FCPsupplied, _baseSupplied, _FCPborrowed, _baseBorrowed, _amountYield, _amountBond, _suppliedRateChange, _borrowedRateChange);
		}
		//account for price multiplier
		uint adjMaxBorrowed = maxBorrowed.mul(TOTAL_BASIS_POINTS).div(_priceMultiplier);
		return _amountBorrowed < adjMaxBorrowed;
	}
}