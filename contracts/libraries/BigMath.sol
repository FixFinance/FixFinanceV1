pragma solidity >=0.5.0;

import "./ABDKMath64x64.sol";
import "./SignedSafeMath.sol";
import "./SafeMath.sol";
import "./Ei.sol";

import "../AmmInfoOracle.sol";

library BigMath {
  using ABDKMath64x64 for int128;
  using SignedSafeMath for int256;
  using SafeMath for uint256;

  /*
    we keep error bound here such that we won't exceed 35 iterations in the power series 
    epsilon ~ 0.000000000108420217248550443400745280086994171142578125 * 2**64

  */
  int128 private constant epsilon = 2000000000;

  int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  int128 public constant ABDK_1 = 1<<64;

  uint public constant SecondsPerYear = 31556926;


  /*
    @Description: find the pool constant for the YT-U amm given current pool reserves

    @param uint Y: amount of pool reserves of Yield Tokens, inflated by 64 bits
    @param uint L: amount of Liquidity tokens, inflated by 64 bits
    @param uint r: amount of time remaining / anchor, inflated by 64 bits
    @param uint w: slippage minimiser variable inflated by 1 ether
    @param uint feeConstant: raise APY in differential equation to feeConstant
    @param int128 APYo: the apy returned from the oracle inflated by 64 bits

    @return int256: YTamm pool constant minus U
  */
  function YT_U_PoolConstantMinusU(uint256 Y, uint256 L, uint256 r, uint256 w, uint256 feeConstant, int128 APYo) public pure returns (int256) {
    /*
      K - U  = - (c+Y)*(APYo)**(-S*r/(Y+c)) - S*r*ln(APYo)*Ei(-S*r*ln(APYo)/(Y+c)) + Y
      K - U  = - (c+Y)*(APYo)**(-S*r/(Y+c)) + (-S*r)*ln(APYo)*Ei(-S*r*ln(APYo)/(Y+c)) + Y

      y_c = Y+c
      term0 = -S*r

      K - U  = - y_c*(APYo)**(term0/y_c) + term0*ln(APYo)*Ei(term0*ln(APYo)/y_c) + Y
      K - U  = - y_c*e**ln((APYo)**(term0/y_c)) + term0*ln(APYo)*Ei(term0*ln(APYo)/y_c) + Y
      K - U  = - y_c*e**((term0/y_c)*ln(APYo)) + term0*ln(APYo)*Ei(term0*ln(APYo)/y_c) + Y
      K - U  = - y_c*e**(term0*ln(APYo)/y_c) + term0*ln(APYo)*Ei(term0*ln(APYo)/y_c) + Y

      term1 = term * ln(APYo)

      K - U  = - y_c*e**(term1/y_c) + term1*Ei(term1/y_c) + Y

      term2 = term1/y-c

      K - U  = - y_c*e**(term2) + term1*Ei(term2) + Y
      K - U  = term1*Ei(term2) + Y - y_c*e**(term2)
    */

    uint256 c = L.mul(w)/(1 ether);
    uint256 y_c = Y.add(c);
    int128 term1;
    {
      uint256 S = L.add(c);
      S = S.mul(feeConstant)/(1 ether);
      uint temp = S.mul(r) >> 64;
      require(temp <= uint(MAX));
      int128 term0 = int128(temp).neg();
      term1 = APYo.ln().mul(term0);
    }
    int128 term2 = int128(int256(term1).mul(ABDK_1)/int256(y_c));
    int256 term3 = Ei.eval(term2).mul(int256(term1)) / Ei.INFLATOR;
    int256 term4 = int256(term2.exp()).mul(int256(y_c)) / int256(ABDK_1);

    return term3
      .add(int256(Y))
      .sub(term4);
  }

  /*
    @Description: find the change of reserves in the YTamm when a swap is made

    @param uint Y: amount of pool reserves of Yield Tokens, inflated by 64 bits
    @param uint L: amount of Liquidity tokens, inflated by 64 bits
    @param uint r: amount of time remaining / anchor, inflated by 64 bits
    @param uint w: slippage minimiser variable inflated by (1 ether)
    @param uint feeConstant: raise APY in differential equation to feeConstant
    @param int128 APYo: the apy returned from the oracle inflated by 64 bits
    @param int128 changeYreserve: the change in YT reserves due to the swap transaction

    @return int128: the change in the U reserve due to the swap transaction
  */
  function YT_U_reserve_change(uint256 Y, uint256 L, uint256 r, uint256 w, uint feeConstant, int128 APYo, int128 changeYreserve) external pure returns (int128) {
    require(changeYreserve > -int(Y));
    int256 KminusU = YT_U_PoolConstantMinusU(Y, L, r, w, feeConstant, APYo);
    int256 newKminusU = YT_U_PoolConstantMinusU(uint(int(Y) + changeYreserve), L, r, w, feeConstant, APYo);
    int256 result = KminusU.sub(newKminusU);
    require(result.abs() < MAX);
    return int128(result);
  }

  /*
    @Description: get the price of U in terms of YT based on APY and time remaining

    @paran int128 APY: the APY which shall be used to calculate the price of U in terms of YT
    @param uint secondsRemaining: the amount of seconds until the maturity
    
    @return uint ratio: the price of U in terms of YT
  */
  function YT_U_ratio(int128 APY, uint secondsRemaining) external pure returns (uint ratio) {
    int128 timeRemaining = int128((secondsRemaining << 64) / SecondsPerYear);
    int128 ret = ABDK_1.div(ABDK_1.sub(Pow(APY, -timeRemaining)));
    return uint(ret).mul(1 ether) >> 64;
  }

  /*
    @Description: get the pool constant from the Z**(1-r) + U**(1-r) == K formula

    @param uint U: the amount of U reserves
    @param uint Z: the amount of ZCB reserves
    @param uint r: the amount of time remaining to maturity (in anchor) inflated by 64 bits
  
    @return int128: pool constant
  */
  function ZCB_U_PoolConstant(uint U, uint Z, uint r) private pure returns (int128) {
    /*
      K == U**(1-r) + Z**(1-r)
      K == exp_2( log_2( U**(1-r) ) ) + exp_2( log_2( Z**(1-r) ) )
      K == exp_2( (1-r)*log_2( U ) ) + exp_2( (1-r)*log_2( Z ) )
    */
    int128 exponent = int128(1<<64).sub(int128( r ));
    return exponent.mul( int128( U ).log_2() ).exp_2().add(  exponent.mul( int128( Z ).log_2() ).exp_2()  );
  }

  /*
    @Description: based on the state of a ZCBamm find the change in reserves due to a swap transaction

    @param uint reserve0: the reserves of (ZCB / U) that has a known reserve change due to the swap
    @param uint reserve1: the reserves of (U / ZCB) that has an unknown reserve change due to the swap
    @param uint r: the amount of time to maturity (in anchor) inflated by 64 bits
    @param uint feeConstant: the constant which we raise the APY to in the differential equation to compensate LPs

    @return int128 changeReserve1: the change in amm reserves of (U / ZCB)
  */
  function ZCB_U_reserve_change(uint reserve0, uint reserve1, uint r, uint feeConstant, int128 changeReserve0) public pure returns (int128 changeReserve1) {
    //adjust for fee constant
    r = r.mul(feeConstant) / 1 ether;
    int128 K = ZCB_U_PoolConstant(reserve0, reserve1, r);
    /*
      K == U**(1-r) + Z**(1-r)
      K == (U + uChange)**(1-r) + (Z + zChange)**(1-r)
      (Z + zChange)**(1-r) == K - (U + uChange)**(1-r)
      Z + zChange == (K - (U + uChange)**(1-r))**(1/(1-r))
      zChange == (K - (U + uChange)**(1-r))**(1/(1-r)) - Z


      changeReserve1 == (K - (reserve0 + changeReserve0)**(1-r))**(1/(1-r)) - reserve1

      changeReserve1 == (K - exp_2(log_2((reserve0 + changeReserve0)**(1-r)))   )**(1/(1-r)) - reserve1

      changeReserve1 == (K - exp_2((1-r)*log_2(reserve0 + changeReserve0))   )**(1/(1-r)) - reserve1
    */
    int128 exponent = ABDK_1.sub(int128( r ));

    //base == K - exp_2((1-r)*log_2(reserve0 + changeReserve0))
    int128 base = K.sub( (exponent.mul( (int128(reserve0) + changeReserve0).log_2())).exp_2() );

    /*
      changeReserve1 == base**(1/exponent) - reserve1
      changeReserve1 == exp_2(log_2(base**(1/exponent))) - reserve1
      changeReserve1 == exp_2((1/exponent)*log_2(base)) - reserve1
    */
    changeReserve1 = (ABDK_1.div(exponent)).mul( base.log_2() ).exp_2().sub(int128(reserve1));
  }

  /*
    @Description: get info about the affect on reserves and the amount of fees to be paid to the treasury
      when a user makes a swap transaction in the ZCBamm

    @param uint reserve0: the reserve of the asset for which the user is swapping a specific amount
    @param uint reserve1: the reserve of the asset we need to find the change in resulting
      change in reserve of after the swap
    @param uint r: seconds remaining ABDK format divided by anchor
    @param int128: the effect on reserve0 of the user's swap transaction
    @param address AmmInfoOracleAddress: the address of the contract which tells us how much of the
      total fee to send to the treasury
    @param flipFee: when we get the feeConstant from AmmInfoOracle if this is true assign it to 1/itself
      This should be true when the swap is selling U for ZCB and false when selling ZCB for U

    @return uint change: the change in the reserve1 due to the swap transaction
    @return uint treasuryFee: the amount which shall be sent to the treasury
    @return address sendTo: the address that the treasury fee shall be sent to
  */
  function ZCB_U_ReserveAndFeeChange(
    uint reserve0,
    uint reserve1,
    uint r,
    int128 changeReserve0,
    address AmmInfoOracleAddress,
    address capitalHandlerAddress,
    bool flipFee
  ) public view returns (uint change, uint treasuryFee, address sendTo) {

    uint nonFeeAdjustedChange = uint(int(ZCB_U_reserve_change(
      reserve0,
      reserve1,
      r,
      (1 ether),
      changeReserve0
    )).abs());

    uint feeConstant = AmmInfoOracle(AmmInfoOracleAddress).getZCBammFeeConstant(capitalHandlerAddress);
    if (flipFee) {
      feeConstant = uint((1 ether)**2).div(feeConstant);
    }
    change = uint(int(ZCB_U_reserve_change(
      reserve0,
      reserve1,
      r,
      feeConstant,
      changeReserve0
    )).abs());

    (uint larger, uint smaller) = nonFeeAdjustedChange > change ? (nonFeeAdjustedChange, change) : (change, nonFeeAdjustedChange) ;

    (treasuryFee, sendTo) = AmmInfoOracle(AmmInfoOracleAddress).treasuryFee(larger, smaller);

  }

  int128 private constant MAX_ANNUAL_ERROR = ABDK_1 / 100000;
  uint private constant MaxAnchor = 1000 * SecondsPerYear;

  /*
    @Description: get the new effective total supply after recalibration of the ZCBamm

    @param uint prevRatio: the previous ratio of (ZCBreserves+EffectiveTotalSupply)/Ureserves
    @param int128 prevAnchorABDK: the previous anchor inflated by 64 bits
    @param int128 secondsRemaining: the amount of seconds until maturity inflated by 64 bits
    @param uint lowerBoundAnchor: the proposed lower bound of the new anchor
    @param uint upperBoundAnchor: the proposed upper bound of the new anchor
    @param uint ZCBreserves: the amount of ZCB reserves in the ZCBamm
    @param uint Ureserves: the amount of U reserves in the ZCBamm
  */
  function ZCB_U_recalibration(
    uint prevRatio,
    int128 prevAnchorABDK,
    int128 secondsRemaining,
    uint lowerBoundAnchor,
    uint upperBoundAnchor,
    uint ZCBreserves,
    uint Ureserves
  ) external pure returns (uint) {
    
    require(upperBoundAnchor > lowerBoundAnchor && upperBoundAnchor < lowerBoundAnchor + 30 seconds && lowerBoundAnchor > uint(secondsRemaining) >> 64);
    require(upperBoundAnchor < MaxAnchor);
    require(int(ZCBreserves) <= MAX && int(ZCBreserves) > 0);
    require(int(Ureserves) <= MAX && int(Ureserves) > 0);
    int128 prevYield;
    {
      uint base = (prevRatio << 64) / (1 ether);
      require(int(base) <= MAX && int(base) > 0);
      prevYield = Pow(int128(base), secondsRemaining.div(prevAnchorABDK));
    }

    /*
      For the solution to be valid the following must be approximately true

      0 ~= 2 * L**(1-t) - (Z + L)**(1-t) - U**(1-t)
      Where
      prevYield == ((Z+L)/U)**anchor
      anchor == secondsRemaining / t
    */

    /*
      For any given value of anchor we can find the expected value of L with some algebra
      
      prevYield == ( (Z+L)/U )**(secondsRemaining/anchor)
      prevYield**(anchor/secondsRemaining) == (Z+L)/U
      U * prevYield**(anchor/secondsRemaining) == Z+L
      L == U * prevYield**(anchor/secondsRemaining) - Z

      Next we need to check if this fits with our other equation

      An increase in anchor results in a decrease in L thus we expect
      LowerBoundL > UpperBoundL because LowerBoundL is derived from a
      higher anchor
    */
    int128 LowerBoundL;
    int128 UpperBoundL;
    int128 lowAnchorG;
    int128 highAnchorG;
    {
      int128 ABDKAnchor = int128(lowerBoundAnchor << 64);
      int128 exponent = ABDKAnchor.div(secondsRemaining);
      LowerBoundL = Pow(prevYield, exponent).mul(int128(Ureserves)).sub(int128(ZCBreserves));
      int128 t = secondsRemaining.div(ABDKAnchor);
      lowAnchorG = approxG(LowerBoundL, int128(ZCBreserves), int128(Ureserves), t);

      ABDKAnchor = int128(upperBoundAnchor << 64);
      exponent = ABDKAnchor.div(secondsRemaining);
      UpperBoundL = Pow(prevYield, exponent).mul(int128(Ureserves)).sub(int128(ZCBreserves));
      t = secondsRemaining.div(ABDKAnchor);
      highAnchorG = approxG(UpperBoundL, int128(ZCBreserves), int128(Ureserves), t);
    }
    require(lowAnchorG <= 0 && 0 <= highAnchorG);

    int128 ret = LowerBoundL.avg(UpperBoundL);
    require(ret > 0);
    return uint(ret);
  }

  /*
    @Description: approximate value of
      2 * L**(1-t) - (Z + L)**(1-t) - U**(1-t)
      when we recalibrate the ZCBamm we try to scale anchor such that the expression above has
      a value very near 0

    @param int128 L: the effective total supply in the ZCBamm
    @param int128 Z: the amount of ZCB reserves in the ZCBamm
    @param int128 u: the amount of U reserves in the ZCBamm
    @param int128 t: the time to maturity (in anchor) inflated by 64 bits

    @return int128: the approximate value of G
  */
  function approxG(int128 L, int128 Z, int128 U, int128 t) internal pure returns (int128) {
    int128 exp = ABDK_1.sub(t);
    int128 term0 = (2 * ABDK_1).mul(Pow(L, exp));
    int128 term1 = Pow(L.add(Z), exp);
    int128 term2 = Pow(U, exp);
    return term0.sub(term1).sub(term2);
  }

  /*
    @Description: rase one ABDK number to the power of another
      base**exponent

    @param int128 base: the base of the pow operation
    @param int128 exponent: the exponent of the pow operation
  */
  function Pow(int128 base, int128 exponent) internal pure returns (int128) {
    /*
      base**exponent ==
      2**(log_2(base**exponent))
      2**(exponent * log_2(base))
    */
    return base.log_2().mul(exponent).exp_2();
  }

}

