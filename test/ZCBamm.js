const aToken = artifacts.require("dummyAToken");
const aaveWrapper = artifacts.require("aaveWrapper");
const BigMath = artifacts.require("BigMath");
const capitalHandler = artifacts.require("capitalHandler");
const yieldToken = artifacts.require("yieldToken");
const yieldTokenDeployer = artifacts.require("yieldTokenDeployer");
const ZCBamm = artifacts.require("ZCBamm");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10To18BN = (new BN("10")).pow(new BN("18"));

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
		amm = await ZCBamm.new(capitalHandlerInstance.address);
		anchor = (await amm.anchor()).toNumber();

		//mint funds to accounts[0]
		balance = _10To18BN;
		await aTokenInstance.approve(aaveWrapperInstance.address, balance);
		await aaveWrapperInstance.firstDeposit(accounts[0], balance);
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
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
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

		await amm.mint(balanceLT, maxUin, maxZCBin);

		let Uexpected = (new BN(Ureserves)).mul(new BN(2)).toString();
		let ZCBexpected = (new BN(ZCBreserves)).mul(new BN(2)).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);
		totalSupplyLT = await amm.totalSupply();

		assert.equal(balanceLT.toString(), Uin.mul(new BN(2)).toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
		assert.equal(totalSupplyLT.toString(), balanceLT.toString(), "correct total supply of liquidity tokens");
	})

	it('burn liquidity tokens', async () => {
		let toBurn = Uin;

		await amm.burn(toBurn);

		let Uexpected = (new BN(Ureserves)).div(new BN(2)).toString();
		let ZCBexpected = (new BN(ZCBreserves)).div(new BN(2)).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceLT = await amm.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
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
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let Uout = parseInt(Ureserves) - (k - Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).add(amtIn).toString()), 1-r))**(1/(1-r));
		let Uexpected = (parseInt(Ureserves) - Uout).toString();
		let ZCBexpected = (parseInt(ZCBreserves) + parseInt(amtIn.toString())).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceLT.toString(), Uin.toString());
		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('SwapFromSpecificTokens _ZCBin:false', async () => {
		amtIn = balance.div(new BN(100));

		rec = await amm.SwapFromSpecificTokens(amtIn, false);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let ZCBout = parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()) - (k - Math.pow( (new BN(Ureserves)).add(amtIn).toString() , 1-r))**(1/(1-r));
		let Uexpected = amtIn.add(new BN(Ureserves)).toString();
		let ZCBexpected = (parseInt(ZCBreserves) - ZCBout).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('SwapToSpecificTokens _ZCBout:true', async () => {
		let amtOut = balance.div(new BN(100));

		rec = await amm.SwapToSpecificTokens(amtOut, true);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let Uin = (k - Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).sub(amtOut).toString()), 1-r))**(1/(1-r)) - parseInt(Ureserves);
		let Uexpected = (parseInt(Ureserves) + Uin).toString()
		let ZCBexpected = (parseInt(ZCBreserves) - parseInt(amtOut.toString())).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

	it('SwapToSpecificTokens _ZCBout:false', async () => {
		let amtOut = balance.div(new BN(100));

		rec = await amm.SwapToSpecificTokens(amtOut, false);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let r = (maturity-timestamp)/anchor;
		let k = Math.pow(parseInt(Ureserves), 1-r) + Math.pow(parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString()), 1-r);
		let ZCBin = (k - Math.pow( (new BN(Ureserves)).sub(amtOut).toString() , 1-r))**(1/(1-r)) - parseInt(totalSupplyLT.add(new BN(ZCBreserves)).toString());
		let Uexpected = (parseInt(Ureserves) - parseInt(amtOut.toString())).toString();
		let ZCBexpected = (parseInt(ZCBreserves) + ZCBin).toString();

		let results = await amm.getReserves();

		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();

		assert.equal(Ureserves.length, Uexpected.length, "correct length of Ureserves");
		assert.equal(Ureserves.substring(0, 10), Uexpected.substring(0, 10), "Ureserves is accurate to within 10 digits");
		assert.equal(ZCBreserves.length, ZCBexpected.length, "correct length of ZCBreserves");
		assert.equal(ZCBreserves.substring(0, 10), ZCBexpected.substring(0, 10), "ZCBreserves is accurate to within 10 digits");

		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await capitalHandlerInstance.balanceOf(accounts[0]);

		assert.equal(balanceYT.toString(), balance.sub(new BN(Ureserves)).toString(), "correct balance YT");
		assert.equal(balanceZCB.toString(), balance.sub((new BN(ZCBreserves)).add(new BN(Ureserves))).toString(), "correct balance ZCB");
	});

});
