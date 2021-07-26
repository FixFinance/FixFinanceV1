// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IInfoOracle.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../helpers/Ownable.sol";
import "../helpers/nonReentrant.sol";
import "./ZCB_YT/ZCB_YT_Deployer.sol";
import "./FCPData.sol";

contract FCPDelegate1 is FCPData {

}