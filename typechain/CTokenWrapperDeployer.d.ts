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

interface CTokenWrapperDeployerInterface extends ethers.utils.Interface {
  functions: {
    "deploy(address,address)": FunctionFragment;
  };

  encodeFunctionData(
    functionFragment: "deploy",
    values: [string, string]
  ): string;

  decodeFunctionResult(functionFragment: "deploy", data: BytesLike): Result;

  events: {};
}

export class CTokenWrapperDeployer extends Contract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  on(event: EventFilter | string, listener: Listener): this;
  once(event: EventFilter | string, listener: Listener): this;
  addListener(eventName: EventFilter | string, listener: Listener): this;
  removeAllListeners(eventName: EventFilter | string): this;
  removeListener(eventName: any, listener: Listener): this;

  interface: CTokenWrapperDeployerInterface;

  functions: {
    deploy(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "deploy(address,address)"(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;
  };

  deploy(
    _underlyingAssetAddress: string,
    _owner: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "deploy(address,address)"(
    _underlyingAssetAddress: string,
    _owner: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  callStatic: {
    deploy(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: CallOverrides
    ): Promise<string>;

    "deploy(address,address)"(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: CallOverrides
    ): Promise<string>;
  };

  filters: {};

  estimateGas: {
    deploy(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "deploy(address,address)"(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: Overrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    deploy(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "deploy(address,address)"(
      _underlyingAssetAddress: string,
      _owner: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;
  };
}
