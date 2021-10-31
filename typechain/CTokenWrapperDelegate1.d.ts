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

interface CTokenWrapperDelegate1Interface extends ethers.utils.Interface {
  functions: {
    "depositUnitAmount(address,uint256)": FunctionFragment;
    "depositWrappedAmount(address,uint256)": FunctionFragment;
    "forceRewardsCollection()": FunctionFragment;
    "harvestToTreasury()": FunctionFragment;
    "owner()": FunctionFragment;
    "transferOwnership(address)": FunctionFragment;
    "withdrawUnitAmount(address,uint256,bool)": FunctionFragment;
    "withdrawWrappedAmount(address,uint256,bool)": FunctionFragment;
  };

  encodeFunctionData(
    functionFragment: "depositUnitAmount",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "depositWrappedAmount",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "forceRewardsCollection",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "harvestToTreasury",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "owner", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "transferOwnership",
    values: [string]
  ): string;
  encodeFunctionData(
    functionFragment: "withdrawUnitAmount",
    values: [string, BigNumberish, boolean]
  ): string;
  encodeFunctionData(
    functionFragment: "withdrawWrappedAmount",
    values: [string, BigNumberish, boolean]
  ): string;

  decodeFunctionResult(
    functionFragment: "depositUnitAmount",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "depositWrappedAmount",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "forceRewardsCollection",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "harvestToTreasury",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "owner", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "transferOwnership",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "withdrawUnitAmount",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "withdrawWrappedAmount",
    data: BytesLike
  ): Result;

  events: {
    "EVNT(uint256)": EventFragment;
    "FlashBurn(address,uint256,uint256)": EventFragment;
    "FlashMint(address,uint256)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "EVNT"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "FlashBurn"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "FlashMint"): EventFragment;
}

export class CTokenWrapperDelegate1 extends Contract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  on(event: EventFilter | string, listener: Listener): this;
  once(event: EventFilter | string, listener: Listener): this;
  addListener(eventName: EventFilter | string, listener: Listener): this;
  removeAllListeners(eventName: EventFilter | string): this;
  removeListener(eventName: any, listener: Listener): this;

  interface: CTokenWrapperDelegate1Interface;

  functions: {
    depositUnitAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "depositUnitAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    depositWrappedAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "depositWrappedAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    forceRewardsCollection(overrides?: Overrides): Promise<ContractTransaction>;

    "forceRewardsCollection()"(
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    harvestToTreasury(overrides?: Overrides): Promise<ContractTransaction>;

    "harvestToTreasury()"(overrides?: Overrides): Promise<ContractTransaction>;

    owner(overrides?: CallOverrides): Promise<{
      0: string;
    }>;

    "owner()"(overrides?: CallOverrides): Promise<{
      0: string;
    }>;

    transferOwnership(
      newOwner: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "transferOwnership(address)"(
      newOwner: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    withdrawUnitAmount(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "withdrawUnitAmount(address,uint256,bool)"(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    withdrawWrappedAmount(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "withdrawWrappedAmount(address,uint256,bool)"(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<ContractTransaction>;
  };

  depositUnitAmount(
    _to: string,
    _amount: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "depositUnitAmount(address,uint256)"(
    _to: string,
    _amount: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  depositWrappedAmount(
    _to: string,
    _amount: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "depositWrappedAmount(address,uint256)"(
    _to: string,
    _amount: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  forceRewardsCollection(overrides?: Overrides): Promise<ContractTransaction>;

  "forceRewardsCollection()"(
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  harvestToTreasury(overrides?: Overrides): Promise<ContractTransaction>;

  "harvestToTreasury()"(overrides?: Overrides): Promise<ContractTransaction>;

  owner(overrides?: CallOverrides): Promise<string>;

  "owner()"(overrides?: CallOverrides): Promise<string>;

  transferOwnership(
    newOwner: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "transferOwnership(address)"(
    newOwner: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  withdrawUnitAmount(
    _to: string,
    _amountUnit: BigNumberish,
    _claimRewards: boolean,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "withdrawUnitAmount(address,uint256,bool)"(
    _to: string,
    _amountUnit: BigNumberish,
    _claimRewards: boolean,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  withdrawWrappedAmount(
    _to: string,
    _amountWrappedToken: BigNumberish,
    _claimRewards: boolean,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "withdrawWrappedAmount(address,uint256,bool)"(
    _to: string,
    _amountWrappedToken: BigNumberish,
    _claimRewards: boolean,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  callStatic: {
    depositUnitAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "depositUnitAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    depositWrappedAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "depositWrappedAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    forceRewardsCollection(overrides?: CallOverrides): Promise<void>;

    "forceRewardsCollection()"(overrides?: CallOverrides): Promise<void>;

    harvestToTreasury(overrides?: CallOverrides): Promise<void>;

    "harvestToTreasury()"(overrides?: CallOverrides): Promise<void>;

    owner(overrides?: CallOverrides): Promise<string>;

    "owner()"(overrides?: CallOverrides): Promise<string>;

    transferOwnership(
      newOwner: string,
      overrides?: CallOverrides
    ): Promise<void>;

    "transferOwnership(address)"(
      newOwner: string,
      overrides?: CallOverrides
    ): Promise<void>;

    withdrawUnitAmount(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "withdrawUnitAmount(address,uint256,bool)"(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    withdrawWrappedAmount(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "withdrawWrappedAmount(address,uint256,bool)"(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  filters: {
    EVNT(its: null): EventFilter;

    FlashBurn(
      from: string | null,
      wrappedAmount: null,
      feeAmount: null
    ): EventFilter;

    FlashMint(to: string | null, wrappedAmount: null): EventFilter;
  };

  estimateGas: {
    depositUnitAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "depositUnitAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    depositWrappedAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "depositWrappedAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    forceRewardsCollection(overrides?: Overrides): Promise<BigNumber>;

    "forceRewardsCollection()"(overrides?: Overrides): Promise<BigNumber>;

    harvestToTreasury(overrides?: Overrides): Promise<BigNumber>;

    "harvestToTreasury()"(overrides?: Overrides): Promise<BigNumber>;

    owner(overrides?: CallOverrides): Promise<BigNumber>;

    "owner()"(overrides?: CallOverrides): Promise<BigNumber>;

    transferOwnership(
      newOwner: string,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "transferOwnership(address)"(
      newOwner: string,
      overrides?: Overrides
    ): Promise<BigNumber>;

    withdrawUnitAmount(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "withdrawUnitAmount(address,uint256,bool)"(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<BigNumber>;

    withdrawWrappedAmount(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "withdrawWrappedAmount(address,uint256,bool)"(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    depositUnitAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "depositUnitAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    depositWrappedAmount(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "depositWrappedAmount(address,uint256)"(
      _to: string,
      _amount: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    forceRewardsCollection(
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "forceRewardsCollection()"(
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    harvestToTreasury(overrides?: Overrides): Promise<PopulatedTransaction>;

    "harvestToTreasury()"(overrides?: Overrides): Promise<PopulatedTransaction>;

    owner(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    "owner()"(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    transferOwnership(
      newOwner: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "transferOwnership(address)"(
      newOwner: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    withdrawUnitAmount(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "withdrawUnitAmount(address,uint256,bool)"(
      _to: string,
      _amountUnit: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    withdrawWrappedAmount(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "withdrawWrappedAmount(address,uint256,bool)"(
      _to: string,
      _amountWrappedToken: BigNumberish,
      _claimRewards: boolean,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;
  };
}
