// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "../../helpers/DividendEnabledData.sol";
import "../../helpers/IYTammData.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/BigMath.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IYieldToken.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/IZCBamm.sol";
import "../../AmmInfoOracle.sol";

contract YTammDelegate is DividendEnabledData, IYTammData {
	using SafeMath for uint256;
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;

	/*
		@return uint: amount of time remaining to maturity (in years) inflated by 64 bits
	*/
	function timeRemaining() internal view returns (uint) {
		return uint( ((maturity-wrapper.lastUpdate())<<64) / SecondsPerYear);
	}

	/*
		@Description: used in swap calculations,
			regular internalTotalSupply is used when minting or when burning LP tokens

		@return uint ret: internalTotalSupply divided by a constant
	*/
	function _inflatedTotalSupply() internal view returns (uint ret) {
		ret = internalTotalSupply.mul(1 ether) / YTtoLmultiplier;
		require(ret > 0);
	}

	/*
		@Description: if this pool has encured losses due to market events there is a chance that
			the ratio of U and YT reserves is out of sync, this function should tell us if this
			has happened or not

		@param int128 _approxYTin: an approximation of the maximum amount of YT that may be swapped
			into this amm in order to get U out. This value should be greater than the actual maximum
			amount of YT that may be swapped in

		@return bool: return true if the U and YT reserve ratio is out of sync, return false otherwise
	*/
	function isOutOfSync(int128 _approxYTin) internal view returns (bool) {
		uint _YTreserves = YTreserves;
		require(_approxYTin > 0);
		uint effectiveTotalSupply = _inflatedTotalSupply();
		uint Uchange = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			effectiveTotalSupply,
			timeRemaining(),
			SlippageConstant,
			1 ether, // fee constant of 1.0 means no fee
			IZCBamm(ZCBammAddress).getAPYFromOracle(),
			_approxYTin
		));
		if (Uchange < Ureserves) {
			// in this case _approxYTin is of no use to us as an upper bound 
			return false;
		}
		uint _MaxYTreserves = _YTreserves + uint(_approxYTin);
		/*
			L = effectiveTotalSupply

			L/_YTreservesAtAPYo == 1
			_YTreservesAtAPYo == L
	
			Thus effectiveTotalSupply == YTLiquidityAboveAPYo
		*/

		//if APYo does not exist along the amm curve return out of sync
		if (_MaxYTreserves >= effectiveTotalSupply) {
			return true;
		}
		uint YTliquidityUnderAPYo = _MaxYTreserves - effectiveTotalSupply;
		if (YTliquidityUnderAPYo < 2*effectiveTotalSupply) {
			return true;
		}
		return false;
	}

	/*
		@Description: add new dividend round

		@param uint ZCBdividend: the amount of ZCB in unit in round dividend
		@param uint YTdividend: the amount of YT in unit in round divided
	*/
	function writeNextDividend(uint ZCBdividend, uint YTdividend) internal {
		uint scaledYield = wrapper.UnitAmtToWrappedAmt_RoundDown(YTdividend);
		/*
			ZCBdividend == scaledYield + balanceBond
			balanceBond == ZCBdividend - scaledYield
		*/
		int balanceBond = int(ZCBdividend) - int(scaledYield);

		uint lastIndex = contractZCBDividend.length - 1;
		uint prevYieldDividend = contractYieldDividend[lastIndex];
		int prevZCBDividend = contractZCBDividend[lastIndex];

		//normalise with activeTotalSupply
		uint _activeTotalSupply = activeTotalSupply;
		if (_activeTotalSupply == 0) {
			//in odd case that there is no active supply all supply is made active
			//this is done by pushing the previous lastValues in the dividend arrays
			//then we push the new values, thus giving those with previously non active
			//LP shares the chance to earn the interest, also avoid div by 0
			contractYieldDividend.push(prevYieldDividend);
			contractZCBDividend.push(prevZCBDividend);
			_activeTotalSupply = internalTotalSupply;
		}

		scaledYield = scaledYield.mul(1 ether).div(_activeTotalSupply);
		balanceBond = balanceBond.mul(1 ether).div(int(_activeTotalSupply));

		contractYieldDividend.push(scaledYield + prevYieldDividend);
		contractZCBDividend.push(balanceBond + prevZCBDividend);

		totalZCBDividend += ZCBdividend;
		totalYTDividend += YTdividend;
	}

	/*
		@Description: resupply all excess funds (interest generated and funds donated to the contrac) as liquidity
			for the funds that cannot be supplied as liqudity redistribute them out to LP token holders as dividends
	*/
	function contractClaimDividend() external {
		require(lastWithdraw + 1 days < block.timestamp, "this function can only be called once every 24 hours");

		uint _YTreserves = YTreserves;	//gas savings
		uint _Ureserves = Ureserves;	//gas savings
		uint _YT_Ur = _Ureserves + _YTreserves;

		uint amtZCB = IERC20(ZCBaddress).balanceOf(address(this));
		uint amtYT = IYieldToken(YTaddress).balanceOf_2(address(this), false);
		require(amtZCB > _Ureserves);
		require(amtYT > _YT_Ur);
		amtZCB = amtZCB - _Ureserves + ZCBdividendOut;
		amtYT = amtYT - _YT_Ur + YTdividendOut;

		(uint prevZCBdividend, uint prevYTdividend) = (totalZCBDividend, totalYTDividend);

		require(amtZCB > prevZCBdividend);
		require(amtYT > prevYTdividend);

		{
			uint ZCBoverReserves = amtZCB - prevZCBdividend;
			uint YToverReserves = amtYT - prevYTdividend;

			uint ZCBoverutilization = ZCBoverReserves.mul(1 ether).div(_Ureserves);
			uint YToverutilization = YToverReserves.mul(1 ether).div(_YT_Ur);

			/*
				Scale up reserves and effective total supply as much as possible
			*/
			if (ZCBoverutilization > YToverutilization) {
				uint scaledZCBoverReserves = ZCBoverReserves.mul(YToverutilization).div(ZCBoverutilization);

				amtZCB = ZCBoverReserves.sub(scaledZCBoverReserves);
				amtYT = 0;

				YTreserves += YToverReserves.sub(scaledZCBoverReserves);
				Ureserves += scaledZCBoverReserves;

				/*
					L == effectiveTotalSupply == internalTotalSupply / YTtoLmultiplier
					
					L * (1 + YToverutilization) == internalTotalSupply / (YTtoLmultiplier / (1 + YToverutilization) )

					to increase L by YToverutilization do:
					YTtoLmultiplier /= 1 + YToverutilization
				*/
				YTtoLmultiplier = YTtoLmultiplier.mul(1 ether).div((YToverutilization).add(1 ether));
				writeNextDividend(ZCBoverReserves.sub(scaledZCBoverReserves), 0);
			}
			else {
				uint scaledYToverReserves = YToverReserves.mul(ZCBoverutilization).div(YToverutilization);

				amtZCB = 0;
				amtYT = YToverReserves.sub(scaledYToverReserves).add(prevYTdividend);

				YTreserves += scaledYToverReserves.sub(ZCBoverReserves);
				Ureserves += ZCBoverReserves;
				/*
					L == effectiveTotalSupply == internalTotalSupply / YTtoLmultiplier
					
					L * (1 + ZCBoverutilization) == internalTotalSupply / (YTtoLmultiplier / (1 + ZCBoverutilization) )

					to increase L by ZCBoverutilization do:
					YTtoLmultiplier /= 1 + ZCBoverutilization
				*/
				YTtoLmultiplier = YTtoLmultiplier.mul(1 ether).div((ZCBoverutilization).add(1 ether));
				writeNextDividend(0, YToverReserves.sub(scaledYToverReserves));
			}
		}

		lastWithdraw = block.timestamp;
	}


	/*
		@Description: as time progresses the optimal ratio of YT to U reserves changes
			this function ensures that we return to that ratio every so often
			this function may also be called when outOfSync returns true

		@param int128 _approxYTin: an approximation of the maximum amount of YT that may be swapped
			into this amm in order to get U out. This value should be greater than the actual maximum
			amount of YT that may be swapped in
			This param only matters if the user is trying to recalibrate based on reserves going out
			of sync
	*/
	function recalibrate(int128 _approxYTin) external {
		require(block.timestamp > lastRecalibration + 4 weeks || isOutOfSync(_approxYTin));
		/*
			Ureserves == (1 - APYo**(-timeRemaining)) * YTreserves

			APYeff == APYo**(L/YTreserves)
			APYerr == APYo
			L/YTreserves == 1
			L == YTreserves
		*/
		uint _YTreserves = YTreserves;
		uint impliedUreserves;
		{
			int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
			int128 _TimeRemaining = int128(timeRemaining());
			//we want to recalibrate such that it is perfectly calibrated at the
			//midpoint in time between this recalibration and the next
			if (_TimeRemaining > 2*_2WeeksABDK) {
				_TimeRemaining -= _2WeeksABDK;
			}
			// term == OracleRate**(-_TimeRemaining)
			int128 term = OracleRate.log_2().mul(_TimeRemaining).neg().exp_2();
			int128 multiplier = BigMath.ABDK_1.sub(term);
			impliedUreserves = YTreserves.mul(uint(multiplier)) >> 64;
		}
		uint _Ureserves = Ureserves;
		if (_Ureserves > impliedUreserves) {
			Ureserves = impliedUreserves;
		}
		else {
			_YTreserves = _YTreserves.mul(_Ureserves).div(impliedUreserves);
			YTreserves = _YTreserves;
		}
		/*
			L == internalTotalSupply / YTtoLmultiplier
			L/YTreserves == 1
			L == YTreserves
			YTreserves == internalTotalSupply / YTtoLmultiplier
			YTtoLmultiplier == internalTotalSupply / YTreserves
		*/
		YTtoLmultiplier = internalTotalSupply.mul(1 ether) / _YTreserves;
		SlippageConstant = AmmInfoOracle(AmmInfoOracleAddress).getSlippageConstant(FCPaddress);
		lastRecalibration = block.timestamp;
		//ensure noone reserves quote before recalibrating and is then able to take the quote
		quoteSignature = bytes32(0);
	}
}