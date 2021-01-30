const aToken = artifacts.require("dummyAToken");
const aaveWrapper = artifacts.require("AaveWrapper");
const BigMath = artifacts.require("BigMath");
const capitalHandler = artifacts.require("CapitalHandler");
const yieldToken = artifacts.require("YieldToken");
const yieldTokenDeployer = artifacts.require("YieldTokenDeployer");
const ZCBamm = artifacts.require("ZCBamm");
const YTamm = artifacts.require("YTamm");

const helper = require("../helper/helper.js");
const YT_U_math = require("../helper/YT-U-Math.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10To18BN = (new BN("10")).pow(new BN("18"));
const secondsPerYear = 31556926;

/*
	Here we assume that there are no bugs in the ZCBamm contract which is used as a rate oracle for the YTamm contract
*/
contract('YTamm', async function(accounts){
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
		await YTamm.link("BigMath", BigMathInstance.address);
		amm0 = await ZCBamm.new(capitalHandlerInstance.address);
		YTtoLmultiplier = 50;
		amm1 = await YTamm.new(amm0.address, YTtoLmultiplier);
		anchor = (await amm0.anchor()).toNumber();

		//simulate generation of 100% returns in money market
		await aTokenInstance.setInflation("2"+_10To18BN.toString().substring(1));

		//mint funds to accounts[0]
		balance = _10To18BN;
		await aTokenInstance.approve(aaveWrapperInstance.address, balance);
		await aaveWrapperInstance.deposit(accounts[0], balance);
		await aaveWrapperInstance.approve(capitalHandlerInstance.address, balance);
		await capitalHandlerInstance.depositWrappedToken(accounts[0], balance);
		await capitalHandlerInstance.approve(amm0.address, balance);
		await yieldTokenInstance.approve(amm0.address, balance);
		await capitalHandlerInstance.approve(amm1.address, balance);
		await yieldTokenInstance.approve(amm1.address, balance);
		/*
			make first deposit in amm0
		*/
		Uin = balance.div(new BN("10"));
		ZCBin = balance.div(new BN("300"));
		rec = await amm0.firstMint(Uin, ZCBin);
		/*
			now we mint liquidity tokens and then burn to hold rate constant in amm0 and build up to have 3 rate data points
		*/
		await amm0.mint(Uin, _10To18BN, _10To18BN);
		await amm0.mint(Uin, _10To18BN, _10To18BN);
		let results = await amm0.getReserves();
		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();
		await amm0.burn(await amm0.balanceOf(accounts[0]));
		OracleRate = parseInt((await amm0.getRateFromOracle()).toString()) * Math.pow(2, -64);
		APYo = parseInt((await amm0.getAPYFromOracle()).toString()) * Math.pow(2, -64);
		assert.equal((await capitalHandlerInstance.balanceOf(accounts[0])).toString(), balance.toString(), "correct balance ZCB");
		assert.equal((await yieldTokenInstance.balanceOf_2(accounts[0], false)).toString(), balance.toString(), "correct balance YT");
	});

	it('First Liquidity Token Mint', async () => {
		toMint = balance.div((new BN("1000")));
		await amm1.firstMint(toMint);
		assert.equal((await amm1.balanceOf(accounts[0])).toString(), toMint.toString(), "correct balance of YTamm liquidity tokens");
		assert.equal((await capitalHandlerInstance.balanceOf(accounts[0])).toString(), balance.sub(toMint).toString(), "correct balance ZCB");
		assert.equal((await yieldTokenInstance.balanceOf_2(accounts[0], false)).toString(), balance.sub(toMint.mul(new BN(YTtoLmultiplier+1))).toString(), "correct balance YT");
		let results = await amm1.getReserves();
		assert.equal(results._Ureserves.toString(), toMint.toString(), "correct value of Ureserves");
		assert.equal(results._YTreserves.toString(), toMint.mul(new BN(YTtoLmultiplier)).toString(), "correct value of Ureserves");

		assert.equal((await amm1.totalSupply()).toString(), toMint.toString(), "correct balance of YTamm liquidity tokens");
	});

	it('Mint Liquidity Tokens', async () => {
		await amm1.mint(toMint, toMint, toMint.mul(new BN(YTtoLmultiplier)));
		assert.equal((await amm1.balanceOf(accounts[0])).toString(), toMint.mul(new BN(2)).toString(), "correct balance of YTamm liquidity tokens");
		assert.equal((await capitalHandlerInstance.balanceOf(accounts[0])).toString(), balance.sub(toMint.mul(new BN(2))).toString(), "correct balance ZCB");
		assert.equal((await yieldTokenInstance.balanceOf_2(accounts[0], false)).toString(), balance.sub(toMint.mul(new BN(2*YTtoLmultiplier+2))).toString(), "correct balance YT");
		let results = await amm1.getReserves();
		assert.equal(results._Ureserves.toString(), toMint.mul(new BN(2)).toString(), "correct value of Ureserves");
		assert.equal(results._YTreserves.toString(), toMint.mul(new BN(2*YTtoLmultiplier)).toString(), "correct value of Ureserves");

		assert.equal((await amm1.totalSupply()).toString(), toMint.mul(new BN(2)).toString(), "correct balance of YTamm liquidity tokens");
	});

	it('Burn Liquidity Tokens', async () => {
		await amm1.burn(toMint);
		amm1balance = await amm1.balanceOf(accounts[0]);
		ZCBbalance = await capitalHandlerInstance.balanceOf(accounts[0]);
		YTbalance = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		assert.equal(amm1balance.toString(), toMint, "correct balance of YTamm liquidity tokens");
		assert.equal(ZCBbalance.toString(), balance.sub(toMint).toString(), "correct balance ZCB");
		assert.equal(YTbalance.toString(), balance.sub(toMint.mul(new BN(YTtoLmultiplier+1))).toString(), "correct balance YT");
		let results = await amm1.getReserves();
		Ureserves = results._Ureserves;
		YTreserves = results._YTreserves;
		assert.equal(Ureserves.toString(), toMint.toString(), "correct value of Ureserves");
		assert.equal(YTreserves.toString(), toMint.mul(new BN(YTtoLmultiplier)).toString(), "correct value of Ureserves");

		assert.equal((await amm1.totalSupply()).toString(), amm1balance.toString(), "correct YTamm totalSupply");
		totalSupply = amm1balance
	});

	it('SwapFromSpecificYT()', async () => {
		amtIn = toMint.div(new BN("100"));
		rec = await amm1.SwapFromSpecificYT(amtIn);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let expectedUout = YT_U_math.Uout(parseInt(YTreserves.toString()), parseInt(totalSupply.div(new BN(YTtoLmultiplier)).toString()), r, OracleRate, parseInt(amtIn.toString()));
		let prevZCBbalance = ZCBbalance;
		ZCBbalance = await capitalHandlerInstance.balanceOf(accounts[0]);
		let Uout = ZCBbalance.sub(prevZCBbalance);
		let error = Math.abs(parseInt(Uout.toString())/expectedUout - 1);
		assert.isBelow(error, 0.000001, "acceptable margin of error")
		let prevYTbalance = YTbalance;
		YTbalance = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		assert.equal(prevYTbalance.add(Uout).sub(YTbalance).toString(), amtIn.toString(), "correct amount U in");
	});

	it('SwapToSpecificYT()', async () => {
		amtOut = amtIn;
		let results = await amm1.getReserves();
		Ureserves = results._Ureserves;
		YTreserves = results._YTreserves;

		rec = await amm1.SwapToSpecificYT(amtOut);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let expectedUin = YT_U_math.Uin(parseInt(YTreserves.toString()), parseInt(totalSupply.div(new BN(YTtoLmultiplier)).toString()), r, OracleRate, parseInt(amtOut.toString()));
		let prevZCBbalance = ZCBbalance;
		ZCBbalance = await capitalHandlerInstance.balanceOf(accounts[0]);
		let Uin = prevZCBbalance.sub(ZCBbalance);
		let error = Math.abs(parseInt(Uin.toString())/expectedUin - 1);
		assert.isBelow(error, 0.000001, "acceptable margin of error")
		let prevYTbalance = YTbalance;
		YTbalance = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		assert.equal(YTbalance.sub(prevYTbalance.sub(Uin)).toString(), amtOut.toString(), "correct amount U out");
	});

	it('Valid reserves', async () => {
		let results = await amm1.getReserves();
		Ureserves = results._Ureserves.toString();
		YTreserves = results._YTreserves.toString();
		let balZCB = await capitalHandlerInstance.balanceOf(amm1.address);
		let balYT = await yieldTokenInstance.balanceOf_2(amm1.address, false);
		assert.equal(Ureserves, balZCB.toString(), "valid Ureserves");
		assert.equal(YTreserves, balYT.sub(balZCB).toString(), "valid ZCBreserves");
	});

	it('Yield Generation does not affect pool reserves before contract claim dividend', async () => {
		//simulate generation of yield by sending funds directly to pool address
		amtZCB = balance.div(new BN(1000));
		amtYT = balance.div(new BN(500));
		await capitalHandlerInstance.transfer(amm1.address, amtZCB);
		await yieldTokenInstance.transfer_2(amm1.address, amtYT, true);

		let results = await amm1.getReserves();
		assert.equal(results._Ureserves.toString(), Ureserves, "U reserves not affected by yield generation");
		assert.equal(results._YTreserves.toString(), YTreserves, "U reserves not affected by yield generation");
	});

	it('Contract Claim Dividend', async () => {
		await amm1.contractClaimDividend();

		assert.equal((await amm1.length()).toString(), "2");
		assert.equal((await amm1.contractBalanceAsset1(1)).toString(), amtZCB.toString());
		assert.equal((await amm1.contractBalanceAsset2(1)).toString(), amtYT.toString());
	})

	it('Yield Generation does not affect pool reserves after contract claim dividend', async () => {
		let results = await amm1.getReserves();
		assert.equal(results._Ureserves.toString(), Ureserves, "U reserves not affected by yield generation");
		assert.equal(results._YTreserves.toString(), YTreserves, "U reserves not affected by yield generation");
	});

	it('User Claims Generated Yield', async () => {
		rec = await amm1.claimDividend(accounts[1]);
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

		await capitalHandlerInstance.transfer(amm1.address, amtZCB2);
		await yieldTokenInstance.transfer_2(amm1.address, amtYT2, true);

		await amm1.contractClaimDividend();

		assert.equal((await amm1.length()).toString(), "3");
		assert.equal((await amm1.contractBalanceAsset1(2)).toString(), amtZCB.add(amtZCB2).toString());
		assert.equal((await amm1.contractBalanceAsset2(2)).toString(), amtYT.add(amtYT2).toString());
	});

	it('ClaimContract Dividend After Dividend Payouts', async () => {
		//advance 1 day and 1 second
		await helper.advanceTime(1 + 24*60*60);
		let caught = false;
		try {
			await amm1.contractClaimDividend();
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('Cannot Call claimContractDividend() when no yield has been generated');
	});


	it('Claims Dividend On transfer() call', async () => {
		balance = await amm1.balanceOf(accounts[0]);
		amount = balance.div(new BN(2))
		rec = await amm1.transfer(accounts[1], amount);
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
		await capitalHandlerInstance.transfer(amm1.address, amtZCB);
		await yieldTokenInstance.transfer_2(amm1.address, amtYT, true);
		await amm1.contractClaimDividend();

		await amm1.approve(accounts[0], amount, {from: accounts[1]});
		rec = await amm1.transferFrom(accounts[1], accounts[0], amount);

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
});
