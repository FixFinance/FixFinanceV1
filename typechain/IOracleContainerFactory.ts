/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer } from "ethers";
import { Provider } from "@ethersproject/providers";

import type { IOracleContainer } from "./IOracleContainer";

export class IOracleContainerFactory {
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): IOracleContainer {
    return new Contract(address, _abi, signerOrProvider) as IOracleContainer;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_aTokenAddress",
        type: "address",
      },
    ],
    name: "AssetPhrase",
    outputs: [
      {
        internalType: "string",
        name: "phrase",
        type: "string",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "string",
        name: "_phrase",
        type: "string",
      },
    ],
    name: "BaseAggregatorAddress",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_assetAddress",
        type: "address",
      },
    ],
    name: "getAssetPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "string",
        name: "_phrase",
        type: "string",
      },
    ],
    name: "phraseToLatestPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "spot",
        type: "uint256",
      },
      {
        internalType: "uint8",
        name: "decimals",
        type: "uint8",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];
