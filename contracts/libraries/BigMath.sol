pragma solidity >=0.5.0;

import "./ABDKMath64x64.sol";
import "./SignedSafeMath.sol";

contract BigMath {
  using ABDKMath64x64 for int128;
  using SignedSafeMath for int256;

  /*
    we keep error bound here such that we won't exceed 35 iterations in the power series and 
    epsilon ~ 0.000000000108420217248550443400745280086994171142578125 * 2**64

  */
  int128 private constant epsilon = 2000000000;

  int256[] private addition_series_data_array = [
      3.532638989211429e21, 8.123575301925086e21,
      1.914547520851727e22, 4.597351009781708e22,
      1.1199767955048595e23, 2.7595467055933305e23,
      6.861762397213119e23, 1.7190984485914473e24,
      4.334170479517456e24, 1.0986161322763805e25,
      2.797703108389213e25, 7.1534708728861e25,
      1.835618393612818e26, 4.7252538897488815e26,
      1.2198312830141285e27, 3.1570619510569525e27,
      8.189734001592899e27, 2.128967126497089e28,
      5.5450007070812015e28, 1.4467672526275159e29,
      3.780936367779663e29, 9.895777734762272e29,
      2.5935973811247214e30, 6.806354363991228e30,
      1.788329890071965e31, 4.704000104541168e31,
      1.2386324902270515e32, 3.264711636491927e32,
      8.612886291792749e32, 2.2742106798878982e33,
      6.00992892534685e33, 1.5894430796449978e34,
      4.2066807430832585e34, 1.1141313708614602e35,
      2.9527056022310355e35, 7.830266715673091e35,
      2.077745864657038e36, 5.516396839118708e36,
      1.4653938605367742e37, 3.894739269536102e37,
      1.0356610276733984e38, 2.755261428205564e38,
      7.333397495026503e38, 1.9527053469860518e39
  ];

  int128 constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;


  function isOutOfBounds(int256 x) internal pure returns (bool) {
    /*
     * Minimum value signed 64.64-bit fixed point number may have. 
     */
    int128 MIN_64x64 = -0x80000000000000000000000000000000;

    /*
     * Maximum value signed 64.64-bit fixed point number may have. 
     */
    int128 MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    return x < MIN_64x64 || x > MAX_64x64;
  }


  function Power_Series_Ei(int128 x) public pure returns (int256) { 
    int128 _epsilon = epsilon;  //gas savings
    int128 xn = -x;
    int128 Sn = -x;
    int128 Sm1 = 0;
    int128 hsum = 1<<64; //1.0
    int128 y = 1<<64; //1.0
    // we don't inflate factorial because we need it to fit in the 128 bit limit
    int128 factorial = 1;
    int128 store;

    require(x != 0);

    uint8 i = 0;
    while ( (Sn - Sm1).abs() > _epsilon.mul(Sm1.abs()) && i < 36) {
      y += 1<<64;
      int256 result = int256(xn) * (-x) >>64;
      if (isOutOfBounds(result)) {
        y -= 1<<64;
        store = xn / factorial;
        //reset xn and factorial
        xn = 1<<64;
        factorial = 1;
        break;
      }
      xn = int128(result);
      factorial *= y>>64;
      hsum += int128(1<<64).div(y);
      result = int256(hsum) * xn >> 64;
      if (isOutOfBounds(result)) {
        hsum -= int128(1<<64).div(y);
        factorial /= y>>64;
        xn = xn.div(-x);
        y -= 1<<64;
        store = xn / factorial;
        //reset xn and factorial
        xn = 1<<64;
        factorial = 1;
        break;
      }
      Sm1 = Sn;
      Sn += int128(result) / factorial;
      i++;
    }
    if (store == 0) {
      //copy x to top of the stack
      int128 _x = x;
      int128 g = 1.0647749645774669733e19; // 0.5772156649015328606065121
      return (g.add(_x.abs().ln()).sub(_x.exp().mul(Sn)));
    }
    while ( (Sn - Sm1).abs() > _epsilon.mul(Sm1.abs()) && i < 36) {
      y += 1<<64;
      xn = xn.mul(-x);
      factorial *= y>>64;
      hsum += int128(1<<64).div(y);
      Sm1 = Sn;
      Sn += hsum.mul(xn).mul(store) / factorial;
      i++;
    }
    //copy x to top of the stack
    int128 _x = x;
    int128 g = 1.0647749645774669733e19; // 0.5772156649015328606065121
    return int256(g.add(_x.abs().ln()).sub(_x.exp().mul(Sn)));
  }

  function arg_add_series_return(int128 k, int128 Sn, int128 xx) internal view returns (int256) {
      /*
        we divide the exponent by 2 and then square the result is because
        the math library we use is bound to 128 bits
        x = 50 is the upper bound of the domain of this approximation function
        if we try to find (50).exp() we will get an overflow error from our math library
        thus we find (50/2).exp and cast to int256 and find the square
      */
      int256 exp = int256((xx/2).exp())**2 >> 64;
      int256 a = exp * Sn;
      require(a/exp == Sn, "multiplication overflow");
      a >>= 64;
      int256 b = addition_series_data_array[uint8(k>>64)-7];
      int256 c = a + b;
      require((b >= 0 && c >= a) || (b < 0 && c < a), "addition overflow");
      return c;
  }

  function Argument_Addition_Series_Ei(int128 x) public view returns (int256) {
     int128 k = ((x + (1<<63)) >> 64) << 64;
     int128 j = 0;
     int128 xx = k;
     int128 dx = x - xx;
     int128 xxj = xx;
     int128 edx = dx.exp();
     int128 Sm = 1 << 64;
     int128 Sn = (edx - (1<<64)).div(xxj);
     int128 term = MAX;
     int128 factorial = 1;
     int128 dxj = 1<<64;
     int128 _epsilon = epsilon; //gas savings
     while (term.abs() > _epsilon.mul(Sn.abs()) ) {
        j++;
        factorial *= j;
        xxj = xxj.mul(xx);
        dxj = dxj.mul(-dx);
        Sm = Sm.add(dxj / factorial);
        term = ( (factorial<<64).mul(edx.mul(Sm) - (1<<64) ) ).div(xxj);
        Sn = Sn.add(term);
     }

     return arg_add_series_return(k, Sn, xx);
  }


  function Continued_Fraction_Ei(int128 x) public pure returns (int256) {
      int256 Am1 = 1 << 64;
      int256 A0 = 0;
      int256 Bm1 = 0;
      int256 B0 = 1 << 64;
      int256 a = int256((x/2).exp())**2 >> 64;
      int256 b = (-x).add(1<<64);
      int256 Ap1 = (b.mul(A0) >> 64).add(a.mul(Am1) >> 64);
      int256 Bp1 = (b.mul(B0) >> 64).add(a.mul(Bm1) >> 64);
      int256 j = 1 << 64;
      int _epsilon = epsilon; //gas savings

     while ( ( (Ap1.mul(B0) >> 64).sub(A0.mul(Bp1) >> 64) ).abs() > (A0.mul(Bp1) >> 64).abs().mul(_epsilon) >> 64 ) {
        if ( Bp1.abs() > 1 << 64) {
           Am1 = A0.mul(1<<64).div(Bp1);
           A0 = Ap1.mul(1<<64).div(Bp1);
           Bm1 = B0.mul(1<<64).div(Bp1);
           B0 = 1 << 64;
        } else {
           Am1 = A0;
           A0 = Ap1;
           Bm1 = B0;
           B0 = Bp1;
        }
        a = j.mul(-j) >> 64;
        b += 2 << 64;
        Ap1 = (b.mul(A0) >> 64).add(a.mul(Am1) >> 64);
        Bp1 = (b.mul(B0) >> 64).add(a.mul(Bm1) >> 64);
        j += 1<<64;
     }

     return (-Ap1).mul(1<<64).div(Bp1);
  }


  function Ei(int128 x) public view returns (int256) {
    require(x >= int(-19 * 2**64) && x <= int(87 * 2**64), "not in range");
    if (x < int(-5 * 2**64) || x > int(50 * 2**64))
      return Continued_Fraction_Ei(x);
    else if (x < int(uint(68 * 2**64) / 10))
      return Power_Series_Ei(x);
    else
      return Argument_Addition_Series_Ei(x);
  }


  /*
    @Description: find the pool constant given current pool reserves

    @param U: amount of pool reserves of Underlying asset, inflated by 64 bits
    @param Y: amount of pool reserves of Yield Tokens, inflated by 64 bits
    @param L: amount of Liquidity tokens, inflated by 64 bits
    @param r: amount of time remaining / anchor, inflated by 64 bits
    @param APYo: the apy returned from the oracle inflated by 64 bits
  */
  function PoolConstant(int256 U, int256 Y, int256 L, int256 r, int128 APYo) public view returns (int256) {
    /*
      K = U - (L* r * ln(APYo) * Ei(-L*r*ln(APYo)/Y) + Y*(APYo**(-L*r/Y) -1))
      K = U + (-L* r * ln(APYo) * Ei(-L*r*ln(APYo)/Y) - Y*(APYo**(-L*r/Y) -1))
    */
    int256 lnAPYo = int256(APYo.ln());
    //we know that L * r is a safe operation and does not require safemath
    int256 term = - ((L * r) >> 64);
    //note that termMulLog is inflated by 128 bits not 64 bits
    int256 termMulLog = term.mul(lnAPYo);
    int256 term3 = termMulLog/Y;
    require(term3 < MAX);
    int256 ei = Ei(int128(term3));

    /*
      APYo**(-L*r/Y) - 1 ==
      APYo**(term/Y) - 1 ==
      e**((term/y) * ln(APYo)) - 1 ==
      e**(termMulLog/Y) - 1 ==
      e**(term3) - 1
    */
    int256 APYoexp = ( int128(term3) ).exp().sub(1<<64);

    return U.add( ((termMulLog >> 64).mul(ei) >> 64).sub(Y.mul(APYoexp) >> 64) );
  }

  function PoolConstantMinusU(int256 Y, int256 L, int256 r, int128 APYo) public view returns (int256) {
    /*
      K = U - (L* r * ln(APYo) * Ei(-L*r*ln(APYo)/Y) + Y*(APYo**(-L*r/Y) -1))
      K = U + (-L* r * ln(APYo) * Ei(-L*r*ln(APYo)/Y) - Y*(APYo**(-L*r/Y) -1))
      K - U = (-L* r * ln(APYo) * Ei(-L*r*ln(APYo)/Y) - Y*(APYo**(-L*r/Y) -1))
    */
    int256 lnAPYo = int256(APYo.ln());
    //we know that L * r is a safe operation and does not require safemath
    int256 term = - ((L * r) >> 64);
    //note that termMulLog is inflated by 128 bits not 64 bits
    int256 termMulLog = term.mul(lnAPYo);
    int256 term3 = termMulLog/Y;
    require(term3 < MAX);
    int256 ei = Ei(int128(term3));

    /*
      APYo**(-L*r/Y) - 1 ==
      APYo**(term/Y) - 1 ==
      e**((term/y) * ln(APYo)) - 1 ==
      e**(termMulLog/Y) - 1 ==
      e**(term3) - 1
    */
    int256 APYoexp = ( int128(term3) ).exp().sub(1<<64);

    return ((termMulLog >> 64).mul(ei) >> 64).sub(Y.mul(APYoexp) >> 64);
  }

}

