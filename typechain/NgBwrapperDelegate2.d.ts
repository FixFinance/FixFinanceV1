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

interface NgBwrapperDelegate2Interface extends ethers.utils.Interface {
  functions: {
    "FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)": FunctionFragment;
    "editSubAccountPosition(bool,address,address,int256,int256)": FunctionFragment;
    "flashLoan(address,address,uint256,bytes)": FunctionFragment;
    "forceClaimSubAccountRewards(bool,address,address,address)": FunctionFragment;
    "owner()": FunctionFragment;
    "transferOwnership(address)": FunctionFragment;
  };

  encodeFunctionData(
    functionFragment: "FCPDirectClaimSubAccountRewards",
    values: [boolean, boolean, string, BigNumberish, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "editSubAccountPosition",
    values: [boolean, string, string, BigNumberish, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "flashLoan",
    values: [string, string, BigNumberish, BytesLike]
  ): string;
  encodeFunctionData(
    functionFragment: "forceClaimSubAccountRewards",
    values: [boolean, string, string, string]
  ): string;
  encodeFunctionData(functionFragment: "owner", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "transferOwnership",
    values: [string]
  ): string;

  decodeFunctionResult(
    functionFragment: "FCPDirectClaimSubAccountRewards",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "editSubAccountPosition",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "flashLoan", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "forceClaimSubAccountRewards",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "owner", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "transferOwnership",
    data: BytesLike
  ): Result;

  events: {
    "FlashBurn(address,uint256,uint256)": EventFragment;
    "FlashMint(address,uint256)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "FlashBurn"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "FlashMint"): EventFragment;
}

export class NgBwrapperDelegate2 extends Contract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  on(event: EventFilter | string, listener: Listener): this;
  once(event: EventFilter | string, listener: Listener): this;
  addListener(eventName: EventFilter | string, listener: Listener): this;
  removeAllListeners(eventName: EventFilter | string): this;
  removeListener(eventName: any, listener: Listener): this;

  interface: NgBwrapperDelegate2Interface;

  functions: {
    FCPDirectClaimSubAccountRewards(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)"(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    editSubAccountPosition(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "editSubAccountPosition(bool,address,address,int256,int256)"(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    flashLoan(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "flashLoan(address,address,uint256,bytes)"(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    forceClaimSubAccountRewards(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

    "forceClaimSubAccountRewards(bool,address,address,address)"(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>;

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
  };

  FCPDirectClaimSubAccountRewards(
    _inPayoutPhase: boolean,
    _claimRewards: boolean,
    _subAcct: string,
    _yield: BigNumberish,
    _wrappedClaim: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)"(
    _inPayoutPhase: boolean,
    _claimRewards: boolean,
    _subAcct: string,
    _yield: BigNumberish,
    _wrappedClaim: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  editSubAccountPosition(
    _claimRewards: boolean,
    _subAcct: string,
    _FCPaddr: string,
    changeYield: BigNumberish,
    changeBond: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "editSubAccountPosition(bool,address,address,int256,int256)"(
    _claimRewards: boolean,
    _subAcct: string,
    _FCPaddr: string,
    changeYield: BigNumberish,
    changeBond: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  flashLoan(
    receiver: string,
    token: string,
    amount: BigNumberish,
    data: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "flashLoan(address,address,uint256,bytes)"(
    receiver: string,
    token: string,
    amount: BigNumberish,
    data: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  forceClaimSubAccountRewards(
    _claimRewards: boolean,
    _distributionAccount: string,
    _subAccount: string,
    _FCPaddr: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

  "forceClaimSubAccountRewards(bool,address,address,address)"(
    _claimRewards: boolean,
    _distributionAccount: string,
    _subAccount: string,
    _FCPaddr: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>;

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

  callStatic: {
    FCPDirectClaimSubAccountRewards(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    "FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)"(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    editSubAccountPosition(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    "editSubAccountPosition(bool,address,address,int256,int256)"(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    flashLoan(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: CallOverrides
    ): Promise<boolean>;

    "flashLoan(address,address,uint256,bytes)"(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: CallOverrides
    ): Promise<boolean>;

    forceClaimSubAccountRewards(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: CallOverrides
    ): Promise<void>;

    "forceClaimSubAccountRewards(bool,address,address,address)"(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: CallOverrides
    ): Promise<void>;

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
  };

  filters: {
    FlashBurn(
      from: string | null,
      wrappedAmount: null,
      feeAmount: null
    ): EventFilter;

    FlashMint(to: string | null, wrappedAmount: null): EventFilter;
  };

  estimateGas: {
    FCPDirectClaimSubAccountRewards(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)"(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    editSubAccountPosition(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "editSubAccountPosition(bool,address,address,int256,int256)"(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>;

    flashLoan(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "flashLoan(address,address,uint256,bytes)"(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>;

    forceClaimSubAccountRewards(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: Overrides
    ): Promise<BigNumber>;

    "forceClaimSubAccountRewards(bool,address,address,address)"(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: Overrides
    ): Promise<BigNumber>;

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
  };

  populateTransaction: {
    FCPDirectClaimSubAccountRewards(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)"(
      _inPayoutPhase: boolean,
      _claimRewards: boolean,
      _subAcct: string,
      _yield: BigNumberish,
      _wrappedClaim: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    editSubAccountPosition(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "editSubAccountPosition(bool,address,address,int256,int256)"(
      _claimRewards: boolean,
      _subAcct: string,
      _FCPaddr: string,
      changeYield: BigNumberish,
      changeBond: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    flashLoan(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "flashLoan(address,address,uint256,bytes)"(
      receiver: string,
      token: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    forceClaimSubAccountRewards(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

    "forceClaimSubAccountRewards(bool,address,address,address)"(
      _claimRewards: boolean,
      _distributionAccount: string,
      _subAccount: string,
      _FCPaddr: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>;

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
  };
}
