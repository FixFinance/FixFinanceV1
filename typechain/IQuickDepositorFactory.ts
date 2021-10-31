/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer } from "ethers";
import { Provider } from "@ethersproject/providers";

import type { IQuickDepositor } from "./IQuickDepositor";

export class IQuickDepositorFactory {
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): IQuickDepositor {
    return new Contract(address, _abi, signerOrProvider) as IQuickDepositor;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_fixCapitalPoolAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountUnderlying",
        type: "uint256",
      },
    ],
    name: "FastDepositUnderlying",
    outputs: [
      {
        internalType: "uint256",
        name: "wrappedDeposit",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "dynamicDeposit",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_fixCapitalPoolAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountUnderlying",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_maxMaturityConversionRate",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_maxCumulativeMaturityConversionRate",
        type: "uint256",
      },
      {
        internalType: "uint16",
        name: "_maxIterations",
        type: "uint16",
      },
    ],
    name: "UnderlyingToYT",
    outputs: [
      {
        internalType: "uint256",
        name: "yield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "bond",
        type: "int256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_fixCapitalPoolAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountUnderlying",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minMaturityConversionRate",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minCumulativeMaturityConversionRate",
        type: "uint256",
      },
      {
        internalType: "uint16",
        name: "_maxIterations",
        type: "uint16",
      },
    ],
    name: "UnderlyingToZCB",
    outputs: [
      {
        internalType: "uint256",
        name: "yield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "bond",
        type: "int256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
];
