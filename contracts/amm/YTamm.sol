pragma solidity >=0.6.0;

import "../helpers/IYTamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/SafeMath.sol";
import "../libraries/BigMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../helpers/IZCBamm.sol";
import "../AmmInfoOracle.sol";


contract YTamm is IYTamm {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	address public override ZCBammAddress;
	uint64 public override maturity;

	uint YTreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	address AmmInfoOracleAddress;
	IWrapper wrapper;

	bytes32 quoteSignature;
	int128 quotedAmountYT;
	uint256 quotedAmountU;
	uint256 quotedTreasuryFee;

	uint public lastRecalibration;
	uint public YTtoLmultiplier;
	uint public SlippageConstant;

	int128 _2WeeksABDK = int128((2 weeks << 64)/BigMath.SecondsPerYear);

	/*
		Init AMM
	*/
	constructor(
		address _ZCBammAddress,
		address _feeOracleAddress
	) public {
		name = "aYT amm Liquidity Token";
		symbol = "aYTLT";
		address _ZCBaddress = IZCBamm(_ZCBammAddress).ZCBaddress();
		address _YTaddress = IZCBamm(_ZCBammAddress).YTaddress();
		uint64 _maturity = IZCBamm(_ZCBammAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		int128 apy = IZCBamm(_ZCBammAddress).getAPYFromOracle();
		//YTamm cannot be created until it has a matching ZCBamm from which to get rate information
		require(apy > 0);
		maturity = _maturity;
		ZCBammAddress = _ZCBammAddress;
		AmmInfoOracleAddress = _feeOracleAddress;
		SlippageConstant = AmmInfoOracle(_feeOracleAddress).getSlippageConstant(_ZCBaddress);
		wrapper = ICapitalHandler(_ZCBaddress).wrapper();
		YTtoLmultiplier = BigMath.YT_U_ratio(
			apy,
			maturity-block.timestamp
		);
		init(_ZCBaddress, _YTaddress);
	}

	/*
		@Description: mint LP tokens

		@param address _to: address that shall receive LP tokens
		@param uint _amount: amount of LP tokens to be minted
	*/
	function _mint(address _to, uint _amount) internal {
        claimDividendInternal(_to, _to, true);
		balanceOf[_to] += _amount;
		totalSupply += _amount;

		emit Mint(_to, _amount);
	}

	/*
		@Description: burn LP tokens

		@param address _from: address that is burning LP tokenns
		@param uint _amount: amount of LP tokens to burn
	*/
	function _burn(address _from, uint _amount) internal {
		require(balanceOf[_from] >= _amount);
        claimDividendInternal(_from, _from, true);
		balanceOf[_from] -= _amount;
		totalSupply -= _amount;

		emit Burn(_from, _amount);
	}

	/*
		@Descripiton: aggregate fund transfers when pool receives YT and sends U

		@param uint _amountYT: amount of YT to get
		@param uint _amountU: amount of U to send
		@param uint _treasuryFee: amount of U to be sent to the treasury
		@param address _treasuryAddress: destination of treasury fee
	*/
	function getYTsendU(uint _amountYT, uint _amountU, uint _treasuryFee, address _treasuryAddress)  internal {
		sendZCB(msg.sender, _amountU);
		if (_amountYT > _amountU) {
			getYT(address(this), _amountYT - _amountU);
		}

		sendYT(_treasuryAddress, _treasuryFee);
		sendZCB(_treasuryAddress, _treasuryFee);
	}

	/*
		@Descripiton: aggregate fund transfers when pool sends YT and receives U

		@param uint _amountYT: amount of YT to send
		@param uint _amountU: amount of U to get
		@param uint _treasuryFee: amount of U to be sent to the treasury
		@param address _treasuryAddress: destination of treasury fee
	*/
	function sendYTgetU(uint _amountYT, uint _amountU, uint _treasuryFee, address _treasuryAddress) internal {
		require(_amountYT > _amountU);
		sendYT(msg.sender, _amountYT - _amountU);
		getZCB(address(this), _amountU);

		sendYT(_treasuryAddress, _treasuryFee);
		sendZCB(_treasuryAddress, _treasuryFee);
	}

	/*
		@Description: pool receives ZCB from user

		@param address _to: address to get ZCB from
		@param uint _amount: amount of ZCB for pool to receive
	*/
	function getZCB(address _to, uint _amount) internal {
		IERC20(ZCBaddress).transferFrom(msg.sender, _to, _amount);
	}

	/*
		@Description: pool receives YT from user

		@param address _to: address to get YT from
		@param uint _amount: amount of YT for pool to receive
	*/
	function getYT(address _to, uint _amount) internal {
		IYieldToken(YTaddress).transferFrom_2(msg.sender, _to, _amount, true);
	}

	/*
		@Description: pool transfers ZCB to user

		@param address _to: address to which to transfer ZCB
		@param uint _amount: amount of ZCB to transfer
	*/
	function sendZCB(address _to, uint _amount) internal {
		IERC20(ZCBaddress).transfer(_to, _amount);
	}

	/*
		@Description: pool transfers YT to user

		@param address _to: address to which to transfer YT
		@param uint _amount: amount of YT to transfer
	*/
	function sendYT(address _to, uint _amount) internal {
		IYieldToken(YTaddress).transfer_2(_to, _amount, false);
	}

	/*
		@return uint: amount of time remaining to maturity (in years) inflated by 64 bits
	*/
	function timeRemaining() internal view returns (uint) {
		return uint( ((maturity-wrapper.lastUpdate())<<64) / BigMath.SecondsPerYear);
	}

	/*
		@Description: used in swap calculations,
			regular totalSupply is used when minting or when burning LP tokens

		@return uint ret: totalSupply divided by a constant
	*/
	function _inflatedTotalSupply() internal view returns (uint ret) {
		ret = totalSupply.mul(1 ether) / YTtoLmultiplier;
		require(ret > 0);
	}

	/*
		@Description: get signature of amm state, useful for when reserving and taking amm quotes

		@param bool _YTin: if the user is getting a quote for sendingYT and receiveing U this will be true

		@return bytes32: signature of amm state
	*/
	function getQuoteSignature(bool _YTin) internal view returns (bytes32) {
		IZCBamm zcbamm = IZCBamm(ZCBammAddress);
		(uint updateTimestamp, uint ratio) = wrapper.getStatus();
		return keccak256(abi.encodePacked(totalSupply, YTreserves, zcbamm.getRateFromOracle(), zcbamm.anchor(), _YTin, updateTimestamp, ratio));
	}

	/*
		@Description: write state signature to storage so that quote may be taken later

		@param bool _YTin: if the quote is for sending YT to the pool and receiveing U this will be true
			otherwise it will be false
		@param int128 _amountYT: the amount of YT that is being quoted to be sent or received
		@param uint _amountU: the amount of U that is being quoted to be sent or received
		@param uint _treasuryFee: the amoun of U that will be sent to the treasury if this quote is taken
	*/
	function writeQuoteSignature(bool _YTin, int128 _amountYT, uint _amountU, uint _treasuryFee) internal {
		quoteSignature = getQuoteSignature(_YTin);
		quotedAmountYT = _amountYT;
		quotedAmountU = _amountU;
		quotedTreasuryFee = _treasuryFee;
	}

	/*
		@Description: ensure the quote in storage matches the quote the user is asking for

		@uint _amountU: the amount of U that is quoted to be sent or received
		@param int128 _amountYT: the amount of YT that is quoted to be sent or received
		@param bool _YTin: if the quote is for sendingYT to the pool and receiveing U this will be true
			otherwise it will be false
	*/
	modifier verifyQuote(uint _amountU, int128 _amountYT, bool _YTin) {
		require(quotedAmountU == _amountU);
		require(quotedAmountYT == _amountYT);
		require(getQuoteSignature(_YTin) == quoteSignature);
		_;
	}

	/*
		@Description first deposit of liquidity into this contract, totalSupply must be == 0
			pool starts at equilibrim this means the implied rate of the pool is the same as the rate fetched from the oracle
	*/
	function firstMint(uint128 _Uin) external override {
		require(totalSupply == 0);
		uint YTin = YTtoLmultiplier.mul(_Uin) / (1 ether);

		getYT(address(this), _Uin + YTin);
		getZCB(address(this), _Uin);

		_mint(msg.sender, _Uin);

		Ureserves = _Uin;
		YTreserves = YTin;
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
		@Description: as time progresses the optimal ratio of YT to U reserves changes
			this function ensures that we return to that ratio every so often
			this function may also be called when outOfSync returns true

		@param int128 _approxYTin: an approximation of the maximum amount of YT that may be swapped
			into this amm in order to get U out. This value should be greater than the actual maximum
			amount of YT that may be swapped in
			This param only matters if the user is trying to recalibrate based on reserves going out
			of sync
	*/
	function recalibrate(int128 _approxYTin) external override {
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
				_TimeRemaining = _TimeRemaining.sub(_2WeeksABDK);
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
			L == totalSupply / YTtoLmultiplier
			L/YTreserves == 1
			L == YTreserves
			YTreserves == totalSupply / YTtoLmultiplier
			YTtoLmultiplier == totalSupply / YTreserves
		*/
		YTtoLmultiplier = totalSupply.mul(1 ether) / _YTreserves;
		SlippageConstant = AmmInfoOracle(AmmInfoOracleAddress).getSlippageConstant(ZCBaddress);
		lastRecalibration = block.timestamp;
		//ensure noone reserves quote before recalibrating and is then able to take the quote
		quoteSignature = bytes32(0);
	}

	/*
		@Description: to supply liquidity to this contract this function must be called

		@param uint _amount: the amount of LP tokens to mint
		@param uint _maxUin: the maximum amount of U to deposit as liquidity
		@param uint _maxYTin: the maximum amount of YT to deposit as liquidity
	*/
	function mint(uint _amount, uint _maxUin, uint _maxYTin) external override {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uin = _amount*Ureserves;
		Uin = Uin/_totalSupply + (Uin%_totalSupply == 0 ? 0 : 1);
		require(Uin <= _maxUin);

		uint YTin = _amount*YTreserves;
		YTin = YTin/_totalSupply + (YTin%_totalSupply == 0 ? 0 : 1);
		require(YTin <= _maxYTin);

		getZCB(address(this), Uin);
		getYT(address(this), Uin + YTin);

		_mint(msg.sender, _amount);

		Ureserves += Uin;
		YTreserves += YTin;
	}

	/*
		@Description: to remove liquidity from this contract this function must be called

		@param uint _amount: the amount of LP tokens to burn
	*/
	function burn(uint _amount) external override {
		uint _totalSupply = totalSupply;	//gas savings
		uint Uout = _amount*Ureserves/_totalSupply;
		uint YTout = _amount*YTreserves/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(msg.sender, Uout);
		sendYT(msg.sender, Uout + YTout);

		Ureserves -= Uout;
		YTreserves -= YTout;
	}


	/*
		@Description: call this function to send a specified amount of YT to the contract and receive U

		@param int128 _amount: the amount of YT to send

		@return uint: the amount of U received by the user
	*/
	function SwapFromSpecificYT(int128 _amount) public override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint inflTotalSupply = _inflatedTotalSupply();
		uint nonFeeAdjustedUout = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			(1 ether), //fee constant of 1.0 means no fee
			OracleRate,
			_amount
		));
		uint Uout = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			(1 ether)**2 / AmmInfoOracle(AmmInfoOracleAddress).getYTammFeeConstant(ZCBaddress),
			OracleRate,
			_amount
		));
		(uint treasuryFee, address sendTo) = AmmInfoOracle(AmmInfoOracleAddress).treasuryFee(nonFeeAdjustedUout, Uout);
		uint reserveDecrease = Uout.add(treasuryFee);

		require(Ureserves >= reserveDecrease);

		getYTsendU(uint(_amount), Uout, treasuryFee, sendTo);

		YTreserves += uint(_amount);
		Ureserves -= reserveDecrease;

		emit Swap(msg.sender, uint(_amount), Uout, true);
		return Uout;
	}

	/*
		@Description: call this function to send U to the contract and receive a specified amount of YT

		@param int128 _amount: the amount of YT to receive

		@return uint: the amount of U sent to the contract
	*/
	function SwapToSpecificYT(int128 _amount) public override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint inflTotalSupply = _inflatedTotalSupply();
		uint nonFeeAdjustedUin = uint(BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			(1 ether), //fee constant of 1.0 means no fee
			OracleRate,
			-_amount
		));
		uint Uin = uint(BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			AmmInfoOracle(AmmInfoOracleAddress).getYTammFeeConstant(ZCBaddress),
			OracleRate,
			-_amount
		));
		(uint treasuryFee, address sendTo) = AmmInfoOracle(AmmInfoOracleAddress).treasuryFee(Uin, nonFeeAdjustedUin);
		uint reserveIncrease = Uin.sub(treasuryFee);

		sendYTgetU(uint(_amount), Uin, treasuryFee, sendTo);

		YTreserves -= uint(_amount);
		Ureserves += reserveIncrease;

		emit Swap(msg.sender, uint(_amount), Uin, false);
		return Uin;
	}

	/*
		@Description: send a specific amount of YT to the contract and receive U
			revert if the amount of U received is less than a minimum U desired

		@param int128: the amount of YT to send
		@param uint _minUout: the minimum amount of U desired out

		@return uint: the amont of U received by the user
	*/
	function SwapFromSpecificYTWithLimit(int128 _amount, uint _minUout) external override returns (uint) {
		uint ret = SwapFromSpecificYT(_amount);
		require(ret >= _minUout);
		return ret;
	}

	/*
		@Description: send U to the contract and received a specified amount of YT,
			revert if the amount of U is greater than a maximum amount of U to send

		@param int128: the amount of YT to receive
		@param uint _maxUin: the maximum amount of U the user is willing to send

		@return uint: the amount of U sent to the contract
	*/
	function SwapToSpecificYTWithLimit(int128 _amount, uint _maxUin) external override returns (uint) {
		uint ret = SwapToSpecificYT(_amount);
		require(ret <= _maxUin);
		return ret;
	}

	/*
		@Description: reserve a quote for a swap that sends a specific amount of YT to this contract

		@param int128 _amount: the amount of YT to send in to this contract

		@return uint: the amount of U send out by contract
	*/
	function ReserveQuoteFromYT(int128 _amount) external override returns (uint) {
		require(_amount > 0);
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint _YTreserves = YTreserves;
		uint inflTotalSupply = _inflatedTotalSupply();
		uint nonFeeAdjustedUout = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			(1 ether),
			OracleRate,
			_amount
		));
		uint Uout = uint(-BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			(1 ether)**2 / AmmInfoOracle(AmmInfoOracleAddress).getYTammFeeConstant(ZCBaddress),
			OracleRate,
			_amount
		));
		(uint treasuryFee, ) = AmmInfoOracle(AmmInfoOracleAddress).treasuryFee(nonFeeAdjustedUout, Uout);
		//(uint Uout, uint treasuryFee, ) = AmmInfoOracle(AmmInfoOracleAddress).feeAdjustedAmountOut(maturity, nonFeeAdjustedUout);
		uint reserveDecrease = Uout.add(treasuryFee);
		require(Ureserves >= reserveDecrease);
		writeQuoteSignature(true, _amount, Uout, treasuryFee);
		return Uout;
	}

	/*
		@Description: reserve a quote for a swap in whicht he user receives a specific amount of YT

		@param int128 _amount: the amount of YT out desired

		@return uint: the amount of U sent in to the contract
	*/
	function ReserveQuoteToYT(int128 _amount) external override returns (uint) {
		require(_amount > 0);
		uint _YTreserves = YTreserves;
		require(_YTreserves > uint(_amount));
		uint _TimeRemaining = timeRemaining();
		int128 OracleRate = IZCBamm(ZCBammAddress).getAPYFromOracle();
		uint inflTotalSupply = _inflatedTotalSupply();
		uint nonFeeAdjustedUin = uint(BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			(1 ether),
			OracleRate,
			-_amount
		));
		uint Uin = uint(BigMath.YT_U_reserve_change(
			_YTreserves,
			inflTotalSupply,
			_TimeRemaining,
			SlippageConstant,
			AmmInfoOracle(AmmInfoOracleAddress).getYTammFeeConstant(ZCBaddress),
			OracleRate,
			-_amount
		));
		(uint treasuryFee, ) = AmmInfoOracle(AmmInfoOracleAddress).treasuryFee(Uin, nonFeeAdjustedUin);
		//(uint Uin, uint treasuryFee, ) = AmmInfoOracle(AmmInfoOracleAddress).feeAdjustedAmountIn(maturity, nonFeeAdjustedUin);
		writeQuoteSignature(false, _amount, Uin, treasuryFee);
		return Uin;
	}

	/*
		@Description: take the quote that was most recently reserved

		@param uint _amountU: the amount of U involved in the swap
		@param int128: the amount of YT involved in the swap
		@param bool _YTin: if the quote is for sendingYT to the pool and receiveing U this will be true
			otherwise it will be false
	*/
	function TakeQuote(uint _amountU, int128 _amountYT, bool _YTin) external override verifyQuote(_amountU, _amountYT, _YTin) {
		uint _quotedTreasuryFee = quotedTreasuryFee;
		address sendTo = AmmInfoOracle(AmmInfoOracleAddress).sendTo();
		if (_YTin) {
			uint reserveDecrease = _amountU.add(_quotedTreasuryFee);
			require(Ureserves >= reserveDecrease);
			getYTsendU(uint(_amountYT), _amountU, _quotedTreasuryFee, sendTo);
			YTreserves += uint(_amountYT);
			Ureserves -= reserveDecrease;
		} else {
			uint reserveIncrease = _amountU.sub(_quotedTreasuryFee);
			require(YTreserves > uint(_amountYT));
			sendYTgetU(uint(_amountYT), _amountU, _quotedTreasuryFee, sendTo);
			Ureserves += reserveIncrease;
			YTreserves -= uint(_amountYT);
		}

		emit Swap(msg.sender, uint(_amountYT), _amountU, _YTin);
	}


	//-------------------------implement double asset yield enabled token-------------------------------

	/*
		@Description: resupply all excess funds (interest generated and funds donated to the contrac) as liquidity
			for the funds that cannot be supplied as liqudity redistribute them out to LP token holders as dividends
	*/
	function contractClaimDividend() external override {
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

		uint prevAsset1 = contractBalanceAsset1[contractBalanceAsset1.length-1];
		uint prevAsset2 = contractBalanceAsset2[contractBalanceAsset2.length-1];

		require(amtZCB > prevAsset1);
		require(amtYT > prevAsset2);

		{
			uint ZCBoverReserves = amtZCB - prevAsset1;
			uint YToverReserves = amtYT - prevAsset2;

			uint ZCBoverutilization = ZCBoverReserves.mul(1 ether).div(_Ureserves);
			uint YToverutilization = YToverReserves.mul(1 ether).div(_YT_Ur);

			/*
				Scale up reserves and effective total supply as much as possible
			*/
			if (ZCBoverutilization > YToverutilization) {
				uint scaledZCBoverReserves = ZCBoverReserves.mul(YToverutilization).div(ZCBoverutilization);

				amtZCB = ZCBoverReserves.sub(scaledZCBoverReserves).add(prevAsset1);
				amtYT = prevAsset2;

				YTreserves += YToverReserves.sub(scaledZCBoverReserves);
				Ureserves += scaledZCBoverReserves;

				/*
					L == effectiveTotalSupply == totalSupply / YTtoLmultiplier
					
					L * (1 + YToverutilization) == totalSupply / (YTtoLmultiplier / (1 + YToverutilization) )

					to increase L by YToverutilization do:
					YTtoLmultiplier /= 1 + YToverutilization
				*/
				YTtoLmultiplier = YTtoLmultiplier.mul(1 ether).div((YToverutilization).add(1 ether));
			}
			else {
				uint scaledYToverReserves = YToverReserves.mul(ZCBoverutilization).div(YToverutilization);

				amtZCB = prevAsset1;
				amtYT = YToverReserves.sub(scaledYToverReserves).add(prevAsset2);

				YTreserves += scaledYToverReserves.sub(ZCBoverReserves);
				Ureserves += ZCBoverReserves;
				/*
					L == effectiveTotalSupply == totalSupply / YTtoLmultiplier
					
					L * (1 + ZCBoverutilization) == totalSupply / (YTtoLmultiplier / (1 + ZCBoverutilization) )

					to increase L by ZCBoverutilization do:
					YTtoLmultiplier /= 1 + ZCBoverutilization
				*/
				YTtoLmultiplier = YTtoLmultiplier.mul(1 ether).div((ZCBoverutilization).add(1 ether));
			}
		}

		contractBalanceAsset1.push(amtZCB);
		contractBalanceAsset2.push(amtYT);

		lastWithdraw = block.timestamp;
	}


	//------------------------------v-i-e-w-s-----------------------------------------------

	/*
		@Description: return valuable info about this contract's reserves and time to maturity
	*/
	function getReserves() external view override returns (uint _Ureserves, uint _YTreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_YTreserves = YTreserves;
		_TimeRemaining = timeRemaining();
	}

	/*
		@Description: return value of _inflatedTotalSupply externally
	*/
	function inflatedTotalSupply() external override view returns (uint) {
		return _inflatedTotalSupply();
	}

}

