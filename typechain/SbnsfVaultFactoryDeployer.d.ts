/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import {
  ethers,
  EventFilter,
  Signer,
  BigNumber,
  BigNumberish,
  PopulatedTransaction,
} from "ethers";
import {
  Contract,
  ContractTransaction,
  Overrides,
  CallOverrides,
} from "@ethersproject/contracts";
import { BytesLike } from "@ethersproject/bytes";
import { Listener, Provider } from "@ethersproject/providers";
import { FunctionFragment, EventFragment, Result } from "@ethersproject/abi";

interface SbnsfVaultFactoryDeployerInterface extends ethers.utils.Interface {
  functions: {
    "deploy(address)": FunctionFragment;
  };

  encodeFunctionData(functionFragment: "deploy", values: [string]): string;

  decodeFunctionResult(functionFragment: "deploy", data: BytesLike): Result;

  events: {
    "Deploy(address)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "Deploy"): EventFragment;
}

export class SbnsfVaultFactoryDeployer extends Contract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  on(event: EventFilter | string, listener: Listener): this;
  once(event: EventFilter | string, listener: Listener): this;
  addListener(eventName: EventFilter | string, listener: Listener): this;
  removeAllListeners(eventName: EventFilter | string): this;
  removeListener(eventName: any, listener: Listener): this;

  interface: SbnsfVaultFactoryDeployerInterface;

  functions: {
    deploy(
      _vaultHealthAddress: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "deploy(address)"(
      _vaultHealthAddress: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;
  };

  deploy(
    _vaultHealthAddress: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "deploy(address)"(
    _vaultHealthAddress: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  callStatic: {
    deploy(
      _vaultHealthAddress: string,
      overrides?: CallOverrides
    ): Promise<string>;

    "deploy(address)"(
      _vaultHealthAddress: string,
      overrides?: CallOverrides
    ): Promise<string>;
  };

  filters: {
    Deploy(addr: null): EventFilter;
  };

  estimateGas: {
    deploy(
      _vaultHealthAddress: string,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "deploy(address)"(
      _vaultHealthAddress: string,
      overrides?: Overrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    deploy(
      _vaultHealthAddress: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "deploy(address)"(
      _vaultHealthAddress: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;
  };
}
