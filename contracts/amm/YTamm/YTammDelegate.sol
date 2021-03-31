pragma solidity >=0.6.0;

import "../../helpers/DividendEnabledData.sol";
import "../../helpers/IYTammData.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/BigMath.sol";
import "../../interfaces/ICapitalHandler.sol";
import "../../interfaces/IYieldToken.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/IZCBamm.sol";
import "../../AmmInfoOracle.sol";

contract YTammDelegate is DividendEnabledData, IYTammData {

}