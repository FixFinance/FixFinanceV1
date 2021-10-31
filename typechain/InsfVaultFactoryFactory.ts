/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer } from "ethers";
import { Provider } from "@ethersproject/providers";

import type { InsfVaultFactory } from "./InsfVaultFactory";

export class InsfVaultFactoryFactory {
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): InsfVaultFactory {
    return new Contract(address, _abi, signerOrProvider) as InsfVaultFactory;
  }
}

const _abi = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "AdjustVault",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "AdjustYTVault",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "vaultOwner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "vaultIndex",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "liquidationIndex",
        type: "uint256",
      },
    ],
    name: "AuctionLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "YTvaultOwner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "YTvaultIndex",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "YTliquidationIndex",
        type: "uint256",
      },
    ],
    name: "AuctionYTLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "liquidationIndex",
        type: "uint256",
      },
    ],
    name: "BidOnLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "YTliquidationIndex",
        type: "uint256",
      },
    ],
    name: "BidOnYTLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "liquidationIndex",
        type: "uint256",
      },
    ],
    name: "ClaimLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "asset",
        type: "address",
      },
    ],
    name: "ClaimRebate",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "YTliquidationIndex",
        type: "uint256",
      },
    ],
    name: "ClaimYTLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "FCPaddress",
        type: "address",
      },
    ],
    name: "ClaimYTRebate",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "CloseVault",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "CloseYTVault",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "InstantLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "InstantYTLiquidation",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "OpenVault",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "index",
        type: "uint256",
      },
    ],
    name: "OpenYTVault",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "prevOwner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "prevIndex",
        type: "uint256",
      },
      {
        indexed: true,
        internalType: "address",
        name: "newOwner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "bool",
        name: "isYTVault",
        type: "bool",
      },
    ],
    name: "TransferVault",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
    ],
    name: "Liquidations",
    outputs: [
      {
        internalType: "address",
        name: "vaultOwner",
        type: "address",
      },
      {
        internalType: "address",
        name: "assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amountBorrowed",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "bidder",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "bidAmount",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "bidTimestamp",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "VaultHealthAddress",
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
        name: "_owner",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCP",
        type: "address",
      },
    ],
    name: "YTLiquidationRebates",
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
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
    ],
    name: "YTLiquidations",
    outputs: [
      {
        internalType: "address",
        name: "vaultOwner",
        type: "address",
      },
      {
        internalType: "address",
        name: "FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "FCPborrowed",
        type: "address",
      },
      {
        internalType: "int256",
        name: "bondRatio",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "amountBorrowed",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "bidder",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "bidAmount",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "bidTimestamp",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "YTLiquidationsLength",
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
        name: "_FCPaddress",
        type: "address",
      },
    ],
    name: "YTrevenue",
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
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
    ],
    name: "YTvaults",
    outputs: [
      {
        internalType: "address",
        name: "FCPsupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "FCPborrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "yieldSupplied",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "bondSupplied",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "amountBorrowed",
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
        name: "_owner",
        type: "address",
      },
    ],
    name: "YTvaultsLength",
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
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
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
        internalType: "int128[3]",
        name: "_multipliers",
        type: "int128[3]",
      },
      {
        internalType: "bytes",
        name: "_data",
        type: "bytes",
      },
      {
        internalType: "address",
        name: "_receiverAddr",
        type: "address",
      },
    ],
    name: "adjustVault",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
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
        name: "_yieldSupplied",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_bondSupplied",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
      {
        internalType: "int128[3]",
        name: "_multipliers",
        type: "int128[3]",
      },
      {
        internalType: "bytes",
        name: "_data",
        type: "bytes",
      },
      {
        internalType: "address",
        name: "_receiverAddr",
        type: "address",
      },
    ],
    name: "adjustYTVault",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
    ],
    name: "allVaults",
    outputs: [
      {
        components: [
          {
            internalType: "address",
            name: "assetSupplied",
            type: "address",
          },
          {
            internalType: "address",
            name: "assetBorrowed",
            type: "address",
          },
          {
            internalType: "uint256",
            name: "amountSupplied",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "amountBorrowed",
            type: "uint256",
          },
        ],
        internalType: "struct NSFVaultFactoryData.Vault[]",
        name: "_vaults",
        type: "tuple[]",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_bid",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_amtIn",
        type: "uint256",
      },
    ],
    name: "auctionLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_bidYield",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_minBondRatio",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_amtIn",
        type: "uint256",
      },
    ],
    name: "auctionYTLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_bid",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_amtIn",
        type: "uint256",
      },
    ],
    name: "bidOnLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_bidYield",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_amtIn",
        type: "uint256",
      },
    ],
    name: "bidOnYTLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "claimLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_asset",
        type: "address",
      },
    ],
    name: "claimRebate",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "claimYTLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_FCPaddress",
        type: "address",
      },
    ],
    name: "claimYTRebate",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "closeVault",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "closeYTVault",
    outputs: [],
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
    ],
    name: "fixCapitalPoolToWrapper",
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
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_maxIn",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minOut",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "instantLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_maxIn",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minOut",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_minBondRatio",
        type: "int256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "instantYTLiquidation",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "address",
        name: "_asset",
        type: "address",
      },
    ],
    name: "liquidationRebates",
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
    inputs: [],
    name: "liquidationsLength",
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
        name: "_addr",
        type: "address",
      },
      {
        internalType: "int256",
        name: "_num",
        type: "int256",
      },
      {
        internalType: "enum NSFVaultFactoryData.MANAGE_METHOD",
        name: "_mm",
        type: "uint8",
      },
    ],
    name: "manage",
    outputs: [],
    stateMutability: "nonpayable",
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
      {
        internalType: "uint256",
        name: "_priceMultiplier",
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
    name: "openVault",
    outputs: [],
    stateMutability: "nonpayable",
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
        name: "_yieldSupplied",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_bondSupplied",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_amountBorrowed",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_priceMultiplier",
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
    name: "openYTVault",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_in",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minOut",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "partialLiquidationSpecificIn",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_assetBorrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_assetSupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_out",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_maxIn",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "partialLiquidationSpecificOut",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_in",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minOut",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_minBondRatio",
        type: "int256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "partialYTLiquidationSpecificIn",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_FCPborrowed",
        type: "address",
      },
      {
        internalType: "address",
        name: "_FCPsupplied",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_out",
        type: "uint256",
      },
      {
        internalType: "int256",
        name: "_minBondRatio",
        type: "int256",
      },
      {
        internalType: "uint256",
        name: "_maxIn",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
    ],
    name: "partialYTLiquidationSpecificOut",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_asset",
        type: "address",
      },
    ],
    name: "revenue",
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
        name: "_wrapper",
        type: "address",
      },
    ],
    name: "shortInterestAllDurations",
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
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
      {
        internalType: "bool",
        name: "_isYTVault",
        type: "bool",
      },
    ],
    name: "transferVault",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_owner",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_index",
        type: "uint256",
      },
    ],
    name: "vaults",
    outputs: [
      {
        internalType: "address",
        name: "assetSupplied",
        type: "address",
      },
      {
        internalType: "address",
        name: "assetBorrowed",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amountSupplied",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "amountBorrowed",
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
        name: "_owner",
        type: "address",
      },
    ],
    name: "vaultsLength",
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
    name: "wrapperToUnderlyingAsset",
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
];
