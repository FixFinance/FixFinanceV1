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
		await NGBwrapperInstance.forceHarvest();
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
		lockedYT = await exchange.lockedYT(accounts[0]);

		assert.equal(prevYD.sub(YD).toString(), yieldToWithdraw.toString());
		assert.equal(prevBD.sub(BD).toString(), bondToWithdraw.toString());
		assert.equal(lockedYT.toString(), "0");
		assert.equal(yieldBalance.sub(prevYieldBalance).toString(), yieldToWithdraw.toString());
		assert.equal(bondBalance.sub(prevBondBalance).toString(), bondToWithdraw.toString());
	});

	async function test_place_limit_order(amt, MCR, targetID, hintID, expectedIDs, isZCBLimitSell) {
		if (isZCBLimitSell) {
			let prevYD = YD;
			let prevBD = BD;
			let prevLockedYT = lockedYT;

			await exchange.limitSellZCB(amt, MCR, hintID);

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);

			let currentID = (await exchange.headZCBSellID()).toString();
			let order;
			for (let i = 0; i < expectedIDs.length; i++) {
				order = await exchange.ZCBSells(currentID);
				assert.equal(currentID, expectedIDs[i]);
				currentID = order.nextID.toString();
			}
			assert.equal(currentID, "0", "end of orderbook refers to null order");

			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(prevBD.sub(BD).toString(), amt.toString());
			assert.equal(lockedYT.toString(), prevLockedYT.toString());

			order = await exchange.ZCBSells(targetID);

			assert.equal(order.maker, accounts[0]);
			assert.equal(order.amount.toString(), amt.toString());
			assert.equal(order.maturityConversionRate.toString(), MCR.toString());
		}
		else {
			let prevYD = YD;
			let prevBD = BD;
			let prevLockedYT = lockedYT;

			let rec = await exchange.limitSellYT(amt, MCR, hintID);

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);

			let currentID = (await exchange.headYTSellID()).toString();
			let order;
			for (let i = 0; i < expectedIDs.length; i++) {
				order = await exchange.YTSells(currentID);
				assert.equal(currentID, expectedIDs[i]);
				currentID = order.nextID.toString();
			}
			assert.equal(currentID, "0", "end of orderbook refers to null order");

			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(BD.toString(), prevBD.toString());
			assert.equal(lockedYT.sub(prevLockedYT).toString(), amt.toString());

			order = await exchange.YTSells(targetID);

			assert.equal(order.maker, accounts[0]);
			assert.equal(order.amount.toString(), amt.toString());
			assert.equal(order.maturityConversionRate.toString(), MCR.toString());
		}
	}

	async function test_modify(change, ID, hintID, maxSteps, isZCBLimitSell) {
		if (isZCBLimitSell) {
			let prevYD = YD;
			let prevBD = BD;
			let prevOrder = await exchange.ZCBSells(ID);
			let prevHeadID = (await exchange.headZCBSellID()).toString();

			await exchange.modifyZCBLimitSell(change, ID, hintID, maxSteps);

			let order = await exchange.ZCBSells(ID);
			let headID = (await exchange.headZCBSellID()).toString();

			let resultantChange = order.amount.sub(prevOrder.amount);
			let expectedDeleted = change.cmp(prevOrder.amount.neg()) <= 0;
			let expectedChange = expectedDeleted ? prevOrder.amount.neg() : change;

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);

			assert.equal(resultantChange.toString(), expectedChange.toString());
			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(prevBD.sub(BD).toString(), resultantChange.toString());
			if (expectedDeleted) {
				assert.equal(order.maker, nullAddress);
				assert.equal(order.maturityConversionRate.toString(), "0");
				assert.equal(order.nextID.toString(), "0");
			}
			else {
				assert.equal(order.maker, prevOrder.maker);
				assert.equal(order.maturityConversionRate.toString(), prevOrder.maturityConversionRate.toString());
				assert.equal(order.nextID.toString(), prevOrder.nextID.toString());
			}
			if (expectedDeleted && prevHeadID === ID) {
				assert.equal(headID, prevOrder.nextID.toString());
			}
			else {
				assert.equal(headID, prevHeadID);
			}
		}
		else {
			let prevYD = YD;
			let prevBD = BD;
			let prevLockedYT = lockedYT;
			let prevOrder = await exchange.YTSells(ID);
			let prevHeadID = (await exchange.headYTSellID()).toString();

			await exchange.modifyYTLimitSell(change, ID, hintID, maxSteps);

			let order = await exchange.YTSells(ID);
			let headID = (await exchange.headYTSellID()).toString();

			let resultantChange = order.amount.sub(prevOrder.amount);
			let expectedDeleted = change.cmp(prevOrder.amount.neg()) <= 0;
			let expectedChange = expectedDeleted ? prevOrder.amount.neg() : change;

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);

			assert.equal(resultantChange.toString(), expectedChange.toString());
			assert.equal(BD.toString(), prevBD.toString());
			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(lockedYT.sub(prevLockedYT).toString(), resultantChange.toString());
			if (expectedDeleted) {
				assert.equal(order.maker, nullAddress);
				assert.equal(order.maturityConversionRate.toString(), "0");
				assert.equal(order.nextID.toString(), "0");
			}
			else {
				assert.equal(order.maker, prevOrder.maker);
				assert.equal(order.maturityConversionRate.toString(), prevOrder.maturityConversionRate.toString());
				assert.equal(order.nextID.toString(), prevOrder.nextID.toString());
			}
			if (expectedDeleted && prevHeadID === ID) {
				assert.equal(headID, prevOrder.nextID.toString());
			}
			else {
				assert.equal(headID, prevHeadID);
			}
		}
	}

	it('limitSellZCB at head, blank list', async () => {
		let amtZCB = _10To18.div(new BN(200));
		let MCR = _10To18.mul(new BN(5));
		let expectedIDs = ["1"];
		await test_place_limit_order(amtZCB, MCR, "1", "0", expectedIDs, true);
	});

	it('limitSellZCB at head, head exists', async () => {
		let amtZCB = _10To18.div(new BN(500));
		let MCR = _10To18.mul(new BN(8));
		let expectedIDs = ["2", "1"];
		await test_place_limit_order(amtZCB, MCR, "2", "0", expectedIDs, true);
	});

	it('limitSellZCB in middle, no hint', async () => {
		let amtZCB = _10To18.div(new BN(500));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["2", "3", "1"];
		await test_place_limit_order(amtZCB, MCR, "3", "0", expectedIDs, true);
	});

	it('limitSellZCB in middle, use hint', async () => {
		let amtZCB = _10To18.div(new BN(500));
		let MCR = _10To18.mul(new BN(6));
		let expectedIDs = ["2", "3", "4", "1"];
		await test_place_limit_order(amtZCB, MCR, "4", "2", expectedIDs, true);
	});

	it('limitSellZCB at tail, no hint', async () => {
		let amtZCB = _10To18.div(new BN(800));
		let MCR = _10To18.mul(new BN(4));
		let expectedIDs = ["2", "3", "4", "1", "5"];
		await test_place_limit_order(amtZCB, MCR, "5", "0", expectedIDs, true);
	});

	it('limitSellZCB at tail, use hint', async () => {
		let amtZCB = _10To18.div(new BN(700));
		let MCR = _10To18.mul(new BN(3));
		let expectedIDs = ["2", "3", "4", "1", "5", "6"];
		await test_place_limit_order(amtZCB, MCR, "6", "5", expectedIDs, true);
	});

	it('cannot limitSellZCB where MCR is under current ratio', async () => {
		let MCR = _10To18.mul(new BN(3)).div(new BN(2));
		let amtZCB = _10To18.div(new BN(900));
		let caught = false;
		try {
			await exchange.limitSellZCB(amtZCB, MCR, 0);
		}
		catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail("was able to make sell ZCB limit order with MCR under current ratio");
		}
	});

	it('modifyZCBLimitSell at head', async () => {
		await test_modify(_10To18.div(new BN(1200)).neg(), "2", "0", 10, true);
	});

	it('modifyZCBLimitSell in middle, no hint', async () => {
		await test_modify(_10To18.div(new BN(7500)).neg(), "4", "0", 10, true);
	});

	it('modifyZCBLimitSell in middle, use hint', async () => {
		await test_modify(_10To18.div(new BN(6500)).neg(), "4", "3", 10, true);
	});

	it('modifyZCBLimitSell at tail, no hint', async () => {
		await test_modify(_10To18.div(new BN(6500)).neg(), "6", "0", 10, true);
	});

	it('modifyZCBLimitSell at tail, use hint', async () => {
		await test_modify(_10To18.neg(), "6", "1", 10, true);
	});

	//other side of orderbook

	it('limitSellYT at head, blank list', async () => {
		let amtYT = _10To18.div(new BN(800));
		let MCR = _10To18.mul(new BN(6));
		let expectedIDs = ["7"];
		await test_place_limit_order(amtYT, MCR, "7", "0", expectedIDs, false);
	});

	it('limitSellYT at head, head exists', async () => {
		let amtYT = _10To18.div(new BN(900));
		let MCR = _10To18.mul(new BN(3));
		let expectedIDs = ["8", "7"];
		await test_place_limit_order(amtYT, MCR, "8", "0", expectedIDs, false);
	});

	it('limitSellYT in middle, no hint', async () => {
		let amtYT = _10To18.div(new BN(700));
		let MCR = _10To18.mul(new BN(4));
		let expectedIDs = ["8", "9", "7"];
		await test_place_limit_order(amtYT, MCR, "9", "0", expectedIDs, false);
	});

	it('limitSellYT in middle, use hint', async () => {
		let amtYT = _10To18.div(new BN(450));
		let MCR = _10To18.mul(new BN(5));
		let expectedIDs = ["8", "9", "10", "7"];
		await test_place_limit_order(amtYT, MCR, "10", "9", expectedIDs, false);
	});

	it('limitSellYT at tail, no hint', async () => {
		let amtYT = _10To18.div(new BN(870));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["8", "9", "10", "7", "11"];
		await test_place_limit_order(amtYT, MCR, "11", "0", expectedIDs, false);
	});

	it('limitSellYT at tail, use hint', async () => {
		let amtYT = _10To18.div(new BN(900));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["8", "9", "10", "7", "11", "12"];
		await test_place_limit_order(amtYT, MCR, "12", "7", expectedIDs, false);
	});

	it('cannot limitSellYT where MCR is under current ratio', async () => {
		let MCR = _10To18.mul(new BN(3)).div(new BN(2));
		let amtYT = _10To18.div(new BN(1900));
		let caught = false;
		try {
			await exchange.limitSellYT(amtYT, MCR, 0);
		}
		catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail("was able to make sell YT limit order with MCR under current ratio");
		}
	});

	it('modifyYTLimitSell at head', async () => {
		await test_modify(_10To18.neg(), "8", "0", 10, false);
	});

	it('modifyYTLimitSell in middle, no hint', async () => {
		await test_modify(_10To18.div(new BN(5000)), "10", "0", 10, false);
	});

	it('modifyYTLimitSell in middle, use hint', async () => {
		await test_modify(_10To18.div(new BN(1000)), "11", "10", 10, false);
	});

	it('modifyYTLimitSell at tail, no hint', async () => {
		await test_modify(_10To18.div(new BN(7000)).neg(), "12", "0", 10, false);
	});

	it('modifyYTLimitSell at tail, use hint', async () => {
		await test_modify(_10To18.div(new BN(9000)).neg(), "12", "11", 10, false);
	});
});