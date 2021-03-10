pragma solidity >=0.6.0;
import "./helpers/Ownable.sol";
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

	uint256 public SlippageConstant;

	uint256 public ZCBammFeeConstant;

	uint256 public YTammFeeConstant;

	constructor(
		uint16 _bipsToTreasury,
		uint _SlippageConstant,
		uint _ZCBammFeeConstant,
		uint _YTammFeeConstant,
		address _sendTo
		) public {

		setToTreasuryFee(_bipsToTreasury);
		SlippageConstant = _SlippageConstant;
		setFeeConstants(_ZCBammFeeConstant, _YTammFeeConstant);
		sendTo = _sendTo;
	}

	function setToTreasuryFee(uint16 _bipsToTreasury) public onlyOwner {
		require(_bipsToTreasury <= MaxBipsToTreasury);
		bipsToTreasury = _bipsToTreasury;
	}

	function setSendTo(address _sendTo) external onlyOwner {
		sendTo = _sendTo;
	}

	function setFeeConstants(uint _ZCBammFeeConstant, uint _YTammFeeConstant) public onlyOwner {
		require(_ZCBammFeeConstant >= 1 ether && _YTammFeeConstant >= 1 ether);
		ZCBammFeeConstant = _ZCBammFeeConstant;
		YTammFeeConstant = _YTammFeeConstant;
	}

	function setSlippageConstant(uint256 _SlippageConstant) public onlyOwner {
		SlippageConstant = _SlippageConstant;
	}

	function treasuryFee(uint larger, uint smaller) external view returns (uint toTreasury, address _sendTo) {
		require(larger >= smaller);
		uint totalFee = larger - smaller;
		toTreasury = totalFee * bipsToTreasury / totalBasisPoints;
		_sendTo = sendTo;
	}

}