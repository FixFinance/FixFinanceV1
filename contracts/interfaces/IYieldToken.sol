pragma solidity >=0.6.0;
import "./IERC20.sol";

interface IYieldToken is IERC20 {
    function balanceOf_2(address _owner, bool _roundUp) external view returns (uint);
    function transfer_2(address _to, uint256 _value, bool _roundUp) external;
    function transferFrom_2(address _from, address _to, uint256 _value, bool _roundUp) external;

}