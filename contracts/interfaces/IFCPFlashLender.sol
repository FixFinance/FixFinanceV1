pragma solidity >=0.6.0;
import "./IFCPFlashBorrower.sol";

interface IFCPFlashLender {
    function maxFlashLoan() external view returns (uint256, int256);

    function flashFee(
        uint256 amountYield,
        int256 amountBond
    ) external view returns (uint256, int256);

    function flashLoan(
        IFCPFlashBorrower receiver,
        uint256 amountYield,
        int256 amountBond,
        bytes calldata data
    ) external returns (bool);
}