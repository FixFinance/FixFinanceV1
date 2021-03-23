pragma solidity >=0.6.0;
import "./helpers/Ownable.sol";
import "./interfaces/ICapitalHandler.sol";
import "./libraries/SafeMath.sol";
import "./libraries/ABDKMath64x64.sol";
import "./libraries/BigMath.sol";

contract AmmInfoOracle is Ownable {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	uint16 constant totalBasisPoints = 10_000;

	uint private constant SecondsPerYear = 31556926;

	// 1.0 in 64.64 format
	int128 private constant ABDK_1 = 1<<64;

	// the treasury should receive no more than 40% of total fee revenue
	uint16 private constant MaxBipsToTreasury = 4_000;


	//pct fee paid on swap with 1 year to maturity
	int128 public annualRate;

	uint16 public bipsToTreasury;

	address public sendTo;

	mapping(address => uint) public WrapperToYTSlippageConst;

	mapping(address => uint) public WrapperToZCBFeeConst;

	mapping(address => uint) public WrapperToYTFeeConst;

	mapping(address => uint) public YTammSlippageConstants;

	mapping(address => uint) public ZCBammFeeConstants;

	mapping(address => uint) public YTammFeeConstants;

	/*
		init
	*/
	constructor(
		uint16 _bipsToTreasury,
		address _sendTo
	) public {
		setToTreasuryFee(_bipsToTreasury);
		sendTo = _sendTo;
	}

	/*
		@Description: owner of a wrapper may set the default fee constants for ZCB and YT amms that trade ZCB & YT
			that utilise their wrapper

		@param address _wrapper: the address of the wrapped asset that the owner would like to set the default
			fee constants for
		@param uint _ZCBammFeeConstant: the fee constant for ZCBamms, must be >= 1, inflated by (1 ether)
		@param uint _YTammFeeConstant: the fee constant for YTamms, must be >= 1, inflated by (1 ether)
	*/
	function wrapperSetFeeConstants(address _wrapper, uint _ZCBammFeeConstant, uint _YTammFeeConstant) public {
		require(msg.sender == Ownable(_wrapper).owner());
		require(_ZCBammFeeConstant >= 1 ether && _YTammFeeConstant >= 1 ether);
		WrapperToZCBFeeConst[_wrapper] = _ZCBammFeeConstant;
		WrapperToYTFeeConst[_wrapper] = _YTammFeeConstant;
	}

	/*
		@Description: owner of a wrapper may set the default slippage constant, for the YTamm for all YTamms that
			utilise their wrapper

		@param address _wrapper: the address of the wrapped asset that the owner would like to set the default
			slippage constant for
		@param uint _SlippageConstant: the sliippage constant for YTamms, inflated by 1 ether
	*/
	function wrapperSetSlippageConst(address _wrapper, uint _SlippageConstant) public {
		require(msg.sender == Ownable(_wrapper).owner());
		WrapperToYTSlippageConst[_wrapper] = _SlippageConstant;
	}

	/*
		@Description: owner of a capital handler contract may override the default fee constants based on the
			capital handler's wrapper and supplant it with their own fee constants

		@param address _capitalHandlerAddress: address of capital handler contract for which to set amm fee consts
		@param uint _ZCBammFeeConstant: the fee constant for the ZCBamm, must be >= 1, inflated by (1 ether)
		@param uint _YTammFeeConstant: the fee constant for the YTamm, must be >= 1, inflated by (1 ether)
	*/
	function setFeeConstants(address _capitalHandlerAddress, uint _ZCBammFeeConstant, uint _YTammFeeConstant) public {
		require(msg.sender == Ownable(_capitalHandlerAddress).owner());
		require(_ZCBammFeeConstant >= 1 ether && _YTammFeeConstant >= 1 ether);
		ZCBammFeeConstants[_capitalHandlerAddress] = _ZCBammFeeConstant;
		YTammFeeConstants[_capitalHandlerAddress] = _YTammFeeConstant;
	}

	/*
		@Description: owner of a capital handler may override the default slippage constant for the YTamm that
			utilises their capital handler contract.

		@param address _capitalHandlerAddress: address of capital handler contract for which to set YTamm slippage
		@param uint _SlippageConstant: the sliippage constant for YTamms, inflated by 1 ether
	*/
	function setSlippageConstant(address _capitalHandlerAddress, uint256 _SlippageConstant) public {
		require(msg.sender == Ownable(_capitalHandlerAddress).owner());
		YTammSlippageConstants[_capitalHandlerAddress] = _SlippageConstant;
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
	function treasuryFee(uint larger, uint smaller) external view returns (uint toTreasury, address _sendTo) {
		require(larger >= smaller);
		uint totalFee = larger - smaller;
		toTreasury = totalFee * bipsToTreasury / totalBasisPoints;
		_sendTo = sendTo;
	}

	/*
		@Description: given a capital handler return its corresponding ZCBamm fee constant
			if there is a specific constant for the capital handler return that,
			otherwise return the default fee constant for the wrapper that the capital handler is associated with

		@param address _capitalHandlerAddress: corresponds to the capital handler contract for which to find the
			ZCBamm fee constant

		@return uint FeeConstant: the ZCBamm fee constant corresponding to the capital handler contract
	*/
	function getZCBammFeeConstant(address _capitalHandlerAddress) external view returns (uint FeeConstant) {
		FeeConstant = ZCBammFeeConstants[_capitalHandlerAddress];
		if (FeeConstant == 0) {
			FeeConstant = WrapperToZCBFeeConst[address(ICapitalHandler(_capitalHandlerAddress).wrapper())];
		}
	}

	/*
		@Description: given a capital handler return its corresponding YTamm fee constant
			if there is a specific constant for the capital handler return that,
			otherwise return the default fee constant for the wrapper that the capital handler is associated with

		@param address _capitalHandlerAddress: corresponds to the capital handler contract for which to find the
			YTamm fee constant

		@return uint FeeConstant: the YTamm fee constant corresponding to the capital handler contract
	*/
	function getYTammFeeConstant(address _capitalHandlerAddress) external view returns (uint FeeConstant) {
		FeeConstant = YTammFeeConstants[_capitalHandlerAddress];
		if (FeeConstant == 0) {
			FeeConstant = WrapperToYTFeeConst[address(ICapitalHandler(_capitalHandlerAddress).wrapper())];
		}
	}

	/*
		@Description: given a capital handler return its corresponding YTamm slippage constant
			if there is a specific constant for the capital handler return that,
			otherwise return the default slippage constant for the wrapper that the capital handler is associated with

		@param address _capitalHandlerAddress: corresponds to the capital handler contract for which to find the
			YTamm slippage constant

		@return uint FeeConstant: the YTamm slippage constant corresponding to the capital handler contract
	*/
	function getSlippageConstant(address _capitalHandlerAddress) external view returns (uint SlippageConstant) {
		SlippageConstant = YTammSlippageConstants[_capitalHandlerAddress];
		if (SlippageConstant == 0) {
			SlippageConstant = WrapperToYTSlippageConst[address(ICapitalHandler(_capitalHandlerAddress).wrapper())];
		}
	}

	//--------------------------A-m-m-I-n-f-o-O-r-a-c-l-e---a-d-m-i-n-----------------------------

	/*
		@Description: admin may set the % of LP fees that go to the treasury
		
		@param uint16 _bipsToTreasury: the % of LP fees that shall go the treasury (denominated in basis points)
	*/
	function setToTreasuryFee(uint16 _bipsToTreasury) public onlyOwner {
		require(_bipsToTreasury <= MaxBipsToTreasury);
		bipsToTreasury = _bipsToTreasury;
	}

	/*
		@Description: admin may set the address that receives all treasury fees

		@param address _sendTo: the address that shall receive all treasury fees
	*/
	function setSendTo(address _sendTo) external onlyOwner {
		sendTo = _sendTo;
	}

}