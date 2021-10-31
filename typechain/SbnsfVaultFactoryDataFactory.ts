/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import { Contract, ContractFactory, Overrides } from "@ethersproject/contracts";

import type { SbnsfVaultFactoryData } from "./SbnsfVaultFactoryData";

export class SbnsfVaultFactoryDataFactory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(overrides?: Overrides): Promise<SbnsfVaultFactoryData> {
    return super.deploy(overrides || {}) as Promise<SbnsfVaultFactoryData>;
  }
  getDeployTransaction(overrides?: Overrides): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  attach(address: string): SbnsfVaultFactoryData {
    return super.attach(address) as SbnsfVaultFactoryData;
  }
  connect(signer: Signer): SbnsfVaultFactoryDataFactory {
    return super.connect(signer) as SbnsfVaultFactoryDataFactory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): SbnsfVaultFactoryData {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as SbnsfVaultFactoryData;
  }
}

const _abi = [
  {
    inputs: [],
    name: "owner",
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
        name: "newOwner",
        type: "address",
      },
    ],
    name: "transferOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b50336000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff16021790555061025e806100606000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c80638da5cb5b1461003b578063f2fde38b14610085575b600080fd5b6100436100c9565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6100c76004803603602081101561009b57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506100ee565b005b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16146101b0576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252600a8152602001807f6f6e6c79206f776e65720000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff161461022557806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505b5056fea26469706673582212206b28205490f86543e641506b8ba16b74071fb4ccf59516eb0f80874d9b77cf1364736f6c63430006080033";
