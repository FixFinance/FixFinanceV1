const aToken = artifacts.require("dummyAToken");
const aaveWrapper = artifacts.require("AaveWrapper");
const BigMath = artifacts.require("BigMath");
const capitalHandler = artifacts.require("CapitalHandler");
const yieldToken = artifacts.require("YieldToken");
const yieldTokenDeployer = artifacts.require("YieldTokenDeployer");
const ZCBamm = artifacts.require("ZCBamm");
const FeeOracle = artifacts.require("FeeOracle");

const helper = require("../helper/helper.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10To18BN = (new BN("10")).pow(new BN("18"));
const secondsPerYear = 31556926;

const MaxFee = "125000000"; //12.5% in super basis point format
const _2To64BN = (new BN("2")).pow(new BN("64"));
const AnnualFeeRateBN = _2To64BN.div(new BN("100")); //0.01 or 1% in 64.64 form
const AnnualFeeRateNumber = 0.01;
const DesiredDigitsAccurate = 7;
const ErrorRange = Math.pow(10,-7);

function AmountError(actual, expected) {
	return Math.abs(actual-expected)/expected;
}

contract('ZCBamm', async function(accounts){
	it('before each', async () => {
		aTokenInstance = await aToken.new("aCOIN");
		aaveWrapperInstance = await aaveWrapper.new(aTokenInstance.address);
		BigMathInstance = await BigMath.new();
		yieldTokenDeployerInstance = await yieldTokenDeployer.new();
		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		//maturity is 110 days out
		maturity = timestamp + 110*24*60*60;
		capitalHandlerInstance = await capitalHandler.new(aaveWrapperInstance.address, maturity, yieldTokenDeployerInstance.address, nullAddress);
		yieldTokenInstance = await yieldToken.at(await capitalHandlerInstance.yieldTokenAddress());
		await ZCBamm.link("BigMath", BigMathInstance.address);
		feeOracleInstance = await FeeOracle.new(MaxFee, AnnualFeeRateBN);
		amm = await ZCBamm.new(capitalHandlerInstance.address, feeOracleInstance.address);
		anchor = (await amm.anchor()).toNumber();

		//simulate generation of 100% returns in money market
		await aTokenInstance.setInflation("2"+_10To18BN.toString().substring(1));

		//mint funds to accounts[0]
		balance = _10To18BN;
		await aTokenInstance.approve(aaveWrapperInstance.address, balance);
		await aaveWrapperInstance.depositUnitAmount(accounts[0], balance);
		await aaveWrapperInstance.approve(capitalHandlerInstance.address, balance);
		await capitalHandlerInstance.depositWrappedToken(accounts[0], balance);
		await capitalHandlerInstance.approve(amm.address, balance);
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
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);
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
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);
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
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);
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
		await capitalHandlerInstance.transfer(amm.address, zcbToSend);
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
		let balZCB = parseInt((await capitalHandlerInstance.balanceOf(amm.address)).toString()) * 2**-64;
		let balYT = parseInt((await yieldTokenInstance.balanceOf_2(amm.address, false)).toString()) * 2**-64;
		let U = balYT;
		let Z = balZCB - balYT;
		//let U = parseInt(reserves._Ureserves.toString()) * 2**-64;
		//let Z = parseInt(reserves._ZCBreserves.toString()) * 2**-64;
		let effectiveL = parseInt((await amm.inflatedTotalSupply()).toString());
		let yearsRemaining = (maturity - timestamp) / secondsPerYear;
		let rate = (parseInt(ZCBreserves)+effectiveL) / (parseInt(Ureserves));
		let impliedYield = Math.pow(rate, anchor/secondsPerYear);
		let UpperBound = anchor*10 / secondsPerYear;
		let LowerBound = yearsRemaining;
		let a = (UpperBound+LowerBound) / 2;
		let step = (UpperBound-LowerBound) / 4;
		for (let i = 0; i < 100; i++) {
			let t = yearsRemaining / a;
			let exp = 1.0-t;
			let L = U * Math.pow(impliedYield,1/a) - Z;
			let G = 2*Math.pow(L, exp) - Math.pow(Z+L, exp) - Math.pow(U, exp);
			if (G > 0) {
				LowerBound = a;
				a += step;
			}
			else if (L < 0 || G < 0) {
				UpperBound = a;
				a -= step;
			}
			else {
				if (a === UpperBound) {
					a -= step;
				}
				else {
					a += step;
				}
			}
			step /= 2;
		}
		let L = U * Math.pow(impliedYield,1/a) - Z;
		let t = yearsRemaining / a;
		let exp = 1.0-t;
		let lowerAnchor = Math.floor(LowerBound * secondsPerYear - 1).toString();
		let upperAnchor = Math.ceil(UpperBound * secondsPerYear + 1).toString();
		await amm.recalibrate(lowerAnchor, upperAnchor);

		inflatedTotalSupplyLP = await amm.inflatedTotalSupply();
		nextAnchor = (await amm.nextAnchor()).toNumber();
		assert.isBelow(nextAnchor, parseInt(upperAnchor)+1, "anchor is below upper bound");
		assert.isAbove(nextAnchor, parseInt(lowerAnchor)-1, "anchor is above lower bound");
	});

	it('Valid reserves', async () => {
		let results = await amm.getReserves();
		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();
		let expectedZCB = (await capitalHandlerInstance.balanceOf(amm.address));
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
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()), 1-r);
		let Uout = parseInt(Ureserves) - (k - Math.pow(parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).add(amtIn).toString()), 1-r))**(1/(1-r));
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let UoutFeeAdjusted = Uout * (1 - pctFee);
		let Uexpected = parseInt(Ureserves) - UoutFeeAdjusted;
		let ZCBexpected = parseInt(ZCBreserves) + parseInt(amtIn.toString());

		results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		let expectedBalanceYT = balance.sub(new BN(Ureserves)).toString();
		let expectedBalanceZCB = balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString()
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
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()), 1-r);
		let ZCBout = parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()) - (k - Math.pow( (new BN(Ureserves)).add(amtIn).toString() , 1-r))**(1/(1-r));
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let ZCBoutFeeAdjusted = ZCBout * (1 - pctFee);
		let Uexpected = parseInt(amtIn.add(new BN(Ureserves)).toString());
		let ZCBexpected = parseInt(ZCBreserves) - ZCBoutFeeAdjusted;

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		let expectedBalanceYT = balance.sub(new BN(Ureserves)).toString();
		let expectedBalanceZCB = balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString();
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
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()), 1-r);
		let Uin = (k - Math.pow(parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).sub(amtOut).toString()), 1-r))**(1/(1-r)) - parseInt(Ureserves);
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let UinFeeAdjusted = Uin / (1 - pctFee);
		let Uexpected = parseInt(Ureserves) + UinFeeAdjusted;
		let ZCBexpected = parseInt(ZCBreserves) - parseInt(amtOut.toString());

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		let expectedBalanceYT = balance.sub(new BN(Ureserves)).toString();
		let expectedBalanceZCB = balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString();
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
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString()), 1-r);
		let ZCBin = (k - Math.pow( (new BN(Ureserves)).sub(amtOut).toString() , 1-r))**(1/(1-r)) - parseInt(inflatedTotalSupplyLP.add(new BN(ZCBreserves)).toString());
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let ZCBinFeeAdjusted = ZCBin / (1 - pctFee);
		let ZCBexpected = parseInt(ZCBreserves) + ZCBinFeeAdjusted;
		let Uexpected = parseInt(Ureserves) - parseInt(amtOut.toString());

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.isBelow(AmountError(parseInt(Ureserves), Uexpected), ErrorRange, "Ureserves within error range");
		assert.isBelow(AmountError(parseInt(ZCBreserves), ZCBexpected), ErrorRange, "Ureserves within error range");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		let expectedBalanceYT = balance.sub(new BN(Ureserves)).toString();
		let expectedBalanceZCB = balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString();
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
		for (let i = 4; i < LENGTH_RATE_SERIES; i++) {
			await helper.advanceTime(121);
			rec = await amm.forceRateDataUpdate();
		}
	});

	it('Cannot Change Rate Data, until setOracleRate() is called', async () => {
		await helper.advanceTime(121);

		rateData = await amm.getImpliedRateData();

		let rate0 = rateData._impliedRates[0].toString();
		let ts0 = rateData._timestamps[0].toString();

		await amm.forceRateDataUpdate();

		let newRateData = await amm.getImpliedRateData();
		assert.equal(newRateData._impliedRates[0].toString(), rate0, "rate not updated");
		assert.equal(newRateData._timestamps[0].toString(), ts0, "timestamp not updated");
	});

	it('Cannot set invalid rate', async () => {
		let caught = false;
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
		let expectedZCB = (await capitalHandlerInstance.balanceOf(amm.address));
		let expectedYT = (await yieldTokenInstance.balanceOf_2(amm.address, false));
		assert.equal(ZCBreserves, expectedZCB.sub(expectedYT).toString(), "valid ZCBreserves");
		assert.equal(Ureserves, expectedYT.toString(), "valid Ureserves");
	});

	it('Yield Generation does not affect pool reserves', async () => {
		//simulate generation of yield by sending funds directly to pool address
		amtZCB = balance.div(new BN(1000));
		amtYT = balance.div(new BN(500));
		await capitalHandlerInstance.transfer(amm.address, amtZCB);
		await yieldTokenInstance.transfer_2(amm.address, amtYT, true);

		let results = await amm.getReserves();
		assert.equal(results._Ureserves.toString(), Ureserves, "U reserves not affected by yield generation");
		assert.equal(results._ZCBreserves.toString(), ZCBreserves, "U reserves not affected by yield generation");
	});

});
