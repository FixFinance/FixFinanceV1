const aToken = artifacts.require("dummyAToken");
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapper = artifacts.require("NGBwrapper");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const FCPDelegate2 = artifacts.require('FCPDelegate2');
const fixCapitalPool = artifacts.require("FixCapitalPool");
const yieldToken = artifacts.require("IYieldToken");
const zeroCouponBond = artifacts.require("IZeroCouponBond");
const zcbYtDeployer = artifacts.require("ZCB_YT_Deployer");
const ZCBamm = artifacts.require("ZCBamm");
const InfoOracle = artifacts.require("InfoOracle");

const helper = require("../helper/helper.js");
const ZCBammMath = require("../helper/ZCB-U-Math.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10To18BN = (new BN("10")).pow(new BN("18"));
const secondsPerYear = 31556926;

const BipsToTreasury = "1000"; //10% in basis point format
const SlippageConstant = "0";
const ZCBammFeeConstant = _10To18BN.mul(new BN(105)).div(new BN(100));
const YTammFeeConstant = _10To18BN;
const fZCBin = 1.05;
const fToZCB = 1/fZCBin;
const TreasuryFeeNumber = 0.1;
const _2To64BN = (new BN("2")).pow(new BN("64"));
const DesiredDigitsAccurate = 7;
const ErrorRange = Math.pow(10,-7);
const TreasuryErrorRange = Math.pow(10, -5);
const SBPSretained = 999_000;

function AmountError(actual, expected) {
	actual = parseInt(actual);
	expected = parseInt(expected);
	if (actual === expected) {
		return 0;
	}
	else if (actual === 0 || expected === 0) {
		return 1.0;
	}
	return Math.abs(actual-expected)/expected;
}

contract('ZCBamm', async function(accounts){
	it('before each', async () => {
		aTokenInstance = await aToken.new("aCOIN");
		infoOracleInstance = await InfoOracle.new(BipsToTreasury, nullAddress, true);
		ngbwDelegate1Instance = await NGBwrapperDelegate1.new();
		ngbwDelegate2Instance = await NGBwrapperDelegate2.new();
		ngbwDelegate3Instance = await NGBwrapperDelegate3.new();
		NGBwrapperInstance = await NGBwrapper.new(
			aTokenInstance.address,
			infoOracleInstance.address,
			ngbwDelegate1Instance.address,
			ngbwDelegate2Instance.address,
			ngbwDelegate3Instance.address,
			SBPSretained
		);
		EiInstance = await Ei.new();
		await BigMath.link("Ei", EiInstance.address);
		BigMathInstance = await BigMath.new();
		zcbYtDeployerInstance = await zcbYtDeployer.new();
		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		//maturity is 110 days out
		maturity = timestamp + 110*24*60*60;
		fcpDelegate1Instance = await FCPDelegate1.new();
		fcpDelegate2Instance = await FCPDelegate2.new();
		fixCapitalPoolInstance = await fixCapitalPool.new(
			NGBwrapperInstance.address,
			maturity,
			zcbYtDeployerInstance.address,
			infoOracleInstance.address,
			fcpDelegate1Instance.address,
			fcpDelegate2Instance.address
		);
		zcbInstance = await zeroCouponBond.at(await fixCapitalPoolInstance.zeroCouponBondAddress());
		yieldTokenInstance = await yieldToken.at(await fixCapitalPoolInstance.yieldTokenAddress());
		await ZCBamm.link("BigMath", BigMathInstance.address);
		await infoOracleInstance.setSlippageConstant(fixCapitalPoolInstance.address, SlippageConstant);
		await infoOracleInstance.setAmmFeeConstants(fixCapitalPoolInstance.address, ZCBammFeeConstant, YTammFeeConstant);
		amm = await ZCBamm.new(fixCapitalPoolInstance.address, infoOracleInstance.address);
		anchor = (await amm.anchor()).toNumber();

		//simulate generation of 100% returns in money market
		await aTokenInstance.setInflation("2"+_10To18BN.toString().substring(1));

		//mint funds to accounts[0]
		balance = _10To18BN;
		await aTokenInstance.approve(NGBwrapperInstance.address, balance);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], balance);
		await NGBwrapperInstance.approve(fixCapitalPoolInstance.address, balance);
		await fixCapitalPoolInstance.depositWrappedToken(accounts[0], balance);
		await zcbInstance.approve(amm.address, balance);
		await yieldTokenInstance.approve(amm.address, balance);

	});

	it('make first deposit in amm', async () => {
		Uin = balance.div(new BN("10"));
		ZCBin = balance.div(new BN("10"));
		rec = await amm.firstMint(Uin, ZCBin);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = 2 * Math.pow(parseInt(Uin.toString()), 1-r);
		let Uout = parseInt(Uin.toString()) - (k - Math.pow(parseInt(ZCBin.toString()) + parseInt(Uin.toString()), 1-r))**(1/(1-r));
		let Uexpected = (parseInt(Uin.toString()) - Uout);
		let ZCBexpected = parseInt(ZCBin.toString());
		let results = await amm.getReserves();
		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		totalSupplyLT = await amm.totalSupply();

		assert.equal(balanceLT.toString(), Uin.toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
		assert.equal(totalSupplyLT.toString(), balanceLT.toString(), "correct total supply of liquidity tokens");
	});

	it('second liquidity token deposit', async () => {
		let maxYTin = Uin;
		let maxZCBin = ZCBin.add(Uin);

		rec = await amm.mint(balanceLT, maxYTin, maxZCBin);

		rateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(rateData._impliedRates[0].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(rateData._timestamps[0].toString(), timestamp.toString(), "correct height stored")

		let Uexpected = parseInt((new BN(Ureserves)).mul(new BN(2)).toString());
		let ZCBexpected = parseInt((new BN(ZCBreserves)).mul(new BN(2)).toString());

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		totalSupplyLT = await amm.totalSupply();

		assert.equal(balanceLT.toString(), Uin.mul(new BN(2)).toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
		assert.equal(totalSupplyLT.toString(), balanceLT.toString(), "correct total supply of liquidity tokens");
	});

	it('burn liquidity tokens', async () => {
		//advance 2 minuite and 1 second so that rate data may be recorded
		await helper.advanceTime(121);

		let toBurn = Uin;

		rec = await amm.burn(toBurn);

		let newRateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData._impliedRates[1].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData._timestamps[1].toString(), timestamp.toString(), "correct height stored")

		rateData = newRateData;

		let Uexpected = parseInt((new BN(Ureserves)).div(new BN(2)).toString());
		let ZCBexpected = parseInt((new BN(ZCBreserves)).div(new BN(2)).toString());

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		totalSupplyLT = await amm.totalSupply();

		assert.equal(balanceLT.toString(), Uin.toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
		assert.equal(totalSupplyLT.toString(), balanceLT.toString(), "correct total supply of liquidity tokens");
	});

	it('recalibrate curve', async () => {
		const LENGTH_RATE_SERIES = 31;
		for (let i = 1; i < LENGTH_RATE_SERIES; i++) {
			await helper.advanceTime(121);
			rec = await amm.forceRateDataUpdate();
		}
		await amm.setOracleRate((await amm.getImpliedRateData())._impliedRates[LENGTH_RATE_SERIES-1].toString());
		/*
			Send some ZCB and some YT to the contract to see if recalibration can fit reserves to match balances
		*/
		let zcbToSend = (new BN(ZCBreserves)).div(new BN(15));
		let ytToSend = (new BN(Ureserves)).div(new BN(34));
		await zcbInstance.transfer(amm.address, zcbToSend);
		await yieldTokenInstance.transfer(amm.address, ytToSend);

		//advance time 6 weeks so that we may recalibrate
		const _6weeks = 6 * 7 * 24 * 60 * 60;
		await helper.advanceTimeAndBlock(_6weeks);
		/*
			When time passes there is a gradual drift in the curve such that some liquidity
			provision is at negative rates thus we need to be able to recalibrate to amm to
			fix this
		*/
		inflatedTotalSupplyLP = await amm.inflatedTotalSupply();

		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		let reserves = await amm.getReserves();
		let balZCB = parseInt((await zcbInstance.balanceOf(amm.address)).toString()) * 2**-64;
		let balYT = parseInt((await yieldTokenInstance.balanceOf_2(amm.address, false)).toString()) * 2**-64;
		let U = balYT;
		let Z = balZCB - balYT;
		//let U = parseInt(reserves._Ureserves.toString()) * 2**-64;
		//let Z = parseInt(reserves._ZCBreserves.toString()) * 2**-64;
		let effectiveL = parseInt((await amm.inflatedTotalSupply()).toString());
		let secondsRemaining = maturity - timestamp;
		let rate = (parseInt(ZCBreserves)+effectiveL) / (parseInt(Ureserves));
		let impliedYield = Math.pow(rate, secondsRemaining/anchor);
		let UpperBound = anchor*10;
		let LowerBound = secondsRemaining;
		let a = (UpperBound+LowerBound) / 2;
		let step = (UpperBound-LowerBound) / 4;
		for (let i = 0; i < 100; i++) {
			let t = secondsRemaining / a;
			let exp = 1.0-t;
			let L = U * Math.pow(impliedYield, 1/t) - Z;
			let G = 2*Math.pow(L, exp) - Math.pow(Z+L, exp) - Math.pow(U, exp);
			if (G > 0) {
				LowerBound = a;
				a -= step;
			}
			else if (L < 0 || G < 0) {
				UpperBound = a;
				a += step;
			}
			else {
				if (a === UpperBound) {
					a += step;
				}
				else {
					a -= step;
				}
			}
			step /= 2;
		}
		let t = secondsRemaining / a;
		let L = U * Math.pow(impliedYield, 1/t) - Z;
		let exp = 1.0-t;
		let lowerAnchor = Math.floor(LowerBound - 1).toString();
		let upperAnchor = Math.ceil(UpperBound + 1).toString();
		await amm.recalibrate(lowerAnchor, upperAnchor);

		inflatedTotalSupplyLP = await amm.inflatedTotalSupply();
		let inflatedTotalSupplyLPNum = parseInt(inflatedTotalSupplyLP.toString());
		let expectedInflatedTotalSupply = L * Math.pow(2, 64);
		nextAnchor = (await amm.nextAnchor()).toNumber();
		assert.isBelow(nextAnchor, parseInt(upperAnchor)+1, "anchor is below upper bound");
		assert.isAbove(nextAnchor, parseInt(lowerAnchor)-1, "anchor is above lower bound");
		assert.isBelow(AmountError(expectedInflatedTotalSupply, inflatedTotalSupplyLPNum), ErrorRange, "inflatedTotalSupply is within the acceptable margin of error");
	});

	it('Valid reserves', async () => {
		let results = await amm.getReserves();
		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();
		let expectedZCB = (await zcbInstance.balanceOf(amm.address));
		let expectedYT = (await yieldTokenInstance.balanceOf_2(amm.address, false));
		assert.equal(ZCBreserves, expectedZCB.sub(expectedYT).toString(), "valid ZCBreserves");
		assert.equal(Ureserves, expectedYT.toString(), "valid Ureserves");
	});

	it('SwapFromSpecificTokens _ZCBin:true', async () => {
		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		await helper.advanceTime(121);

		amtIn = balance.div(new BN(100));

		rec = await amm.SwapFromSpecificTokens(amtIn, true);

		let newRateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(inflatedTotalSupplyLP).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData._impliedRates[0].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData._timestamps[0].toString(), timestamp.toString(), "correct height stored")

		rateData = newRateData;

		let r = (maturity-timestamp)/nextAnchor;

		let Uout = -ZCBammMath.reserveChange(
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			parseInt(Ureserves),
			r,
			1.0,
			parseInt(amtIn.toString())
		);

		let UoutFeeAdjusted = -ZCBammMath.reserveChange(
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			parseInt(Ureserves),
			r,
			fZCBin,
			parseInt(amtIn.toString())
		);
		let totalFee = Uout - UoutFeeAdjusted;
		let treasuryFee = Math.floor(totalFee * TreasuryFeeNumber);
		let Uexpected = parseInt(Ureserves) - UoutFeeAdjusted - treasuryFee;
		let ZCBexpected = parseInt(ZCBreserves) + parseInt(amtIn.toString());

		results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		balanceTreasuryZCB = (await zcbInstance.balanceOf(nullAddress)).toString();
		balanceTreasuryYT = (await yieldTokenInstance.balanceOf_2(nullAddress, false)).toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		assert.isBelow(AmountError(parseInt(balanceTreasuryZCB), treasuryFee), TreasuryErrorRange, "treasury ZCB balance within error range");
		assert.isBelow(AmountError(parseInt(balanceTreasuryYT), treasuryFee), TreasuryErrorRange, "treasury YT balance within error range");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);

		expectedBalanceYT = balance.sub(new BN(Ureserves)).sub(new BN(balanceTreasuryYT)).toString();
		expectedBalanceZCB = balance.sub(new BN(ZCBreserves)).sub(new BN(Ureserves)).sub(new BN(balanceTreasuryZCB)).toString();
		assert.equal(balanceLT.toString(), Uin.toString());
		assert.equal(balanceYT.toString(), expectedBalanceYT, "correct balance YT");
		assert.equal(balanceZCB.toString(), expectedBalanceZCB, "correct balance ZCB");
	});

	it('SwapFromSpecificTokens _ZCBin:false', async () => {
		await helper.advanceTime(121);

		amtIn = balance.div(new BN(100));

		rec = await amm.SwapFromSpecificTokens(amtIn, false);

		let newRateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(inflatedTotalSupplyLP).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData._impliedRates[1].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData._timestamps[1].toString(), timestamp.toString(), "correct height stored")
		rateData = newRateData;

		let r = (maturity-timestamp)/nextAnchor;
		let ZCBout = -ZCBammMath.reserveChange(
			parseInt(Ureserves),
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			r,
			1.0,
			parseInt(amtIn.toString())
		);

		let ZCBoutFeeAdjusted = -ZCBammMath.reserveChange(
			parseInt(Ureserves),
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			r,
			fToZCB,
			parseInt(amtIn.toString())
		);
		let totalFee = ZCBout - ZCBoutFeeAdjusted;
		let treasuryFee = Math.floor(totalFee * TreasuryFeeNumber);
		let Uexpected = parseInt(amtIn.add(new BN(Ureserves)).toString());
		let ZCBexpected = parseInt(ZCBreserves) - ZCBoutFeeAdjusted - treasuryFee;

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		let prevTreasuryZCB = balanceTreasuryZCB;
		let prevTreasuryYT = balanceTreasuryYT;
		balanceTreasuryZCB = (await zcbInstance.balanceOf(nullAddress)).toString();
		balanceTreasuryYT = (await yieldTokenInstance.balanceOf_2(nullAddress, false)).toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		assert.isBelow(AmountError(parseInt((new BN(balanceTreasuryZCB)).sub(new BN(prevTreasuryZCB))), treasuryFee), TreasuryErrorRange, "treasury ZCB balance within error range");
		assert.equal(balanceTreasuryYT, prevTreasuryYT, "treasury YT balance unchanged");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);

		expectedBalanceYT = balance.sub(new BN(Ureserves)).sub(new BN(balanceTreasuryYT)).toString();
		expectedBalanceZCB = balance.sub(new BN(ZCBreserves)).sub(new BN(Ureserves)).sub(new BN(balanceTreasuryZCB)).toString();
		assert.equal(balanceYT.toString(), expectedBalanceYT, "correct balance YT");
		assert.equal(balanceZCB.toString(), expectedBalanceZCB, "correct balance ZCB");
	});

	it('SwapToSpecificTokens _ZCBin:false', async () => {
		await helper.advanceTime(121);

		let amtOut = balance.div(new BN(100));

		rec = await amm.SwapToSpecificTokens(amtOut, false);

		let newRateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(inflatedTotalSupplyLP).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData._impliedRates[2].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData._timestamps[2].toString(), timestamp.toString(), "correct height stored")
		rateData = newRateData;

		let r = (maturity-timestamp)/nextAnchor;
		let Uin = ZCBammMath.reserveChange(
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			parseInt(Ureserves),
			r,
			1.0,
			-parseInt(amtOut.toString())
		);
		let UinFeeAdjusted = ZCBammMath.reserveChange(
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			parseInt(Ureserves),
			r,
			fToZCB,
			-parseInt(amtOut.toString())
		);
		let totalFee = UinFeeAdjusted - Uin;
		let treasuryFee = Math.floor(totalFee * TreasuryFeeNumber);
		let Uexpected = parseInt(Ureserves) + UinFeeAdjusted - treasuryFee;
		let ZCBexpected = parseInt(ZCBreserves) - parseInt(amtOut.toString());

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		let prevTreasuryZCB = balanceTreasuryZCB;
		let prevTreasuryYT = balanceTreasuryYT;
		balanceTreasuryZCB = (await zcbInstance.balanceOf(nullAddress)).toString();
		balanceTreasuryYT = (await yieldTokenInstance.balanceOf_2(nullAddress, false)).toString();
		let treasuryZCBchange = (new BN(balanceTreasuryZCB)).sub(new BN(prevTreasuryZCB)).toString();
		let treasuryYTchange = (new BN(balanceTreasuryYT)).sub(new BN(prevTreasuryYT)).toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		assert.isBelow(AmountError(parseInt(treasuryZCBchange), treasuryFee), TreasuryErrorRange, "treasury ZCB balance within error range");
		assert.isBelow(AmountError(parseInt(treasuryYTchange), treasuryFee), TreasuryErrorRange, "treasury YT balance within error range");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);

		expectedBalanceYT = balance.sub(new BN(Ureserves)).sub(new BN(balanceTreasuryYT)).toString();
		expectedBalanceZCB = balance.sub(new BN(ZCBreserves)).sub(new BN(Ureserves)).sub(new BN(balanceTreasuryZCB)).toString();

		assert.equal(balanceYT.toString(), expectedBalanceYT, "correct balance YT");
		assert.equal(balanceZCB.toString(), expectedBalanceZCB, "correct balance ZCB");
	});

	it('SwapToSpecificTokens _ZCBin:true', async () => {
		await helper.advanceTime(121);

		let amtOut = balance.div(new BN(100));

		rec = await amm.SwapToSpecificTokens(amtOut, true);

		let newRateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(inflatedTotalSupplyLP).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData._impliedRates[3].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData._timestamps[3].toString(), timestamp.toString(), "correct height stored");
		rateData = newRateData;

		let r = (maturity-timestamp)/nextAnchor;
		let ZCBin = ZCBammMath.reserveChange(
			parseInt(Ureserves),
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			r,
			1.0,
			-parseInt(amtOut.toString())
		);

		let ZCBinFeeAdjusted = ZCBammMath.reserveChange(
			parseInt(Ureserves),
			parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()),
			r,
			fZCBin,
			-parseInt(amtOut.toString())
		);
		let totalFee = ZCBinFeeAdjusted - ZCBin;
		let treasuryFee = Math.floor(totalFee * TreasuryFeeNumber);
		let ZCBexpected = parseInt(ZCBreserves) + ZCBinFeeAdjusted - treasuryFee;
		let Uexpected = parseInt(Ureserves) - parseInt(amtOut.toString());

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		let prevTreasuryZCB = balanceTreasuryZCB;
		let prevTreasuryYT = balanceTreasuryYT;
		balanceTreasuryZCB = (await zcbInstance.balanceOf(nullAddress)).toString();
		balanceTreasuryYT = (await yieldTokenInstance.balanceOf_2(nullAddress, false)).toString();
		let treasuryZCBchange = (new BN(balanceTreasuryZCB)).sub(new BN(prevTreasuryZCB)).toString();
		let treasuryYTchange = (new BN(balanceTreasuryYT)).sub(new BN(prevTreasuryYT)).toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		assert.isBelow(AmountError(parseInt((new BN(balanceTreasuryZCB)).sub(new BN(prevTreasuryZCB))), treasuryFee), TreasuryErrorRange, "treasury ZCB balance within error range");
		assert.equal(balanceTreasuryYT, prevTreasuryYT, "treasury YT balance unchanged");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);

		expectedBalanceYT = balance.sub(new BN(Ureserves)).sub(new BN(balanceTreasuryYT)).toString();
		expectedBalanceZCB = balance.sub(new BN(ZCBreserves)).sub(new BN(Ureserves)).sub(new BN(balanceTreasuryZCB)).toString();
		assert.equal(balanceYT.toString(), expectedBalanceYT, "correct balance YT");
		assert.equal(balanceZCB.toString(), expectedBalanceZCB, "correct balance ZCB");
	});

	it('Force Update Rate Data', async () => {
		await helper.advanceTime(121);
		rec = await amm.forceRateDataUpdate();

		let newRateData = await amm.getImpliedRateData();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		expectedNewRate = (new BN(ZCBreserves)).add(inflatedTotalSupplyLP).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData._impliedRates[4].toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData._timestamps[4].toString(), timestamp.toString(), "correct height stored")

		rateData = newRateData;
	});

	it('Fill Out Rate Data arrays', async () => {
		const LENGTH_RATE_SERIES = 31;
		for (let i = 5; i < LENGTH_RATE_SERIES; i++) {
			await helper.advanceTime(121);
			rec = await amm.forceRateDataUpdate();
		}
	});

	it('Cannot set invalid rate', async () => {
		let caught = false;
		rateData = await amm.getImpliedRateData();
		validRate = rateData._impliedRates[6].toString();
		invalidRate = rateData._impliedRates[0].toString();
		try {
			await amm.setOracleRate(invalidRate);
		} catch {
			caught = true;
		}
		if (!caught) {
			assert.fail('Error: invalid rate was sucessfully set in the ZCBamm');
		}
	});

	it('Set valid rate', async () => {
		await amm.setOracleRate(validRate);
		assert.equal((await amm.getRateFromOracle()).toString(), validRate, "rate sucessfully set");
	});

	it('Returns correct APY getAPYFromOracle()', async () => {
		expectedAPY = (Math.pow(parseInt(validRate) * Math.pow(2, -64), secondsPerYear/nextAnchor) * Math.pow(2, 64)).toLocaleString('fullwide', {useGrouping: false});
		result = (await amm.getAPYFromOracle()).toString();
		assert.equal(result.length, expectedAPY.length, "result has same length of characters as expected result");
		assert.equal(result.substring(0, 10), expectedAPY.substring(0, 10), "first 10 digits of expected and result are the same");
	});

	it('Change Rate Data, after setOracleRate() is called', async () => {
		await helper.advanceTime(121);

		rateData = await amm.getImpliedRateData();

		let rate0 = rateData._impliedRates[0].toString();
		let ts0 = rateData._timestamps[0].toString();

		await amm.forceRateDataUpdate();

		let newRateData = await amm.getImpliedRateData();
		assert.notEqual(newRateData._impliedRates[0].toString(), rate0, "rate is updated");
		assert.notEqual(newRateData._timestamps[0].toString(), ts0, "timestamp is updated");
	});

	it('Valid reserves', async () => {
		let expectedZCB = (await zcbInstance.balanceOf(amm.address));
		let expectedYT = (await yieldTokenInstance.balanceOf_2(amm.address, false));
		assert.equal(ZCBreserves, expectedZCB.sub(expectedYT).toString(), "valid ZCBreserves");
		assert.equal(Ureserves, expectedYT.toString(), "valid Ureserves");
	});

	it('Yield Generation does not affect pool reserves', async () => {
		//simulate generation of yield by sending funds directly to pool address
		amtZCB = balance.div(new BN(1000));
		amtYT = balance.div(new BN(500));
		await zcbInstance.transfer(amm.address, amtZCB);
		await yieldTokenInstance.transfer_2(amm.address, amtYT, true);

		let results = await amm.getReserves();
		assert.equal(results._Ureserves.toString(), Ureserves, "U reserves not affected by yield generation");
		assert.equal(results._ZCBreserves.toString(), ZCBreserves, "U reserves not affected by yield generation");
	});

});
