/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer } from "ethers";
import { Provider } from "@ethersproject/providers";

import type { IVaultHealth } from "./IVaultHealth";

export class IVaultHealthFactory {
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): IVaultHealth {
    return new Contract(address, _abi, signerOrProvider) as IVaultHealth;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
    ],
    name: "LowerCollateralizationRatio",
    outputs: [
      {
        internalType: "uint120",
        name: "",
        type: "uint120",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
    ],
    name: "LowerRateThreshold",
    outputs: [
      {
        internalType: "uint120",
        name: "",
        type: "uint120",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
    ],
    name: "UpperCollateralizationRatio",
    outputs: [
      {
        internalType: "uint120",
        name: "",
        type: "uint120",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
    ],
    name: "UpperRateThreshold",
    outputs: [
      {
        internalType: "uint120",
        name: "",
        type: "uint120",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountYield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_amountBond",
        type: "int256",
      },
    ],
    name: "YTvaultAmountBorrowedAtLowerLimit",
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
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountYield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_amountBond",
        type: "int256",
      },
    ],
    name: "YTvaultAmountBorrowedAtUpperLimit",
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
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountYield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_amountBond",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
    ],
    name: "YTvaultSatisfiesLowerLimit",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountYield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_amountBond",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
    ],
    name: "YTvaultSatisfiesUpperLimit",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "bool",
        name: "_reqSameBase",
        type: "bool",
      },
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountYield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_amountBond",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_pctPriceChange",
        type: "uint256",
      },
      {
        internalType: "int128",
        name: "_suppliedRateChange",
        type: "int128",
      },
      {
        internalType: "int128",
        name: "_borrowRateChange",
        type: "int128",
      },
    ],
    name: "YTvaultWithstandsChange",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSupplied",
        type: "uint256",
      },
    ],
    name: "amountBorrowedAtLowerLimit",
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
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSupplied",
        type: "uint256",
      },
    ],
    name: "amountBorrowedAtUpperLimit",
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
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
    ],
    name: "amountSuppliedAtLowerLimit",
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
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
    ],
    name: "amountSuppliedAtUpperLimit",
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
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
    ],
    name: "lowerMinimumRateAdjustment",
    outputs: [
      {
        internalType: "uint120",
        name: "",
        type: "uint120",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_underlyingAssetAddress",
        type: "address",
      },
    ],
    name: "maximumShortInterest",
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
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSupplied",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
    ],
    name: "satisfiesLowerLimit",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSupplied",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
    ],
    name: "satisfiesUpperLimit",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
      {
        internalType: "uint120",
        name: "_upper",
        type: "uint120",
      },
      {
        internalType: "uint120",
        name: "_lower",
        type: "uint120",
      },
    ],
    name: "setCollateralizationRatios",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_underlyingAssetAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_maximumShortInterest",
        type: "uint256",
      },
    ],
    name: "setMaximumShortInterest",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
      {
        internalType: "uint120",
        name: "_upper",
        type: "uint120",
      },
      {
        internalType: "uint120",
        name: "_lower",
        type: "uint120",
      },
    ],
    name: "setMinimumRateAdjustments",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_organizerAddress",
        type: "address",
      },
    ],
    name: "setOrganizerAddress",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
      {
        internalType: "uint120",
        name: "_upper",
        type: "uint120",
      },
      {
        internalType: "uint120",
        name: "_lower",
        type: "uint120",
      },
    ],
    name: "setRateThresholds",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_wrapperAddress",
        type: "address",
      },
    ],
    name: "upperMinimumRateAdjustment",
    outputs: [
      {
        internalType: "uint120",
        name: "",
        type: "uint120",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "bool",
        name: "_reqSameBase",
        type: "bool",
      },
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSupplied",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_pctPriceChange",
        type: "uint256",
      },
      {
        internalType: "int128",
        name: "_suppliedRateChange",
        type: "int128",
      },
      {
        internalType: "int128",
        name: "_borrowRateChange",
        type: "int128",
      },
    ],
    name: "vaultWithstandsChange",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];
