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

contract('ZCBamm', async function(accounts){
	it('before each', async () => {
		aTokenInstance = await aToken.new();
		aaveWrapperInstance = await aaveWrapper.new(aTokenInstance.address);
		BigMathInstance = await BigMath.new();
		yieldTokenDeployerInstance = await yieldTokenDeployer.new();
		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		//maturity is 11 days out
		maturity = timestamp + 11*24*60*60;
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
		await aaveWrapperInstance.deposit(accounts[0], balance);
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
		let Uexpected = (parseInt(Uin.toString()) - Uout).toString();
		let ZCBexpected = parseInt(ZCBin.toString()).toString();
		let results = await amm.getReserves();
		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();
		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 7 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 7 digits");

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
		let maxUin = Uin;
		let maxZCBin = ZCBin;

		rec = await amm.mint(balanceLT, maxUin, maxZCBin);

		rateData = await amm.getImpliedRateData();

		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(rateData.impliedRate0.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(rateData.height0.toString(), rec.receipt.blockNumber.toString(), "correct height stored")

		let Uexpected = (new BN(Ureserves)).mul(new BN(2)).toString();
		let ZCBexpected = (new BN(ZCBreserves)).mul(new BN(2)).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 7 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 7 digits");

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
		let toBurn = Uin;

		rec = await amm.burn(toBurn);

		let newRateData = await amm.getImpliedRateData();
		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData.impliedRate1.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData.height1.toString(), rec.receipt.blockNumber.toString(), "correct height stored")
		assert.equal(newRateData.impliedRate0.toString(), rateData.impliedRate0.toString(), "correct rate");
		assert.equal(newRateData.height0.toString(), rateData.height0.toString(), "correct height");
		assert.equal(newRateData.impliedRate2.toString(), rateData.impliedRate2.toString(), "correct rate");
		assert.equal(newRateData.height2.toString(), rateData.height2.toString(), "correct height");
		rateData = newRateData;

		let Uexpected = (new BN(Ureserves)).div(new BN(2)).toString();
		let ZCBexpected = (new BN(ZCBreserves)).div(new BN(2)).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 10 digits");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);
		totalSupplyLT = await amm.totalSupply();

		assert.equal(balanceLT.toString(), Uin.toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
		assert.equal(totalSupplyLT.toString(), balanceLT.toString(), "correct total supply of liquidity tokens");
	});

	it('SwapFromSpecificTokens _ZCBin:true', async () => {
		amtIn = balance.div(new BN(100));

		rec = await amm.SwapFromSpecificTokens(amtIn, true);

		let newRateData = await amm.getImpliedRateData();
		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData.impliedRate2.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData.height2.toString(), rec.receipt.blockNumber.toString(), "correct height stored")
		assert.equal(newRateData.impliedRate0.toString(), rateData.impliedRate0.toString(), "correct rate");
		assert.equal(newRateData.height0.toString(), rateData.height0.toString(), "correct height");
		assert.equal(newRateData.impliedRate1.toString(), rateData.impliedRate1.toString(), "correct rate");
		assert.equal(newRateData.height1.toString(), rateData.height1.toString(), "correct height");
		rateData = newRateData;

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let Uout = parseInt(Ureserves) - (k - Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).add(amtIn).toString()), 1-r))**(1/(1-r));
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let UoutFeeAdjusted = Uout * (1 - pctFee);
		let Uexpected = (parseInt(Ureserves) - UoutFeeAdjusted).toString();
		let ZCBexpected = (parseInt(ZCBreserves) + parseInt(amtIn.toString())).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 7 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 7 digits");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceLT.toString(), Uin.toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('SwapFromSpecificTokens _ZCBin:false', async () => {
		amtIn = balance.div(new BN(100));

		rec = await amm.SwapFromSpecificTokens(amtIn, false);

		let newRateData = await amm.getImpliedRateData();
		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData.impliedRate0.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData.height0.toString(), rec.receipt.blockNumber.toString(), "correct height stored")
		assert.equal(newRateData.impliedRate1.toString(), rateData.impliedRate1.toString(), "correct rate");
		assert.equal(newRateData.height1.toString(), rateData.height1.toString(), "correct height");
		assert.equal(newRateData.impliedRate2.toString(), rateData.impliedRate2.toString(), "correct rate");
		assert.equal(newRateData.height2.toString(), rateData.height2.toString(), "correct height");
		rateData = newRateData;

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let ZCBout = parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()) - (k - Math.pow( (new BN(Ureserves)).add(amtIn).toString() , 1-r))**(1/(1-r));
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let ZCBoutFeeAdjusted = ZCBout * (1 - pctFee);
		let Uexpected = amtIn.add(new BN(Ureserves)).toString();
		let ZCBexpected = (parseInt(ZCBreserves) - ZCBoutFeeAdjusted).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('SwapToSpecificTokens _ZCBin:false', async () => {
		let amtOut = balance.div(new BN(100));

		rec = await amm.SwapToSpecificTokens(amtOut, false);

		let newRateData = await amm.getImpliedRateData();
		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData.impliedRate1.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData.height1.toString(), rec.receipt.blockNumber.toString(), "correct height stored")
		assert.equal(newRateData.impliedRate0.toString(), rateData.impliedRate0.toString(), "correct rate");
		assert.equal(newRateData.height0.toString(), rateData.height0.toString(), "correct height");
		assert.equal(newRateData.impliedRate2.toString(), rateData.impliedRate2.toString(), "correct rate");
		assert.equal(newRateData.height2.toString(), rateData.height2.toString(), "correct height");
		rateData = newRateData;

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let Uin = (k - Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).sub(amtOut).toString()), 1-r))**(1/(1-r)) - parseInt(Ureserves);
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let UinFeeAdjusted = Uin / (1 - pctFee);
		let Uexpected = (parseInt(Ureserves) + UinFeeAdjusted).toString()
		let ZCBexpected = (parseInt(ZCBreserves) - parseInt(amtOut.toString())).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('SwapToSpecificTokens _ZCBin:true', async () => {
		let amtOut = balance.div(new BN(100));

		rec = await amm.SwapToSpecificTokens(amtOut, true);

		let newRateData = await amm.getImpliedRateData();
		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData.impliedRate2.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData.height2.toString(), rec.receipt.blockNumber.toString(), "correct height stored")
		assert.equal(newRateData.impliedRate0.toString(), rateData.impliedRate0.toString(), "correct rate");
		assert.equal(newRateData.height0.toString(), rateData.height0.toString(), "correct height");
		assert.equal(newRateData.impliedRate1.toString(), rateData.impliedRate1.toString(), "correct rate");
		assert.equal(newRateData.height1.toString(), rateData.height1.toString(), "correct height");
		rateData = newRateData;

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let ZCBin = (k - Math.pow( (new BN(Ureserves)).sub(amtOut).toString() , 1-r))**(1/(1-r)) - parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString());
		let yearsRemaining = (maturity - timestamp)/secondsPerYear;
		let pctFee = 1 - Math.pow(1 - AnnualFeeRateNumber, yearsRemaining);
		let ZCBinFeeAdjusted = ZCBin / (1 - pctFee);
		let ZCBexpected = (parseInt(ZCBreserves) + ZCBinFeeAdjusted).toString();
		let Uexpected = (parseInt(Ureserves) - parseInt(amtOut.toString())).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, DesiredDigitsAccurate), Uexpected.substring(0, DesiredDigitsAccurate), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, DesiredDigitsAccurate), ZCBexpected.substring(0, DesiredDigitsAccurate), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('Force Update Rate Data', async () => {
		rec = await amm.forceRateDataUpdate();

		let newRateData = await amm.getImpliedRateData();
		expectedNewRate = (new BN(ZCBreserves)).add(totalSupplyLT).mul( (new BN(2)).pow(new BN(64)) ).div(new BN(Ureserves));
		assert.equal(newRateData.impliedRate0.toString(), expectedNewRate.toString(), "correct rate stored");
		assert.equal(newRateData.height0.toString(), rec.receipt.blockNumber.toString(), "correct height stored")
		assert.equal(newRateData.impliedRate1.toString(), rateData.impliedRate1.toString(), "correct rate");
		assert.equal(newRateData.height1.toString(), rateData.height1.toString(), "correct height");
		assert.equal(newRateData.impliedRate2.toString(), rateData.impliedRate2.toString(), "correct rate");
		assert.equal(newRateData.height2.toString(), rateData.height2.toString(), "correct height");
		rateData = newRateData;
	});


	it('Valid reserves', async () => {
		let balZCB = await capitalHandlerInstance.balanceOf(amm.address);
		let balYT = await yieldTokenInstance.balanceOf_2(amm.address, false);
		assert.equal(Ureserves, balYT.toString(), "valid Ureserves");
		assert.equal(ZCBreserves, balZCB.sub(balYT).toString(), "valid ZCBreserves");
	});

	it('Yield Generation does not affect pool reserves before contract claim dividend', async () => {
		//simulate generation of yield by sending funds directly to pool address
		amtZCB = balance.div(new BN(1000));
		amtYT = balance.div(new BN(500));
		await capitalHandlerInstance.transfer(amm.address, amtZCB);
		await yieldTokenInstance.transfer_2(amm.address, amtYT, true);

		let results = await amm.getReserves();
		assert.equal(results._Ureserves.toString(), Ureserves, "U reserves not affected by yield generation");
		assert.equal(results._ZCBreserves.toString(), ZCBreserves, "U reserves not affected by yield generation");
	});

	it('Contract Claim Dividend', async () => {
		await amm.contractClaimDividend();

		assert.equal((await amm.length()).toString(), "2");
		assert.equal((await amm.contractBalanceAsset1(1)).toString(), amtZCB.toString());
		assert.equal((await amm.contractBalanceAsset2(1)).toString(), amtYT.toString());
	})

	it('Yield Generation does not affect pool reserves after contract claim dividend', async () => {
		let results = await amm.getReserves();
		assert.equal(results._Ureserves.toString(), Ureserves, "U reserves not affected by yield generation");
		assert.equal(results._ZCBreserves.toString(), ZCBreserves, "U reserves not affected by yield generation");
	});

	it('User Claims Generated Yield', async () => {
		rec = await amm.claimDividend(accounts[1]);
		let event = rec.logs[2].args;
		assert.equal(event._claimer.toString(), accounts[0]);
		assert.equal(event._to.toString(), accounts[1]);
		assert.equal(event._amtZCB.toString(), amtZCB.toString());
		assert.equal(event._amtYT.toString(), amtYT.toString());
	});

	it('ClaimContract Dividend After Dividend Payouts', async () => {
		//advance 1 day and 1 second
		await helper.advanceTime(1 + 24*60*60);

		amtZCB2 = amtZCB.div(new BN(2));
		amtYT2 = amtYT.div(new BN(5));

		await capitalHandlerInstance.transfer(amm.address, amtZCB2);
		await yieldTokenInstance.transfer_2(amm.address, amtYT2, true);

		await amm.contractClaimDividend();

		assert.equal((await amm.length()).toString(), "3");
		assert.equal((await amm.contractBalanceAsset1(2)).toString(), amtZCB.add(amtZCB2).toString());
		assert.equal((await amm.contractBalanceAsset2(2)).toString(), amtYT.add(amtYT2).toString());
	});

	it('ClaimContract Dividend After Dividend Payouts', async () => {
		//advance 1 day and 1 second
		await helper.advanceTime(1 + 24*60*60);
		let caught = false;
		try {
			await amm.contractClaimDividend();
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('Cannot Call claimContractDividend() when no yield has been generated');
	});


	it('Claims Dividend On transfer() call', async () => {
		balance = await amm.balanceOf(accounts[0]);
		amount = balance.div(new BN(2))
		rec = await amm.transfer(accounts[1], amount);
		/*
			first event is ZCB dividend transfer
			second event is YT dividend transfer
			third event is what we want
			fourth event is transfer of LP tokens
		*/
		let event = rec.logs[2].args;

		assert.equal(event._claimer.toString(), accounts[0]);
		assert.equal(event._to.toString(), accounts[0]);
		assert.equal(event._amtZCB.toString(), amtZCB2.toString());
		assert.equal(event._amtYT.toString(), amtYT2.toString());
	});

	it('Claims Dividend on transferFrom() call', async () => {
		//generate yield for LPs
		await capitalHandlerInstance.transfer(amm.address, amtZCB);
		await yieldTokenInstance.transfer_2(amm.address, amtYT, true);
		await amm.contractClaimDividend();

		await amm.approve(accounts[0], amount, {from: accounts[1]});
		rec = await amm.transferFrom(accounts[1], accounts[0], amount);

		let event = rec.logs[2].args;
		assert.equal(event._claimer.toString(), accounts[1]);
		assert.equal(event._to.toString(), accounts[1]);
		assert.equal(event._amtZCB.toString(), amtZCB.div(new BN(2)).toString());
		assert.equal(event._amtYT.toString(), amtYT.div(new BN(2)).toString());

		event = rec.logs[5].args;
		assert.equal(event._claimer.toString(), accounts[0]);
		assert.equal(event._to.toString(), accounts[0]);
		assert.equal(event._amtZCB.toString(), amtZCB.div(new BN(2)).toString());
		assert.equal(event._amtYT.toString(), amtYT.div(new BN(2)).toString());
	});

	it('Return Median of past 3 rates from getRateFromOracle() call', async () => {
		let first = rateData.impliedRate0;
		let second = rateData.impliedRate1;
		let third = rateData.impliedRate2;
		[first, second] = first.cmp(second) == 1 ? [first, second] : [second, first];
		[second, third] = second.cmp(third) == 1 ? [second, third] : [third, second];
		[first, second] = first.cmp(second) == 1 ? [first, second] : [second, first];
		expectedRate = second.toString();
		assert.equal((await amm.getRateFromOracle()).toString(), expectedRate, "correct rate returned");
	});

	it('Return Correct value from getAPYFromOracle() call', async () => {
		expectedAPY = (Math.pow(parseInt(expectedRate) * Math.pow(2, -64), secondsPerYear/anchor) * Math.pow(2, 64)).toLocaleString('fullwide', {useGrouping: false});
		result = (await amm.getAPYFromOracle()).toString();
		assert.equal(result.length, expectedAPY.length, "result has same length of characters as expected result");
		assert.equal(result.substring(0, 10), expectedAPY.substring(0, 10), "first 10 digits of expected and result are the same");
	});
});
