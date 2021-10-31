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
  CallOverrides,
} from "@ethersproject/contracts";
import { BytesLike } from "@ethersproject/bytes";
import { Listener, Provider } from "@ethersproject/providers";
import { FunctionFragment, EventFragment, Result } from "@ethersproject/abi";

interface BigMathInterface extends ethers.utils.Interface {
  functions: {
    "ABDK_1()": FunctionFragment;
    "SecondsPerYear()": FunctionFragment;
    "YT_U_PoolConstantMinusU(uint256,uint256,uint256,uint256,uint256,int128)": FunctionFragment;
    "YT_U_ratio(int128,uint256)": FunctionFragment;
    "YT_U_reserve_change(uint256,uint256,uint256,uint256,uint256,int128,int128)": FunctionFragment;
    "ZCB_U_ReserveAndFeeChange(uint256,uint256,uint256,int128,address,address,bool)": FunctionFragment;
    "ZCB_U_recalibration(uint256,int128,int128,uint256,uint256,uint256,uint256)": FunctionFragment;
    "ZCB_U_reserve_change(uint256,uint256,uint256,uint256,int128)": FunctionFragment;
  };

  encodeFunctionData(functionFragment: "ABDK_1", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "SecondsPerYear",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "YT_U_PoolConstantMinusU",
    values: [
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "YT_U_ratio",
    values: [BigNumberish, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "YT_U_reserve_change",
    values: [
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "ZCB_U_ReserveAndFeeChange",
    values: [
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      string,
      string,
      boolean
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "ZCB_U_recalibration",
    values: [
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "ZCB_U_reserve_change",
    values: [
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish,
      BigNumberish
    ]
  ): string;

  decodeFunctionResult(functionFragment: "ABDK_1", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "SecondsPerYear",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "YT_U_PoolConstantMinusU",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "YT_U_ratio", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "YT_U_reserve_change",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "ZCB_U_ReserveAndFeeChange",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "ZCB_U_recalibration",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "ZCB_U_reserve_change",
    data: BytesLike
  ): Result;

  events: {};
}

export class BigMath extends Contract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  on(event: EventFilter | string, listener: Listener): this;
  once(event: EventFilter | string, listener: Listener): this;
  addListener(eventName: EventFilter | string, listener: Listener): this;
  removeAllListeners(eventName: EventFilter | string): this;
  removeListener(eventName: any, listener: Listener): this;

  interface: BigMathInterface;

  functions: {
    ABDK_1(overrides?: CallOverrides): Promise<{
      0: BigNumber;
    }>;

    "ABDK_1()"(overrides?: CallOverrides): Promise<{
      0: BigNumber;
    }>;

    SecondsPerYear(overrides?: CallOverrides): Promise<{
      0: BigNumber;
    }>;

    "SecondsPerYear()"(overrides?: CallOverrides): Promise<{
      0: BigNumber;
    }>;

    YT_U_PoolConstantMinusU(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      0: BigNumber;
    }>;

    "YT_U_PoolConstantMinusU(uint256,uint256,uint256,uint256,uint256,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      0: BigNumber;
    }>;

    YT_U_ratio(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      ratio: BigNumber;
      0: BigNumber;
    }>;

    "YT_U_ratio(int128,uint256)"(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      ratio: BigNumber;
      0: BigNumber;
    }>;

    YT_U_reserve_change(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      0: BigNumber;
    }>;

    "YT_U_reserve_change(uint256,uint256,uint256,uint256,uint256,int128,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      0: BigNumber;
    }>;

    ZCB_U_ReserveAndFeeChange(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<{
      change: BigNumber;
      treasuryFee: BigNumber;
      sendTo: string;
      0: BigNumber;
      1: BigNumber;
      2: string;
    }>;

    "ZCB_U_ReserveAndFeeChange(uint256,uint256,uint256,int128,address,address,bool)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<{
      change: BigNumber;
      treasuryFee: BigNumber;
      sendTo: string;
      0: BigNumber;
      1: BigNumber;
      2: string;
    }>;

    ZCB_U_recalibration(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      0: BigNumber;
    }>;

    "ZCB_U_recalibration(uint256,int128,int128,uint256,uint256,uint256,uint256)"(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      0: BigNumber;
    }>;

    ZCB_U_reserve_change(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      changeReserve1: BigNumber;
      0: BigNumber;
    }>;

    "ZCB_U_reserve_change(uint256,uint256,uint256,uint256,int128)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<{
      changeReserve1: BigNumber;
      0: BigNumber;
    }>;
  };

  ABDK_1(overrides?: CallOverrides): Promise<BigNumber>;

  "ABDK_1()"(overrides?: CallOverrides): Promise<BigNumber>;

  SecondsPerYear(overrides?: CallOverrides): Promise<BigNumber>;

  "SecondsPerYear()"(overrides?: CallOverrides): Promise<BigNumber>;

  YT_U_PoolConstantMinusU(
    Y: BigNumberish,
    L: BigNumberish,
    r: BigNumberish,
    w: BigNumberish,
    feeConstant: BigNumberish,
    APYo: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  "YT_U_PoolConstantMinusU(uint256,uint256,uint256,uint256,uint256,int128)"(
    Y: BigNumberish,
    L: BigNumberish,
    r: BigNumberish,
    w: BigNumberish,
    feeConstant: BigNumberish,
    APYo: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  YT_U_ratio(
    APY: BigNumberish,
    secondsRemaining: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  "YT_U_ratio(int128,uint256)"(
    APY: BigNumberish,
    secondsRemaining: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  YT_U_reserve_change(
    Y: BigNumberish,
    L: BigNumberish,
    r: BigNumberish,
    w: BigNumberish,
    feeConstant: BigNumberish,
    APYo: BigNumberish,
    changeYreserve: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  "YT_U_reserve_change(uint256,uint256,uint256,uint256,uint256,int128,int128)"(
    Y: BigNumberish,
    L: BigNumberish,
    r: BigNumberish,
    w: BigNumberish,
    feeConstant: BigNumberish,
    APYo: BigNumberish,
    changeYreserve: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  ZCB_U_ReserveAndFeeChange(
    reserve0: BigNumberish,
    reserve1: BigNumberish,
    r: BigNumberish,
    changeReserve0: BigNumberish,
    InfoOracleAddress: string,
    fixCapitalPoolAddress: string,
    flipFee: boolean,
    overrides?: CallOverrides
  ): Promise<{
    change: BigNumber;
    treasuryFee: BigNumber;
    sendTo: string;
    0: BigNumber;
    1: BigNumber;
    2: string;
  }>;

  "ZCB_U_ReserveAndFeeChange(uint256,uint256,uint256,int128,address,address,bool)"(
    reserve0: BigNumberish,
    reserve1: BigNumberish,
    r: BigNumberish,
    changeReserve0: BigNumberish,
    InfoOracleAddress: string,
    fixCapitalPoolAddress: string,
    flipFee: boolean,
    overrides?: CallOverrides
  ): Promise<{
    change: BigNumber;
    treasuryFee: BigNumber;
    sendTo: string;
    0: BigNumber;
    1: BigNumber;
    2: string;
  }>;

  ZCB_U_recalibration(
    prevRatio: BigNumberish,
    prevAnchorABDK: BigNumberish,
    secondsRemaining: BigNumberish,
    lowerBoundAnchor: BigNumberish,
    upperBoundAnchor: BigNumberish,
    ZCBreserves: BigNumberish,
    Ureserves: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  "ZCB_U_recalibration(uint256,int128,int128,uint256,uint256,uint256,uint256)"(
    prevRatio: BigNumberish,
    prevAnchorABDK: BigNumberish,
    secondsRemaining: BigNumberish,
    lowerBoundAnchor: BigNumberish,
    upperBoundAnchor: BigNumberish,
    ZCBreserves: BigNumberish,
    Ureserves: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  ZCB_U_reserve_change(
    reserve0: BigNumberish,
    reserve1: BigNumberish,
    r: BigNumberish,
    feeConstant: BigNumberish,
    changeReserve0: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  "ZCB_U_reserve_change(uint256,uint256,uint256,uint256,int128)"(
    reserve0: BigNumberish,
    reserve1: BigNumberish,
    r: BigNumberish,
    feeConstant: BigNumberish,
    changeReserve0: BigNumberish,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  callStatic: {
    ABDK_1(overrides?: CallOverrides): Promise<BigNumber>;

    "ABDK_1()"(overrides?: CallOverrides): Promise<BigNumber>;

    SecondsPerYear(overrides?: CallOverrides): Promise<BigNumber>;

    "SecondsPerYear()"(overrides?: CallOverrides): Promise<BigNumber>;

    YT_U_PoolConstantMinusU(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "YT_U_PoolConstantMinusU(uint256,uint256,uint256,uint256,uint256,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    YT_U_ratio(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "YT_U_ratio(int128,uint256)"(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    YT_U_reserve_change(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "YT_U_reserve_change(uint256,uint256,uint256,uint256,uint256,int128,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    ZCB_U_ReserveAndFeeChange(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<{
      change: BigNumber;
      treasuryFee: BigNumber;
      sendTo: string;
      0: BigNumber;
      1: BigNumber;
      2: string;
    }>;

    "ZCB_U_ReserveAndFeeChange(uint256,uint256,uint256,int128,address,address,bool)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<{
      change: BigNumber;
      treasuryFee: BigNumber;
      sendTo: string;
      0: BigNumber;
      1: BigNumber;
      2: string;
    }>;

    ZCB_U_recalibration(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "ZCB_U_recalibration(uint256,int128,int128,uint256,uint256,uint256,uint256)"(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    ZCB_U_reserve_change(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "ZCB_U_reserve_change(uint256,uint256,uint256,uint256,int128)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  filters: {};

  estimateGas: {
    ABDK_1(overrides?: CallOverrides): Promise<BigNumber>;

    "ABDK_1()"(overrides?: CallOverrides): Promise<BigNumber>;

    SecondsPerYear(overrides?: CallOverrides): Promise<BigNumber>;

    "SecondsPerYear()"(overrides?: CallOverrides): Promise<BigNumber>;

    YT_U_PoolConstantMinusU(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "YT_U_PoolConstantMinusU(uint256,uint256,uint256,uint256,uint256,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    YT_U_ratio(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "YT_U_ratio(int128,uint256)"(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    YT_U_reserve_change(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "YT_U_reserve_change(uint256,uint256,uint256,uint256,uint256,int128,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    ZCB_U_ReserveAndFeeChange(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "ZCB_U_ReserveAndFeeChange(uint256,uint256,uint256,int128,address,address,bool)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    ZCB_U_recalibration(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "ZCB_U_recalibration(uint256,int128,int128,uint256,uint256,uint256,uint256)"(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    ZCB_U_reserve_change(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    "ZCB_U_reserve_change(uint256,uint256,uint256,uint256,int128)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    ABDK_1(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    "ABDK_1()"(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    SecondsPerYear(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    "SecondsPerYear()"(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    YT_U_PoolConstantMinusU(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    "YT_U_PoolConstantMinusU(uint256,uint256,uint256,uint256,uint256,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    YT_U_ratio(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    "YT_U_ratio(int128,uint256)"(
      APY: BigNumberish,
      secondsRemaining: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    YT_U_reserve_change(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    "YT_U_reserve_change(uint256,uint256,uint256,uint256,uint256,int128,int128)"(
      Y: BigNumberish,
      L: BigNumberish,
      r: BigNumberish,
      w: BigNumberish,
      feeConstant: BigNumberish,
      APYo: BigNumberish,
      changeYreserve: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    ZCB_U_ReserveAndFeeChange(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    "ZCB_U_ReserveAndFeeChange(uint256,uint256,uint256,int128,address,address,bool)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      changeReserve0: BigNumberish,
      InfoOracleAddress: string,
      fixCapitalPoolAddress: string,
      flipFee: boolean,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    ZCB_U_recalibration(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    "ZCB_U_recalibration(uint256,int128,int128,uint256,uint256,uint256,uint256)"(
      prevRatio: BigNumberish,
      prevAnchorABDK: BigNumberish,
      secondsRemaining: BigNumberish,
      lowerBoundAnchor: BigNumberish,
      upperBoundAnchor: BigNumberish,
      ZCBreserves: BigNumberish,
      Ureserves: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    ZCB_U_reserve_change(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    "ZCB_U_reserve_change(uint256,uint256,uint256,uint256,int128)"(
      reserve0: BigNumberish,
      reserve1: BigNumberish,
      r: BigNumberish,
      feeConstant: BigNumberish,
      changeReserve0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;
  };
}
