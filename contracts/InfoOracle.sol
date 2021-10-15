// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./helpers/Ownable.sol";
import "./interfaces/IWrapper.sol";
import "./interfaces/IInfoOracle.sol";
import "./interfaces/IFixCapitalPool.sol";
import "./libraries/SafeMath.sol";
import "./libraries/ABDKMath64x64.sol";
import "./libraries/BigMath.sol";

contract InfoOracle is IInfoOracle, Ownable {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	uint16 constant totalBasisPoints = 10_000;

	uint private constant SecondsPerYear = 31556926;

	// 1.0 in 64.64 format
	int128 private constant ABDK_1 = 1<<64;

	// the treasury should receive no more than 40% of total AMM fee revenue
	uint16 private constant MaxBipsToTreasury = 4_000;

	uint16 public override bipsToTreasury;

	uint8 public override MinimumOrderbookFee; //denominated in bips

	bool public override TreasuryFeeIsCollected;

	address public immutable override sendTo;

	mapping(address => uint) public override WrapperToYTSlippageConst;

	mapping(address => uint) public override WrapperToZCBFeeConst;

	mapping(address => uint) public override WrapperToYTFeeConst;

	mapping(address => uint) public override YTammSlippageConstants;

	mapping(address => uint) public override ZCBammFeeConstants;

	mapping(address => uint) public override YTammFeeConstants;

	mapping(address => uint8) public override WrapperOrderbookFeeBips;

	mapping(address => uint8) public override FCPOrderbookFeeBips;

	mapping(address => address) public override DelegatedControllers;

	mapping(address => mapping(address => uint64)) public override StabilityFeeAPR;

	/*
		VaultFactory => collateralAsset => (collateralAsset is IWrapper ? underlyingAsset : address(1) )
	*/
	mapping(address => mapping(address => address)) public override collateralWhitelist;

	/*	
		VaultFactory => FCPaddress => wrapperAddress
		acts as FCP whitelist, if FCP is not listed in here it is not whitelisted
	*/
	mapping(address => mapping(address => address)) public override FCPtoWrapper;

	/*
		init
	*/
	constructor(
		uint16 _bipsToTreasury,
		address _sendTo,
		bool _TreasuryFeeIsCollected
	) public {
		setToTreasuryFee(_bipsToTreasury);
		sendTo = _sendTo;
		TreasuryFeeIsCollected = _TreasuryFeeIsCollected;
	}

	/*
		@Description: ensure that msg.sender is either owner of contract for which to set params
			or msg.sender is delegated to set the params

		@param address _contractAddr: the contract for which to set params
	*/
	modifier maySetContractParameters(address _contractAddr) {
		address contractOwner = Ownable(_contractAddr).owner();
		if (msg.sender != contractOwner) {
			address delegatedController = DelegatedControllers[_contractAddr];
			require(msg.sender == delegatedController);
		}
		_;
	}


	/*
		@Description: delegate ability to customise parameters for wrappers and FCPs to another address

		@param address _contract: the contract for which custom parameters may be set
		@param address _manager: the address that shall customise parameters for the contract
	*/
	function setDelegatedController(address _contract, address _manager) external override {
		require(Ownable(_contract).owner() == msg.sender);
		DelegatedControllers[_contract] = _manager;
	}

	/*
		@Description: owner of a wrapper may set the default fee constants for ZCB and YT amms that trade ZCB & YT
			that utilise their wrapper

		@param address _wrapper: the address of the wrapped asset that the owner would like to set the default
			fee constants for
		@param uint _ZCBammFeeConstant: the fee constant for ZCBamms, must be >= 1, inflated by (1 ether)
		@param uint _YTammFeeConstant: the fee constant for YTamms, must be >= 1, inflated by (1 ether)
	*/
	function wrapperSetAmmFeeConstants(address _wrapper, uint _ZCBammFeeConstant, uint _YTammFeeConstant) external override  maySetContractParameters(_wrapper) {
		require(_ZCBammFeeConstant >= 1 ether && _YTammFeeConstant >= 1 ether);
		WrapperToZCBFeeConst[_wrapper] = _ZCBammFeeConstant;
		WrapperToYTFeeConst[_wrapper] = _YTammFeeConstant;
	}

	/*
		@Description: set the default spread in bips that will be taken from orderbook trades on orderbooks for FCPs on a specific wrapper asset

		@param address _wrapper: the address of the wrapper contract for which to set the default orderbook fee
		@param uint8 _orderbookFeeBips: the amount of basis points that will be charged on every orderbook trade,
			inflated by 1 bip
			if _orderbookFeeBips is 0 this means that no general wrapper fee will be taken into account
	*/
	function wrapperSetOrderbookFeeConstant(address _wrapper, uint8 _orderbookFeeBips) external override maySetContractParameters(_wrapper) {
		WrapperOrderbookFeeBips[_wrapper] = _orderbookFeeBips;
	}

	/*
		@Description: owner of a wrapper may set the default slippage constant, for the YTamm for all YTamms that
			utilise their wrapper

		@param address _wrapper: the address of the wrapped asset that the owner would like to set the default
			slippage constant for
		@param uint _SlippageConstant: the sliippage constant for YTamms, inflated by 1 ether
	*/
	function wrapperSetSlippageConst(address _wrapper, uint _SlippageConstant) external override maySetContractParameters(_wrapper) {
		WrapperToYTSlippageConst[_wrapper] = _SlippageConstant;
	}

	/*
		@Description: owner of a fix capital pool contract may override the default fee constants based on the
			fix capital pool's wrapper and supplant it with their own fee constants

		@param address _fixCapitalPoolAddress: address of fix capital pool contract for which to set amm fee consts
		@param uint _ZCBammFeeConstant: the fee constant for the ZCBamm, must be >= 1, inflated by (1 ether)
		@param uint _YTammFeeConstant: the fee constant for the YTamm, must be >= 1, inflated by (1 ether)
	*/
	function setAmmFeeConstants(address _fixCapitalPoolAddress, uint _ZCBammFeeConstant, uint _YTammFeeConstant) external override maySetContractParameters(_fixCapitalPoolAddress) {
		require(_ZCBammFeeConstant >= 1 ether && _YTammFeeConstant >= 1 ether);
		ZCBammFeeConstants[_fixCapitalPoolAddress] = _ZCBammFeeConstant;
		YTammFeeConstants[_fixCapitalPoolAddress] = _YTammFeeConstant;
	}

	/*
		@Description: set spread in bips that will be taken from orderbook trades on the orderbook for a specific FCP contract

		@param address _fixCapitalPoolAddress: the address of the FCP for which to set the specific orderbook fee constant
		@param uint8 _orderbookFeeBips: the amount of basis points that will be charged on every orderbook trade
			inflated by 1 bip
			if _orderbookFeeBips is 0 this means that no specific fee will be taken into account
	*/
	function setOrderbookFeeConstant(address _fixCapitalPoolAddress, uint8 _orderbookFeeBips) external override maySetContractParameters(_fixCapitalPoolAddress) {
		FCPOrderbookFeeBips[_fixCapitalPoolAddress] = _orderbookFeeBips;
	}

	/*
		@Description: owner of a fix capital pool may override the default slippage constant for the YTamm that
			utilises their fix capital pool contract.

		@param address _fixCapitalPoolAddress: address of fix capital pool contract for which to set YTamm slippage
		@param uint _SlippageConstant: the sliippage constant for YTamms, inflated by 1 ether
	*/
	function setSlippageConstant(address _fixCapitalPoolAddress, uint256 _SlippageConstant) external override maySetContractParameters(_fixCapitalPoolAddress) {
		YTammSlippageConstants[_fixCapitalPoolAddress] = _SlippageConstant;
	}

	/*
		@Description: set the desired stability fee of a VaultFactory for a specific wrapper asset

		@param address _vaultFactoryAddress: the address of the VaultFactory for which to set the stability fee
		@param address _wrapperAsset: the address of the IWrapper contract for which to set the desired stability fee
		@param uint64 _stabilityFeeAPR: the new stability fee for the wrapper asset
	*/
	function setStabilityFeeAPR(address _vaultFactoryAddress, address _wrapperAsset, uint64 _stabilityFeeAPR) external override maySetContractParameters(_vaultFactoryAddress) {
		StabilityFeeAPR[_vaultFactoryAddress][_wrapperAsset] = _stabilityFeeAPR;
	}

	/*
		@Description: admin of a DBSFVaultFactory may call this function to allow usage of a IWrapper asset as collateral

		@param address _vaultFactoryAddress: the address of the DBSFVaultFactory for which to allow the IWrapper as collateral
		@param address _wrapperAddress: the address of the IWrapper to add as collateral
	*/
	function whitelistWrapper(address _vaultFactoryAddress, address _wrapperAddress) external override maySetContractParameters(_vaultFactoryAddress) {
		require(IWrapper(_wrapperAddress).isDistributionAccount(_vaultFactoryAddress));
		collateralWhitelist[_vaultFactoryAddress][_wrapperAddress] = IWrapper(_wrapperAddress).underlyingAssetAddress();
	}

	/*
		@Description: admin of a DBSFVaultFactory may call this function to allow usage of a non IWrapper asset as collateral

		@param address _vaultFactoryAddress: the address of the DBSFVaultFactory for which to allow the non IWrapper as collateral
		@param address _assetAddress: the address of the non IWrapper asset to add as collateral
	*/
	function whitelistAsset(address _vaultFactoryAddress, address _assetAddress) external override maySetContractParameters(_vaultFactoryAddress) {
		collateralWhitelist[_vaultFactoryAddress][_assetAddress] = address(1);
	}

	/*
		@Description: admin of a DBSFVaultFactory may call this function to whitelist an FCP to be used as collateral

		@param address _vaultFactoryAddress: the address of the DBSFVaultFactory for which to allow the FCP as collateral
		@param address _FCPaddress: the address of the FCP which to add as collateral
	*/
	function whitelistFixCapitalPool(address _vaultFactoryAddress, address _FCPaddress) external override maySetContractParameters(_vaultFactoryAddress) {
		IWrapper wrapper = IFixCapitalPool(_FCPaddress).wrapper();
		require(wrapper.isDistributionAccount(_vaultFactoryAddress));
		FCPtoWrapper[_vaultFactoryAddress][_FCPaddress] = address(wrapper);
	}

	//--------------------------------------------v-i-e-w-s------------------------------

	/*
		@Description: based on swap inputs/outputs find the total fee and return the total amount of fee
			that must be sent to the treasury

		@param uint larger: the larger of the tx inputs/outputs
		@param uint smaller: the smaller of the tx inputs/outputs

		@return uint toTreasury: the amount of fee that must be sent to the treasury
		@return address _sendTo: the address that shall receive the treasury fee
	*/
	function treasuryFee(uint larger, uint smaller) external view override returns (uint toTreasury, address _sendTo) {
		require(larger >= smaller);
		uint totalFee = larger - smaller;
		toTreasury = totalFee * bipsToTreasury / totalBasisPoints;
		_sendTo = sendTo;
	}

	/*
		@Description: given a fix capital pool return its corresponding ZCBamm fee constant
			if there is a specific constant for the fix capital pool return that,
			otherwise return the default fee constant for the wrapper that the fix capital pool is associated with

		@param address _fixCapitalPoolAddress: corresponds to the fix capital pool contract for which to find the
			ZCBamm fee constant

		@return uint FeeConstant: the ZCBamm fee constant corresponding to the fix capital pool contract
	*/
	function getZCBammFeeConstant(address _fixCapitalPoolAddress) external view override returns (uint FeeConstant) {
		FeeConstant = ZCBammFeeConstants[_fixCapitalPoolAddress];
		if (FeeConstant == 0) {
			FeeConstant = WrapperToZCBFeeConst[address(IFixCapitalPool(_fixCapitalPoolAddress).wrapper())];
		}
	}

	/*
		@Description: given a fix capital pool return its corresponding YTamm fee constant
			if there is a specific constant for the fix capital pool return that,
			otherwise return the default fee constant for the wrapper that the fix capital pool is associated with

		@param address _fixCapitalPoolAddress: corresponds to the fix capital pool contract for which to find the
			YTamm fee constant

		@return uint FeeConstant: the YTamm fee constant corresponding to the fix capital pool contract
	*/
	function getYTammFeeConstant(address _fixCapitalPoolAddress) external view override returns (uint FeeConstant) {
		FeeConstant = YTammFeeConstants[_fixCapitalPoolAddress];
		if (FeeConstant == 0) {
			FeeConstant = WrapperToYTFeeConst[address(IFixCapitalPool(_fixCapitalPoolAddress).wrapper())];
		}
	}

	/*
		@Description: given a FCP return its corresponding orderbook fee, in basis points
			if there is a specific fee for the FCP get that,
			otherwise get the default fee constant for the wrapper that the FCP is associated with
			once the specific or default fee has been found if it is less than the minimum orderbook fee
			increase it to the minimum orderbook fee

		@param address _fixCapitalPoolAddress: corresponds to the FCP contract for which to find the Orderbook fee

		@return uint8 FeeBips: the Orderbook fee in basis points corresponding to the FCP contract
	*/
	function getOrderbookFeeBips(address _fixCapitalPoolAddress) external view override returns (uint8 FeeBips) {
		FeeBips = FCPOrderbookFeeBips[_fixCapitalPoolAddress];
		if (FeeBips == 0) {
			FeeBips = WrapperOrderbookFeeBips[address(IFixCapitalPool(_fixCapitalPoolAddress).wrapper())];
		}
		if (FeeBips != 0) {
			FeeBips--;
		}
		uint8 _minimumOrderbookFee = MinimumOrderbookFee;
		FeeBips = FeeBips < _minimumOrderbookFee ? _minimumOrderbookFee : FeeBips;
	}

	/*
		@Description: given a fix capital pool return its corresponding YTamm slippage constant
			if there is a specific constant for the fix capital pool return that,
			otherwise return the default slippage constant for the wrapper that the fix capital pool is associated with

		@param address _fixCapitalPoolAddress: corresponds to the fix capital pool contract for which to find the
			YTamm slippage constant

		@return uint FeeConstant: the YTamm slippage constant corresponding to the fix capital pool contract
	*/
	function getSlippageConstant(address _fixCapitalPoolAddress) external view override returns (uint SlippageConstant) {
		SlippageConstant = YTammSlippageConstants[_fixCapitalPoolAddress];
		if (SlippageConstant == 0) {
			SlippageConstant = WrapperToYTSlippageConst[address(IFixCapitalPool(_fixCapitalPoolAddress).wrapper())];
		}
	}

	//-----------------------I-n-f-o-O-r-a-c-l-e---a-d-m-i-n-----------------------------

	/*
		@Description: set the floor on the orderbook fee

		@param uint8 _minimumOrderbookFee: the minimum orderbook fee in bips
	*/
	function setMinimumOrderbookFee(uint8 _minimumOrderbookFee) external override onlyOwner {
		MinimumOrderbookFee = _minimumOrderbookFee;
	}


	/*
		@Description: admin may set the % of LP fees that go to the treasury
		
		@param uint16 _bipsToTreasury: the % of LP fees that shall go the treasury (denominated in basis points)
	*/
	function setToTreasuryFee(uint16 _bipsToTreasury) public override onlyOwner {
		require(_bipsToTreasury <= MaxBipsToTreasury);
		bipsToTreasury = _bipsToTreasury;
	}

	/*
		@Description: amin may set whether or not the treasury fee shall be collected

		@param bool _TreasuryFeeIsCollected: the new value that TreasuryFeeIsCollected shall be set to
	*/
	function setTreasuryFeeIsCollected(bool _TreasuryFeeIsCollected) external override onlyOwner {
		TreasuryFeeIsCollected = _TreasuryFeeIsCollected;
	}
}