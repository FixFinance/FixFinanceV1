// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./ABDKMath64x64.sol";
import "./SignedSafeMath.sol";
import "./SafeMath.sol";

import "../InfoOracle.sol";

library BigMath {
  using ABDKMath64x64 for int128;
  using SignedSafeMath for int256;
  using SafeMath for uint256;

  uint public constant SecondsPerYear = 31556926;

  /*
    @Description: rase one ABDK number to the power of another
      base**exponent

    @param int128 base: the base of the pow operation
    @param int128 exponent: the exponent of the pow operation
  */
  function Pow(int128 base, int128 exponent) internal pure returns (int128) {
    /*
      base**exponent ==
      2**(log_2(base**exponent)) ==
      2**(exponent * log_2(base))
    */
    return base.log_2().mul(exponent).exp_2();
  }

}

