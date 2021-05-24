// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../helpers/IYTamm.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/BigMath.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IYieldToken.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IERC20.sol";
import "../../helpers/IZCBamm.sol";
import "../../InfoOracle.sol";

contract YTamm is IYTamm {

	using ABDKMath64x64 for int128;
	using SafeMath for uint256;

	address delegateAddress;


	/*
		Init AMM
	*/
	constructor(
		address _ZCBammAddress,
		address _feeOracleAddress,
		address _delegateAddress
	) public {
		address _FCPaddress = IZCBamm(_ZCBammAddress).FCPaddress();
		address _ZCBaddress = IZCBamm(_ZCBammAddress).ZCBaddress();
		address _YTaddress = IZCBamm(_ZCBammAddress).YTaddress();
		uint64 _maturity = IZCBamm(_ZCBammAddress).maturity();
		require(_maturity > block.timestamp + 10 days);
		int128 apy = IZCBamm(_ZCBammAddress).getAPYFromOracle();
		//YTamm cannot be created until it has a matching ZCBamm from which to get rate information
		require(apy > 0);
		maturity = _maturity;
		ZCBammAddress = _ZCBammAddress;
		InfoOracleAddress = _feeOracleAddress;
		SlippageConstant = InfoOracle(_feeOracleAddress).getSlippageConstant(_FCPaddress);
		wrapper = IFixCapitalPool(_FCPaddress).wrapper();
		YTtoLmultiplier = BigMath.YT_U_ratio(
			apy,
			maturity-block.timestamp
		);
		FCPaddress = _FCPaddress;
		ZCBaddress = _ZCBaddress;
		YTaddress = _YTaddress;
		delegateAddress = _delegateAddress;
		contractZCBDividend.push(0);
		contractYieldDividend.push(0);
	}

	/*
		@Description: mint LP tokens
			minted LP tokens are eligible to start earning interest immediately

		@param address _to: address that shall receive LP tokens
		@param uint _amount: amount of LP tokens to be minted
	*/
	function _firstMint(address _to, uint _amount) internal {
		internalBalanceOf[_to] += _amount;
		activeTotalSupply += _amount;
		internalTotalSupply += _amount;

		emit Mint(_to, _amount);
	}

	/*
		@Description: mint LP tokens
			minted tokens are not eligible to earn interest until next dividend collection

		@param address _to: address that shall receive LP tokens
		@param uint _amount: amount of LP tokens to be minted
	*/
	function _mint(address _to, uint _amount) internal {
        claimDividendInternal(_to, _to);
		ineligibleBalanceOf[_to] += _amount;
		internalTotalSupply += _amount;

		emit Mint(_to, _amount);
	}

	/*
		@Description: burn LP tokens
			first burn ineligible LP tokens that are not earning interest
			next burn LP tokens that are earning interest

		@param address _from: address that is burning LP tokenns
		@param uint _amount: amount of LP tokens to burn
	*/
	function _burn(address _from, uint _amount) internal {
        claimDividendInternal(_from, _from);
		uint _balance = internalBalanceOf[_from];
		uint _ineligibleBalance = ineligibleBalanceOf[_from];
		uint combinedBal = _balance + _ineligibleBalance;
		require(combinedBal >= _amount);
		uint _lastClaim = lastClaim[_from];
		if (_ineligibleBalance < _amount) {
			uint decreaseInterestEarningBalance = _amount - _ineligibleBalance;
			if (_ineligibleBalance != 0) {
				ineligibleBalanceOf[_from] = 0;
			}
			internalBalanceOf[_from] -= decreaseInterestEarningBalance;
			activeTotalSupply -= decreaseInterestEarningBalance;
		}
		else {
			ineligibleBalanceOf[_from] -= _amount;
		}
		internalTotalSupply -= _amount;

		//if _from is earning yield on LP funds then decrement from activeTotalSupply
		uint lastIndex = contractZCBDividend.length-1;
		if (_lastClaim <= lastIndex) {
			activeTotalSupply -= _amount;
		}

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
		@Description: get signature of amm state, useful for when reserving and taking amm quotes

		@param bool _YTin: if the user is getting a quote for sendingYT and receiveing U this will be true

		@return bytes32: signature of amm state
	*/
	function getQuoteSignature(bool _YTin) internal view returns (bytes32) {
		IZCBamm zcbamm = IZCBamm(ZCBammAddress);
		(uint updateTimestamp, uint ratio) = wrapper.getStatus();
		return keccak256(abi.encodePacked(internalTotalSupply, YTreserves, zcbamm.getRateFromOracle(), zcbamm.anchor(), _YTin, updateTimestamp, ratio));
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
		@Description first deposit of liquidity into this contract, internalTotalSupply must be == 0
			pool starts at equilibrim this means the implied rate of the pool is the same as the rate fetched from the oracle
	*/
	function firstMint(uint128 _Uin) external override {
		require(internalTotalSupply == 0);
		uint YTin = YTtoLmultiplier.mul(_Uin) / (1 ether);

		getYT(address(this), _Uin + YTin);
		getZCB(address(this), _Uin);

		_firstMint(msg.sender, _Uin);
		//first mint is a special case where funds are elidgeble for earning interest immediately
		activeTotalSupply = _Uin;

		Ureserves = _Uin;
		YTreserves = YTin;
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
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature('recalibrate(int128)', _approxYTin));
		require(success);
	}

	/*
		@Description: to supply liquidity to this contract this function must be called

		@param uint _amount: the amount of LP tokens to mint
		@param uint _maxUin: the maximum amount of U to deposit as liquidity
		@param uint _maxYTin: the maximum amount of YT to deposit as liquidity
	*/
	function mint(uint _amount, uint _maxUin, uint _maxYTin) external override {
		uint _totalSupply = internalTotalSupply;	//gas savings
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
		uint _totalSupply = internalTotalSupply;	//gas savings
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
			(1 ether)**2 / InfoOracle(InfoOracleAddress).getYTammFeeConstant(FCPaddress),
			OracleRate,
			_amount
		));
		(uint treasuryFee, address sendTo) = InfoOracle(InfoOracleAddress).treasuryFee(nonFeeAdjustedUout, Uout);
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
			InfoOracle(InfoOracleAddress).getYTammFeeConstant(FCPaddress),
			OracleRate,
			-_amount
		));
		(uint treasuryFee, address sendTo) = InfoOracle(InfoOracleAddress).treasuryFee(Uin, nonFeeAdjustedUin);
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
			(1 ether)**2 / InfoOracle(InfoOracleAddress).getYTammFeeConstant(FCPaddress),
			OracleRate,
			_amount
		));
		(uint treasuryFee, ) = InfoOracle(InfoOracleAddress).treasuryFee(nonFeeAdjustedUout, Uout);
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
			InfoOracle(InfoOracleAddress).getYTammFeeConstant(FCPaddress),
			OracleRate,
			-_amount
		));
		(uint treasuryFee, ) = InfoOracle(InfoOracleAddress).treasuryFee(Uin, nonFeeAdjustedUin);
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
		address sendTo = InfoOracle(InfoOracleAddress).sendTo();
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
		(bool success, ) = delegateAddress.delegatecall(abi.encodeWithSignature("contractClaimDividend()"));
		require(success);
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

