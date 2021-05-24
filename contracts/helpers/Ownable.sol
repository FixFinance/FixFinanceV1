// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

abstract contract Ownable {
    address public owner;

    constructor () public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "only owner");
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public virtual {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }
}