// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

interface IFCPFlashBorrower {
    function onFlashLoan(
        address initiator,
        uint256 amountYield,
        int256 amountBond,
        uint256 feeYield,
        int256 feeBond,
        bytes calldata data
    ) external returns (bytes32);
}