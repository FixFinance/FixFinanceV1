pragma solidity >=0.6.0;
import "./helpers/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/ABDKMath64x64.sol";

contract FeeOracle is Ownable {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	// 1.0 in basis points
	uint16 constant totalBasisPoints = 10_000;

	// 0.125 in basis points
	uint16 constant MaxMaxFee = 1_250;

	uint public maxFee;

	// 1.0 in 64.64 format
	int128 ABDK_1 = 1<<64;

	// 0.03125 in 64.64 format
	int128 constant MaxAnnualRate = 1<<59;

	//pct fee paid on swap with 1 year to maturity
	int128 public annualRate;

	uint private constant SecondsPerYear = 31556926;

	constructor(uint16 _maxFee, int128 _annualRate) public {
		setMaxFee(_maxFee);
		setAnnualRate(_annualRate);
	}

	function setMaxFee(uint16 _maxFee) public {
		require(_maxFee >= 0, "Max Fee must not be negative");
		require(_maxFee <= MaxMaxFee, "_maxFee parameter above upper limit");
		maxFee = _maxFee;
	}

	function setAnnualRate(int128 _annualRate) public {
		require(_annualRate >= 0, "annual rate must not be negative");
		require(_annualRate <= MaxAnnualRate, "_annualRate parameter above upper limit");
		annualRate = _annualRate;
	}

	/*
		Returns the percentage fee to be charged by the AMM denominated in basis points
	*/
	function getFeePct(uint _maturity) public returns (uint16 feePct) {
		require(_maturity > block.timestamp);
		int128 _annualRate = annualRate;	//gas savings
		if (_annualRate == 0) {
			return 0;
		}
		int128 yearsRemaining = int128(((block.timestamp - _maturity) << 64) / SecondsPerYear);
		/*
			(1-feePct) == (1 - annualRate)**yearsRemaining
			feePct == 1 - (1 - annualRate)**yearsRemaining

			innerTerm = 1 - annualRate;

			feePct == 1 - innerTerm**yearsRemaining
			feePct == 1 - 2**(log_2(innerTerm**yearsRemaining))
			feePct == 1 - 2**(yearsRemaining*log_2(innerTerm))
		*/
		//due to checks we have done earlier we do not need to use .sub here
		int128 innerTerm = ABDK_1 - _annualRate;
		//due to checks we have done earlier we do not need to use .sub here and to know that converting to uint is safe
		uint result = totalBasisPoints * uint(ABDK_1 - innerTerm.log_2().mul(yearsRemaining).exp_2()) >> 64;
		uint _maxFee = maxFee;	//gas savings
		return uint16(result > _maxFee ? _maxFee : result);
	}



	/*
		amountIn_preFee / (1 - getPctFee()) == amountIn_postFee
	*/
	function feeAdjustedAmtIn(uint _maturity, uint _amountIn_preFee) external returns (uint amountIn_postFee) {
		amountIn_postFee = totalBasisPoints * _amountIn_preFee / (totalBasisPoints - getFeePct(_maturity));
	}


	/*
		amountOut_preFee / (1 - getPctFee()) == amountOut_postFee
	*/
	function feeAdjustedAmtOut(uint _maturity, uint _amountOut_preFee) external returns (uint amountOut_postFee) {
		amountOut_postFee = totalBasisPoints * _amountOut_preFee / (totalBasisPoints - getFeePct(_maturity));
	}

}