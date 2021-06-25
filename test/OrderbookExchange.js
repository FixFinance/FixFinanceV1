const aToken = artifacts.require("dummyAToken");
const NGBwrapper = artifacts.require("NGBwrapper");
const BigMath = artifacts.require("BigMath");
const fixCapitalPool = artifacts.require("FixCapitalPool");
const yieldToken = artifacts.require("IYieldToken");
const zeroCouponBond = artifacts.require("IZeroCouponBond");
const zcbYtDeployer = artifacts.require("ZCB_YT_Deployer");
const OrderbookExchange = artifacts.require("OrderbookExchange");
const InfoOracle = artifacts.require("InfoOracle");

const helper = require("../helper/helper.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10 = new BN(10);
const _10To18 = _10.pow(new BN("18"));
const secondsPerYear = 31556926;

const BipsToTreasury = "1000"; //10% in basis point format
const SBPSretained = 999_000;

contract('OrderbookExchange', async function(accounts) {

	it('before each', async () => {
		aTokenInstance = await aToken.new("aCOIN");
		infoOracleInstance = await InfoOracle.new(BipsToTreasury, nullAddress);
		NGBwrapperInstance = await NGBwrapper.new(aTokenInstance.address, infoOracleInstance.address, SBPSretained);
		zcbYtDeployerInstance = await zcbYtDeployer.new();
		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		//maturity is 110 days out
		maturity = timestamp + 110*24*60*60;
		fixCapitalPoolInstance = await fixCapitalPool.new(NGBwrapperInstance.address, maturity, zcbYtDeployerInstance.address, infoOracleInstance.address);
		zcbInstance = await zeroCouponBond.at(await fixCapitalPoolInstance.zeroCouponBondAddress());
		yieldTokenInstance = await yieldToken.at(await fixCapitalPoolInstance.yieldTokenAddress());
		exchange = await OrderbookExchange.new(fixCapitalPoolInstance.address);

		//mint funds to accounts[0]
		balance = _10To18;
		await aTokenInstance.approve(NGBwrapperInstance.address, balance);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], balance);
		await NGBwrapperInstance.approve(fixCapitalPoolInstance.address, balance);
		await fixCapitalPoolInstance.depositWrappedToken(accounts[0], balance);
		await zcbInstance.approve(exchange.address, balance);
		await yieldTokenInstance.approve(exchange.address, balance);

		//simulate generation of 100% returns in money market
		await aTokenInstance.setInflation("2"+_10To18.toString().substring(1));
	});

	it('deposit', async () => {
		let yieldToDeposit = _10To18.div(_10);
		let bondToDeposit = _10To18.div(new BN(7)).neg();

		let prevBondBalance = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevYieldBalance = await fixCapitalPoolInstance.balanceYield(accounts[0]);

		await exchange.deposit(yieldToDeposit, bondToDeposit);

		let bondBalance = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let yieldBalance = await fixCapitalPoolInstance.balanceYield(accounts[0]);

		YD = await exchange.YieldDeposited(accounts[0]);
		BD = await exchange.BondDeposited(accounts[0]);
		let lockedYT = await exchange.lockedYT(accounts[0]);

		assert.equal(YD.toString(), yieldToDeposit.toString());
		assert.equal(BD.toString(), bondToDeposit.toString());
		assert.equal(lockedYT.toString(), "0");
		assert.equal(prevYieldBalance.sub(yieldBalance).toString(), yieldToDeposit.toString());
		assert.equal(prevBondBalance.sub(bondBalance).toString(), bondToDeposit.toString());
	});

	it ('withdraw', async () => {
		let yieldToWithdraw = _10To18.div(new BN(20));
		let bondToWithdraw = _10To18.div(new BN(14)).neg();

		let prevBondBalance = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevYieldBalance = await fixCapitalPoolInstance.balanceYield(accounts[0]);

		let prevYD = YD;
		let prevBD = BD;

		await exchange.withdraw(yieldToWithdraw, bondToWithdraw);

		let bondBalance = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let yieldBalance = await fixCapitalPoolInstance.balanceYield(accounts[0]);

		YD = await exchange.YieldDeposited(accounts[0]);
		BD = await exchange.BondDeposited(accounts[0]);
		let lockedYT = await exchange.lockedYT(accounts[0]);

		assert.equal(prevYD.sub(YD).toString(), yieldToWithdraw.toString());
		assert.equal(prevBD.sub(BD).toString(), bondToWithdraw.toString());
		assert.equal(lockedYT.toString(), "0");
		assert.equal(yieldBalance.sub(prevYieldBalance).toString(), yieldToWithdraw.toString());
		assert.equal(bondBalance.sub(prevBondBalance).toString(), bondToWithdraw.toString());
	});

});