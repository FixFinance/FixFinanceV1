pragma solidity >=0.6.0;

import "../helpers/IZCBamm.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IERC20.sol";
import "../AmmInfoOracle.sol";

contract ZCBamm is IZCBamm {

	using ABDKMath64x64 for int128;
	using SignedSafeMath for int256;
	using SafeMath for uint256;

	uint8 private constant LENGTH_RATE_SERIES = 31;
	uint8 private constant ANCHOR_MULTIPLIER = 8;
	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
	uint private constant SecondsPerYear = 31556926;


	uint64 public override maturity;
	uint public override anchor;
	uint public override nextAnchor;

	uint ZCBreserves;
	uint Ureserves;

	string public override name;
	string public override symbol;

	address AmmInfoOracleAddress;
	IWrapper wrapper;

	bytes32 quoteSignature;
	uint256 quotedAmountIn;
	uint256 quotedAmountOut;
	uint256 quotedTreasuryFee;

	uint lastRecalibration;
	uint LPTokenInflation;

	uint8 toSet;
	bool CanSetOracleRate;
	int128 OracleRate;
	int128[LENGTH_RATE_SERIES] impliedRates;
	uint[LENGTH_RATE_SERIES] timestamps;


	/*
		Init AMM
	*/
	constructor(address _ZCBaddress, address _feeOracleAddress) public {
		name = "aZCB amm Liquidity Token";
		symbol = "aZCBLT";
		address _YTaddress = ICapitalHandler(_ZCBaddress).yieldTokenAddress();
		uint64 _maturity = ICapitalHandler(_ZCBaddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		maturity = _maturity;
		//we want time remaining / anchor to be less than 1, thus make anchor greater than time remaining
		uint temp = ANCHOR_MULTIPLIER * (maturity - block.timestamp);
		anchor = temp;
		nextAnchor = temp;
		AmmInfoOracleAddress = _feeOracleAddress;
		wrapper = ICapitalHandler(_ZCBaddress).wrapper();
		lastRecalibration = block.timestamp;
		ZCBaddress = _ZCBaddress;
		YTaddress = _YTaddress;
	}

	/*
		@Description: mint LP tokens

		@param address _to: address that shall receive LP tokens
		@param uint _amount: amount of LP tokens to be minted
	*/
	function _mint(address _to, uint _amount) internal {
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
		balanceOf[_from] -= _amount;
		totalSupply -= _amount;

		emit Burn(_from, _amount);
	}

	/*
		@Descripiton: aggregate fund transfers when pool receives ZCB and sends U

		@param uint _amountZCB: amount of ZCB to get
		@param uint _amountU: amount of U to send
		@param uint _treasuryFee: amount of ZCB or U to be sent to the treasury
		@param address _treasuryAddress: destination of treasury fee
		@param bool _treasuryFeeInZCB: true when treasury fee is in ZCB false when treasury Fee is in U
	*/
	function getZCBsendU(uint _amountZCB, uint _amountU, uint _treasuryFee, address _treasuryAddress, bool _treasuryFeeInZCB) internal {
		sendYT(msg.sender, _amountU);
		if (_amountZCB > _amountU) {
			getZCB(address(this), _amountZCB - _amountU);
		}

		sendZCB(_treasuryAddress, _treasuryFee);
		if (!_treasuryFeeInZCB) {
			sendYT(_treasuryAddress, _treasuryFee);
		}
	}

	/*
		@Descripiton: aggregate fund transfers when pool sends ZCB and receives U

		@param uint _amountZCB: amount of ZCB to send
		@param uint _amountU: amount of U to get
		@param uint _treasuryFee: amount of ZCB or U to be sent to the treasury
		@param address _treasuryAddress: destination of treasury fee
		@param bool _treasuryFeeInZCB: true when treasury fee is in ZCB false when treasury Fee is in U
	*/
	function sendZCBgetU(uint _amountZCB, uint _amountU, uint _treasuryFee, address _treasuryAddress, bool _treasuryFeeInZCB) internal {
		require(_amountZCB > _amountU);
		sendZCB(msg.sender, _amountZCB - _amountU);
		getYT(address(this), _amountU);

		sendZCB(_treasuryAddress, _treasuryFee);
		if (!_treasuryFeeInZCB) {
			sendYT(_treasuryAddress, _treasuryFee);
		}
	}

	/*
		@Description: pool receives ZCB from user

		@param address _to: address to get ZCB from
		@param uint _amount: amount of ZCB for pool to receive
	*/
	function getZCB(address _to, uint _amount) internal {
		ICapitalHandler(ZCBaddress).transferFrom(msg.sender, _to, _amount);
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
		ICapitalHandler(ZCBaddress).transfer(_to, _amount);
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
		@Description: time (in anchor) remaining to maturity inflated by 64 bits
	*/
	function timeRemaining() internal view returns (uint) {
		return uint( ((maturity-wrapper.lastUpdate())<<64) / anchor);
	}

	/*
		@Description: time (in nextAnchor) remaining to maturity inflated by 64 bits
	*/
	function nextTimeRemaining() internal view returns (uint) {
		return uint( ((maturity-wrapper.lastUpdate())<<64) / nextAnchor);
	}

	/*
		@Description: get signature of amm state, useful for when reserving and taking amm quotes

		@param uint8 _tradeType: [0, 4) represents one of the 4 different types of swaps that may be
			made with this amm

		@return bytes32: signature of amm state
	*/
	function getQuoteSignature(uint8 _tradeType) internal view returns (bytes32) {
		(uint updateTimestamp, uint ratio) = wrapper.getStatus();
		return keccak256(abi.encodePacked(totalSupply, ZCBreserves, Ureserves, _tradeType, updateTimestamp, ratio));
	}

	/*
		@Description: used in swap calculations,
			regular totalSupply is used when minting or when burning LP tokens

		@return uint ret: totalSupply multiplied by a constant
	*/
	function _inflatedTotalSupply() internal view returns (uint) {
		return totalSupply.mul(LPTokenInflation).div(1 ether);
	}

	/*
		@Description: write state signature to storage so that quote may be taken later

		@param bool _ZCBin: if the quote is for sending ZCB to the pool and receiveing U this will be true
			otherwise it will be false
		@param bool _ToSpecific: if the swap was reserved by specifying a specific amount out desired this is true
			otherwise it will be false
		@param uint _amountIn: the quoted amount of ZCB or U that is to be sent in to this contract
		@param uint _amountOut: the quoted amount of ZCB or U that is to be sent out of this contract
		@param uint _treasuryFee: the amoun of ZCB or U that will be sent to the treasury if this quote is taken
	*/
	function writeQuoteSignature(bool _ZCBin, bool _ToSpecific, uint _amountIn, uint _amountOut, uint _treasuryFee) internal returns (bytes32) {
		quoteSignature = getQuoteSignature(tradeType(_ZCBin, _ToSpecific));
		quotedAmountIn = _amountIn;
		quotedAmountOut = _amountOut;
		quotedTreasuryFee = _treasuryFee;
	}

	/*
		@Description: get a trade type identifier

		@param bool _ZCBin: if the quote is for sending ZCB to the pool and receiveing U this will be true
			otherwise it will be false
		@param bool _ToSpecific: if the swap was reserved by specifying a specific amount out desired this is true
			otherwise it will be false

		@return uint8: trade type identifier
	*/
	function tradeType(bool _ZCBin, bool _ToSpecific) internal pure returns (uint8) {
		return uint8((_ZCBin ? 2: 0) | (_ToSpecific ? 1 : 0));
	}

	/*
		@Description: ensure the quote in storage matches the quote the user is asking for

		@param uint _amountIn: the quoted amount of ZCB or U that is to be sent in to this contract
		@param uint _amountOut: the quoted amount of ZCB or U that is to be sent out of this contract
		@param bool _ZCBin: if the quote is for sending ZCB to the pool and receiveing U this will be true
			otherwise it will be false
		@param bool _ToSpecific: if the swap was reserved by specifying a specific amount out desired this is true
			otherwise it will be false
	*/
	modifier verifyQuote(uint _amountIn, uint _amountOut, bool _ZCBin, bool _ToSpecific) {
		require(quotedAmountIn == _amountIn);
		require(quotedAmountOut == _amountOut);
		require(getQuoteSignature(tradeType(_ZCBin, _ToSpecific)) == quoteSignature);
		_;
	}

	/*
		@Description: first deposit of liquidity into this contract totalSupply must == 0,
		
		@param uint128 _Uin: the amount of U to be supplied to the pool
		@param uint128 _ZCBin: the amount of ZCB to be swapped in against the initial U
			this serves the purpose of letting the initial depositer deposit at a custom rate
	*/
	function firstMint(uint128 _Uin, uint128 _ZCBin) external override {
		require(totalSupply == 0);

		uint r = nextTimeRemaining();
		uint _Uout = uint(- BigMath.ZCB_U_reserve_change(
			_Uin,
			_Uin,
			r,
			(1 ether),
			int128(_ZCBin)
		));

		require(_Uout < _Uin);
		uint effectiveU = _Uin - _Uout;

		getZCB(address(this), effectiveU + _ZCBin);
		getYT(address(this), effectiveU);

		_mint(msg.sender, _Uin);

		LPTokenInflation = 1 ether;
		ZCBreserves = _ZCBin;
		Ureserves = effectiveU;
	}

	/*
		@Description: to supply liquidity to this contract this function must be called

		@param uint _amount: the amount of LP tokens to mint
		@param uint _maxYTin: the maximum amount of YT to deposit as liquidity
		@param uint _maxUin: the maximum amount of ZCB to deposit as liquidity
	*/
	function mint(uint _amount, uint _maxYTin, uint _maxZCBin) external override setRateModifier {
		uint _totalSupply = totalSupply;	//gas savings

		uint contractZCBbalance = IERC20(ZCBaddress).balanceOf(address(this));
		uint contractYTbalance = IYieldToken(YTaddress).balanceOf_2(address(this), false);

		uint ZCBin = _amount.mul(contractZCBbalance);
		ZCBin = ZCBin/_totalSupply + (ZCBin%_totalSupply == 0 ? 0 : 1);
		require(ZCBin <= _maxZCBin);

		uint YTin = _amount.mul(contractYTbalance);
		YTin = YTin/_totalSupply + (YTin%_totalSupply == 0 ? 0 : 1);
		require(YTin <= _maxYTin);

		getZCB(address(this), ZCBin);
		getYT(address(this), YTin);

		_mint(msg.sender, _amount);

		Ureserves = Ureserves.mul(_totalSupply+_amount) / _totalSupply;
		ZCBreserves = ZCBreserves.mul(_totalSupply+_amount) / _totalSupply;
	}

	/*
		@Description: to remove liquidity from this contract this function must be called

		@param uint _amount: the amount of LP tokens to burn
	*/
	function burn(uint _amount) external override setRateModifier {
		uint _totalSupply = totalSupply;	//gas savings

		uint contractZCBbalance = IERC20(ZCBaddress).balanceOf(address(this));
		uint contractYTbalance = IYieldToken(YTaddress).balanceOf_2(address(this), false);

		uint ZCBout = _amount.mul(contractZCBbalance)/_totalSupply;
		uint YTout = _amount.mul(contractYTbalance)/_totalSupply;

		_burn(msg.sender, _amount);

		sendZCB(msg.sender, ZCBout);
		sendYT(msg.sender, YTout);

		Ureserves = Ureserves.mul(_totalSupply-_amount) / _totalSupply;
		ZCBreserves = ZCBreserves.mul(_totalSupply-_amount) / _totalSupply;
	}

	/*
		@Description: call this function to send in a specific amount of ZCB / U and receive U / ZCB from the pool

		@param int128 _amount: the amount of ZCB / U to send into the pool
		@param bool _ZCBin: true if ZCB is being sent to the pool, false otherwise

		@return uint amountOut: the amount of U / ZCB sent out of the contract
	*/
	function SwapFromSpecificTokens(int128 _amount, bool _ZCBin) public override setRateModifier returns (uint amountOut) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		address sendTo;
		uint reserveDecrease;
		if (_ZCBin) {
			(amountOut, treasuryFee, sendTo) = BigMath.ZCB_U_ReserveAndFeeChange(
				ZCBreserves+_inflatedTotalSupply(),
				Ureserves,
				r,
				_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				false
			);

			reserveDecrease = amountOut.add(treasuryFee);

			require(Ureserves >= reserveDecrease);

			getZCBsendU(uint(_amount), amountOut, treasuryFee, sendTo, false);

			ZCBreserves += uint(_amount);
			Ureserves -= reserveDecrease;

			emit Swap(msg.sender, uint(_amount), amountOut, true);

		} else {
			(amountOut, treasuryFee, sendTo) = BigMath.ZCB_U_ReserveAndFeeChange(
				Ureserves,
				ZCBreserves+_inflatedTotalSupply(),
				r,
				_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				true
			);

			reserveDecrease = amountOut.add(treasuryFee);

			require(uint(_amount) < amountOut, "cannot swap to ZCB at negative rate");

			require(ZCBreserves >= reserveDecrease);

			sendZCBgetU(amountOut, uint(_amount), treasuryFee, sendTo, true);

			Ureserves += uint(_amount);
			ZCBreserves -= reserveDecrease;

			emit Swap(msg.sender, amountOut, uint(_amount), false);
		}
	}

	/*
		@Description: call this function to receive a specific amount of ZCB / U from the pool
			and send U / ZCB out of the pool

		@param int128 _amount: the amount of ZCB / U to receive from the pool
		@param bool _ZCBin: true if ZCB is being sent to the pool, false otherwise

		@return uint amountIn: the amount of U / ZCB sent into the contract
	*/
	function SwapToSpecificTokens(int128 _amount, bool _ZCBin) public override setRateModifier returns (uint amountIn) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		address sendTo;
		uint reserveIncrease;
		if (_ZCBin) {
			require(Ureserves >= uint(_amount));
			(amountIn, treasuryFee, sendTo) = BigMath.ZCB_U_ReserveAndFeeChange(
				Ureserves,
				ZCBreserves+_inflatedTotalSupply(),
				r,
				-_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				false
			);
			reserveIncrease = amountIn.sub(treasuryFee);

			getZCBsendU(amountIn, uint(_amount), treasuryFee, sendTo, true);

			ZCBreserves += reserveIncrease;
			Ureserves -= uint(_amount);

			emit Swap(msg.sender, amountIn, uint(_amount), true);
		} else {
			require(ZCBreserves >= uint(_amount));
			(amountIn, treasuryFee, sendTo) = BigMath.ZCB_U_ReserveAndFeeChange(
				ZCBreserves+_inflatedTotalSupply(),
				Ureserves,
				r,
				-_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				true
			);
			reserveIncrease = amountIn.sub(treasuryFee);

			require(uint(_amount) > amountIn, "cannot swap to ZCB at negative rate");

			sendZCBgetU(uint(_amount), amountIn, treasuryFee, sendTo, false);

			Ureserves += reserveIncrease;
			ZCBreserves -= uint(_amount);

			emit Swap(msg.sender, uint(_amount), amountIn, false);
		}
	}

	/*
		@Description: same as SwapFromSpecificTokens except there is a limit on the minimum amount of U / ZCB out
			if this limit is not reached the transaction will revert

		@param int128 _amount: the amount of ZCB / U to send into the amm
		@param bool _ZCBin: true if ZCB is being sent to the pool, false otherwise
		@param uint _minAmtOut: the minimum amount of U / ZCB desired after the swap

		@return uint _out: the amount of U / ZCB sent out of the contract
	*/
	function SwapFromSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _minAmtOut) external override returns(uint _out) {
		_out = SwapFromSpecificTokens(_amount, _ZCBin);
		require(_out >= _minAmtOut);
	}

	/*
		@Description: like SwapToSpecificTokens except there is a limit on the maximum amount of U / ZCB that may
			be sent to the contract

		@param int128 _amount: the amount of ZCB / U to receive from the amm
		@param bool _ZCBin: true if ZCB is being sent to the pool, false otherwise
		@param uint _maxAmtIn: the maximum amount of U / ZCB the user is willing to send into the contract

		@return uint _in: the amount of U / ZCB sent into the contract
	*/
	function SwapToSpecificTokensWithLimit(int128 _amount, bool _ZCBin, uint _maxAmtIn) external override returns(uint _in) {
		_in = SwapToSpecificTokens(_amount, _ZCBin);
		require(_in <= _maxAmtIn);
	}

	/*
		@Description: reserve a quote for a swap that sends a specific amount of ZCB / U to this contract

		@param int128 _amount: the amount of ZCB / U to send to the amm
		@param bool _ZCBin: true if ZCB is being sent to the pool, false otherwise

		@return uint amountOut: the quoted amount of U / ZCB to be received
	*/
	function ReserveQuoteFromSpecificTokens(int128 _amount, bool _ZCBin) external override setRateModifier returns(uint amountOut) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		if (_ZCBin) {
			(amountOut, treasuryFee, ) = BigMath.ZCB_U_ReserveAndFeeChange(
				ZCBreserves+_inflatedTotalSupply(),
				Ureserves,
				r,
				_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				false
			);

			require(Ureserves > amountOut);

		} else {
			(amountOut, treasuryFee, ) = BigMath.ZCB_U_ReserveAndFeeChange(
				Ureserves,
				ZCBreserves+_inflatedTotalSupply(),
				r,
				_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				true
			);

			require(uint(_amount) < amountOut, "cannot swap to ZCB at negative rate");
			
			uint reserveDecrease = amountOut.add(treasuryFee);

			require(ZCBreserves >= reserveDecrease);
		}
		writeQuoteSignature(_ZCBin, false, uint(_amount), amountOut, treasuryFee);
	}

	/*
		@Description: reserve a quote for a swap that receives a specific amount of U / ZCB from this contract

		@param int128 _amount: the amount of ZCB / U to receive from the amm
		@param bool _ZCBin: true if ZCB is being sent to the pool, false otherwise

		@return uint amountIn: the quoted amount of U / ZCB to be sent into this contract
	*/
	function ReserveQuoteToSpecificTokens(int128 _amount, bool _ZCBin) external override setRateModifier returns(uint amountIn) {
		require(_amount > 0);
		uint r = nextTimeRemaining();

		uint treasuryFee;
		if (_ZCBin) {
			require(Ureserves >= uint(_amount));
			(amountIn, treasuryFee, ) = BigMath.ZCB_U_ReserveAndFeeChange(
				Ureserves,
				ZCBreserves+_inflatedTotalSupply(),
				r,
				-_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				false
			);

		} else {
			require(ZCBreserves >= uint(_amount));
			(amountIn, treasuryFee, ) = BigMath.ZCB_U_ReserveAndFeeChange(
				ZCBreserves+_inflatedTotalSupply(),
				Ureserves,
				r,
				-_amount,
				AmmInfoOracleAddress,
				ZCBaddress,
				true
			);

			require(uint(_amount) > amountIn, "cannot swap to ZCB at negative rate");
		}
		writeQuoteSignature(_ZCBin, true, amountIn, uint(_amount), treasuryFee);
	}

	/*
		@Description: take the quote that was most recently reserved

		@param uint _amountIn: the quoted amount of ZCB / U that is to be sent into the amm
		@param uint _amountOut: the quoted amount of U / ZCB that is to be sent out of the amm
		@param bool _ZCBin: if the quote is for sending ZCB to the pool and receiveing U this will be true
			otherwise it will be false
		@param bool _ToSpecific: if the swap was reserved by specifying a specific amount out desired this is true
			otherwise it will be false
	*/
	function TakeQuote(uint _amountIn, uint _amountOut, bool _ZCBin, bool _ToSpecific) external override verifyQuote(_amountIn, _amountOut, _ZCBin, _ToSpecific) {
		address sendTo = AmmInfoOracle(AmmInfoOracleAddress).sendTo();
		uint _quotedTreasuryFee = quotedTreasuryFee;
		uint reserveDecrease = _amountOut.add(!_ToSpecific ? _quotedTreasuryFee : 0);
		if (_ZCBin) {
			require(Ureserves >= reserveDecrease);
			getZCBsendU(_amountIn, _amountOut, _quotedTreasuryFee, sendTo, _ToSpecific);
			ZCBreserves += _amountIn.sub(_ToSpecific ? _quotedTreasuryFee : 0);
			Ureserves -= reserveDecrease;
			emit Swap(msg.sender, _amountIn, _amountOut, _ZCBin);
		} else {
			require(ZCBreserves >= reserveDecrease);
			sendZCBgetU(_amountOut, _amountIn, _quotedTreasuryFee, sendTo, !_ToSpecific);
			Ureserves += _amountIn.sub(_ToSpecific ? _quotedTreasuryFee : 0);
			ZCBreserves -= reserveDecrease;
			emit Swap(msg.sender, _amountOut, _amountIn, _ZCBin);
		}
	}

	//------------------------e-n-a-b-l-e---p-o-o-l---t-o---a-c-t---a-s---r-a-t-e---o-r-a-c-l-e-----------------

	/*
		@Description: force this contract to store a data point in its rate oracle
	*/
	function forceRateDataUpdate() external override setRateModifier {}

	/*
		@Description: write the next rate datapoint to storage
	
		@param uint8 _index: the index within the impliedRates array for which to set a value
	*/
	function internalSetOracleRate(uint8 _index) internal {
		/*
			APY**(anchor/1 year) == ZCBreserves/Ureserves
			APY == (ZCBreserves/Ureserves)**(1 year/anchor)

			the main function of our rate oracle is to feed info to the YTamm which knows the anchor so we are good with storing ZCBreserves/Ureserves here
		*/
		uint _Ureserves = Ureserves;
		uint _ZCBreserves = _inflatedTotalSupply() + ZCBreserves;
		//only record when rate is a positive real number, also _ZCB reserves must fit into 192 bits
		if (Ureserves == 0 || _ZCBreserves >> 192 != 0  || _ZCBreserves <= _Ureserves) return;
		uint rate = (_ZCBreserves << 64) / _Ureserves;
		//rate must fit into 127 bits
		if (rate >= 1 << 128) return;
		timestamps[_index] = block.timestamp;
		impliedRates[_index] = int128(rate);
		if (_index+1 == LENGTH_RATE_SERIES) {
			CanSetOracleRate = true;
			toSet = 0;
		}
		else {
			toSet++;
		}
	}

	/*
		@Description: if enough time has elapsed automatically update the rate data in the oracle
	*/
	modifier setRateModifier() {
		uint8 _toSet = toSet;
		uint8 mostRecent = (LENGTH_RATE_SERIES-1+_toSet)%LENGTH_RATE_SERIES;
		if (block.timestamp >= timestamps[mostRecent] + (2 minutes)) internalSetOracleRate(_toSet);
		_;
	}

	/*
		@Description: return the implied yield from this amm over a period of anchor in ABDK format

		@return int128 rate: impliedAPY**(anchor/1 year)
	*/
	function getRateFromOracle() external view override returns (int128 rate) {
		rate = OracleRate;
	}

	/*
		@Description: set the median of all datapoints in the impliedRates array as the
			oracle rate, may only be called after all datapoints have been updated since
			last call to this function

		@param int128 _rate: the median of all rate datapoints
	*/
	function setOracleRate(int128 _rate) external {
		require(CanSetOracleRate);

		uint8 numLarger;
		uint8 numEqual;
		for (uint8 i = 0; i < LENGTH_RATE_SERIES; i++) {
			if (impliedRates[i] > _rate) {
				numLarger++;
			}
			else if (impliedRates[i] == _rate) {
				numEqual++;
			}
		}
		uint8 numSmaller = LENGTH_RATE_SERIES - numEqual - numLarger;
		require(numLarger+numEqual >= numSmaller);
		require(numSmaller+numEqual >= numLarger);

		OracleRate = _rate;
		CanSetOracleRate = false;
		anchor = nextAnchor;
		toSet = 0;
	}

	/*
		@Description: get the implied APY of this amm

		@return int128 APY: the implied APY of this amm
	*/
	function getAPYFromOracle() external view override returns (int128 APY) {
		/*
			APY == getRateFromOracle()**(1 year / anchor)
			APY == exp2 ( log 2 ( getRateFromOracle()**(1 year / anchor)))
			APY == exp2 ( (1 year / anchor) * log 2 ( getRateFromOracle()))
		*/
		APY = OracleRate;
		int128 _1overAnchor = int128((SecondsPerYear << 64) / anchor);
		APY = APY.log_2().mul(_1overAnchor).exp_2();
	}

	/*
		@Description: get all rate datapoints and the timestamps at which they were recorded
	*/
	function getImpliedRateData() external view override returns (
		int128[LENGTH_RATE_SERIES] memory _impliedRates,
		uint[LENGTH_RATE_SERIES] memory _timestamps
		) {
		_impliedRates = impliedRates;
		_timestamps = timestamps;
	}

	/*
		@Description: as time goes on interest is accrued in the AMM and there is also a slow
			drift in the amm curve such that liquidity is provided at negative rates
			this function corrects this such that all liqudity provision starts at an APY of 0
			this is done by rescaling time in this amm by updating the value of anchor

		@param uint lowerBoundAnchor: the proposed lower bound of the new anchor
		@param uint upperBoundAnchor: the proposed upper bound of the new anchor
			must be within 30 seconds of lowerBoundAnchor
	*/
	function recalibrate(uint lowerBoundAnchor, uint upperBoundAnchor) external override {
		require(block.timestamp > 1 days + lastRecalibration);
		require(nextAnchor == anchor);
		require(toSet == 0);

		uint _ZCBreserves = ZCBreserves;
		uint _Ureserves = Ureserves;

		uint prevRatio = _ZCBreserves.add(_inflatedTotalSupply()).mul(1 ether).div(_Ureserves);

		int128 prevAnchor = int128(anchor << 64);
		int128 secondsRemaining = int128(( maturity - wrapper.lastUpdate() ) << 64);
		uint newZCBreserves;
		uint newUreserves;
		{
			uint amtZCB = IERC20(ZCBaddress).balanceOf(address(this));
			uint amtYT = IYieldToken(YTaddress).balanceOf_2(address(this), false);

			uint incZCB = amtZCB.sub(_ZCBreserves).sub(_Ureserves);
			uint incYT = amtYT.sub(_Ureserves);

			if (incYT > incZCB) {
				//transfer excess YT growth to the fee oracle sendTo address this will only happen
				//if someone makes a direct transfer of YT to this contract thus the natural yield
				//generated by funds in the amm will never be transfered out
				IYieldToken(YTaddress).transfer_2(AmmInfoOracle(AmmInfoOracleAddress).sendTo(), incYT-incZCB, false);
				amtYT -= incYT - incZCB;
			}
			newUreserves = amtYT;
			newZCBreserves = amtZCB.sub(amtYT);
		}
		require(newUreserves != 0 && newZCBreserves >> 192 == 0);
		uint effectiveTotalSupply = BigMath.ZCB_U_recalibration(
			prevRatio,
			prevAnchor,
			secondsRemaining,
			lowerBoundAnchor,
			upperBoundAnchor,
			newZCBreserves,
			newUreserves
		);
		/*
			effectiveTotalSupply == totalSupply * LPTokenInflation
			LPTokenInflation == effectiveTotalSupply / totalSupply
		*/
		LPTokenInflation = effectiveTotalSupply.mul(1 ether).div(totalSupply);
		ZCBreserves = newZCBreserves;
		Ureserves = newUreserves;
		nextAnchor = lowerBoundAnchor.add(upperBoundAnchor) >> 1;
		lastRecalibration = block.timestamp;
		//non utilized reserves will be paid out as dividends to LPs
	}

	//-----------------------o-t-h-e-r---v-i-e-w-s-----------------------------------------------

	/*
		@Description: return valuable info about this contract's reserves and time to maturity
	*/
	function getReserves() external view override returns (uint _Ureserves, uint _ZCBreserves, uint _TimeRemaining) {
		_Ureserves = Ureserves;
		_ZCBreserves = ZCBreserves;
		_TimeRemaining = timeRemaining();
	}

	/*
		@Description: return value of _inflatedTotalSupply externally
	*/
	function inflatedTotalSupply() external view override returns (uint) {
		return _inflatedTotalSupply();
	}


}


