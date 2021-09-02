const aToken = artifacts.require("dummyAToken");
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapper = artifacts.require("NGBwrapper");
const BigMath = artifacts.require("BigMath");
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const fixCapitalPool = artifacts.require("FixCapitalPool");
const yieldToken = artifacts.require("IYieldToken");
const zeroCouponBond = artifacts.require("IZeroCouponBond");
const zcbYtDeployer = artifacts.require("ZCB_YT_Deployer");
const OrderbookDelegate1 = artifacts.require("OrderbookDelegate1");
const OrderbookDelegate2 = artifacts.require("OrderbookDelegate2");
const OrderbookDelegate3 = artifacts.require("OrderbookDelegate3");
const OrderbookExchange = artifacts.require("OrderbookExchange");
const InfoOracle = artifacts.require("InfoOracle");

const helper = require("../helper/helper.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const treasuryAddress = "0x0000000000000000000000000000000000000001";
const _10 = new BN(10);
const _10To18 = _10.pow(new BN("18"));
const LENGTH_RATE_SERIES = 31;
const LENGTH_RATE_SERIES_BN = new BN(LENGTH_RATE_SERIES);
const secondsPerYear = 31556926;

const BipsToTreasury = "1000"; //10% in basis point format
const SBPSretained = 999_000;

const medianBN = arr => {
  const mid = Math.floor(arr.length / 2),
    nums = [...arr].sort((a, b) => a.cmp(b));
  return arr.length % 2 !== 0 ? nums[mid] : (nums[mid - 1] + nums[mid]) / 2;
};

const ErrorRange = Math.pow(10,-7);

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

const MIN_ORDER_SIZE_MODE = {
	NONE: 0,
	NOMINAL: 1,
	NPV: 2
};

contract('OrderbookExchange', async function(accounts) {

	it('before each', async () => {
		aTokenInstance = await aToken.new("aCOIN");
		rewardsAsset = await aToken.new("RWD");
		infoOracleInstance = await InfoOracle.new(BipsToTreasury, treasuryAddress, true);
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
		zcbYtDeployerInstance = await zcbYtDeployer.new();
		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		//maturity is 110 days out
		maturity = timestamp + 110*24*60*60;
		fcpDelegate1Instance = await FCPDelegate1.new();
		fixCapitalPoolInstance = await fixCapitalPool.new(NGBwrapperInstance.address, maturity, zcbYtDeployerInstance.address, infoOracleInstance.address, fcpDelegate1Instance.address);
		zcbInstance = await zeroCouponBond.at(await fixCapitalPoolInstance.zeroCouponBondAddress());
		yieldTokenInstance = await yieldToken.at(await fixCapitalPoolInstance.yieldTokenAddress());
		orderbookDelegate1Instance = await OrderbookDelegate1.new();
		orderbookDelegate2Instance = await OrderbookDelegate2.new();
		orderbookDelegate3Instance = await OrderbookDelegate3.new();
		exchange = await OrderbookExchange.new(
			fixCapitalPoolInstance.address,
			infoOracleInstance.address,
			orderbookDelegate1Instance.address,
			orderbookDelegate2Instance.address,
			orderbookDelegate3Instance.address
		);
		await exchange.setMinimumOrderSize(MIN_ORDER_SIZE_MODE.NPV, _10To18.div(new BN(400000)));
		FeeBips = 25;
		await infoOracleInstance.setMinimumOrderbookFee(FeeBips);

		//mint funds to accounts[0]
		balance = _10To18;
		await aTokenInstance.approve(NGBwrapperInstance.address, balance);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], balance);
		await NGBwrapperInstance.approve(fixCapitalPoolInstance.address, balance);
		await fixCapitalPoolInstance.depositWrappedToken(accounts[0], balance);
		await zcbInstance.approve(exchange.address, balance);
		await yieldTokenInstance.approve(exchange.address, balance);
		await zcbInstance.transfer(accounts[1], balance.div(new BN(2)));
		await yieldTokenInstance.transfer(accounts[1], balance.div(new BN(2)))
		await zcbInstance.approve(exchange.address, balance, {from: accounts[1]});
		await yieldTokenInstance.approve(exchange.address, balance, {from: accounts[1]});

		//simulate generation of 100% returns in money market
		await aTokenInstance.setInflation("2"+_10To18.toString().substring(1));
		await NGBwrapperInstance.addRewardAsset(rewardsAsset.address);
	});

	function rand(min, max) {
		return Math.floor(Math.random() * (max - min)) + min + 1;
	}

	async function addRewards() {
		let amtToMint = _10To18.div(new BN(rand(1, 10000)));
		let currentBal = await rewardsAsset.balanceOf(NGBwrapperInstance.address);
		let newBal = currentBal.add(amtToMint);
		await rewardsAsset.mintTo(NGBwrapperInstance.address, newBal);
	}

	it('deposit', async () => {
		await addRewards();
		let yieldToDeposit = _10To18.div(_10);
		let bondToDeposit = _10To18.div(new BN(7)).neg();

		let prevBondBalance = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevYieldBalance = await fixCapitalPoolInstance.balanceYield(accounts[0]);

		await exchange.deposit(yieldToDeposit, bondToDeposit);
		await exchange.deposit(yieldToDeposit, bondToDeposit, {from: accounts[1]});

		let bondBalance = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let yieldBalance = await fixCapitalPoolInstance.balanceYield(accounts[0]);

		YD = await exchange.YieldDeposited(accounts[0]);
		BD = await exchange.BondDeposited(accounts[0]);
		lockedYT = await exchange.lockedYT(accounts[0]);
		lockedZCB = await exchange.lockedZCB(accounts[0]);

		assert.equal(YD.toString(), yieldToDeposit.toString());
		assert.equal(BD.toString(), bondToDeposit.toString());
		assert.equal(lockedYT.toString(), "0");
		assert.equal(lockedZCB.toString(), "0");
		assert.equal(prevYieldBalance.sub(yieldBalance).toString(), yieldToDeposit.toString());
		assert.equal(prevBondBalance.sub(bondBalance).toString(), bondToDeposit.toString());
	});

	it ('withdraw', async () => {
		await addRewards();
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
		lockedZCB = await exchange.lockedZCB(accounts[0]);

		assert.equal(prevYD.sub(YD).toString(), yieldToWithdraw.toString());
		assert.equal(prevBD.sub(BD).toString(), bondToWithdraw.toString());
		assert.equal(lockedYT.toString(), "0");
		assert.equal(lockedZCB.toString(), "0");
		assert.equal(yieldBalance.sub(prevYieldBalance).toString(), yieldToWithdraw.toString());
		assert.equal(bondBalance.sub(prevBondBalance).toString(), bondToWithdraw.toString());
	});

	async function test_and_check_oracle(test_function) {
		await helper.advanceTime(61);
		let prevZCBsellHeadID = await exchange.headZCBSellID();
		let prevYTsellHeadID = await exchange.headYTSellID();
		let prevMCRzcbHead = (await exchange.ZCBSells(prevZCBsellHeadID)).maturityConversionRate;
		let prevMCRytHead = (await exchange.YTSells(prevYTsellHeadID)).maturityConversionRate;
		let willSet = prevMCRzcbHead.toString() !== "0" && prevMCRytHead.toString() !== "0";
		let ratio = parseFloat((await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18)).toString());
		let ratioAdjZCBMCR = parseFloat(prevMCRzcbHead.toString()) / ratio;
		let ratioAdjYTMCR = parseFloat(prevMCRytHead.toString()) / ratio;
		let newMCRdatapoint = Math.sqrt(ratioAdjZCBMCR * ratioAdjYTMCR) * ratio;
		let prevOrcData = await exchange.getOracleData();

		let rec = await test_function();

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let orcData = await exchange.getOracleData();
		if (willSet) {
			assert.equal(orcData._toSet.toString(), prevOrcData._toSet.add(new BN(1)).mod(LENGTH_RATE_SERIES_BN).toString());
			let numberActualMCR = parseFloat(orcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString());
			assert.isBelow(AmountError(numberActualMCR, newMCRdatapoint), ErrorRange);
			assert.equal(orcData._lastDatapointCollection.toString(), timestamp.toString());
		}
		else {
			assert.equal(orcData._toSet.toString(), prevOrcData._toSet.toString());
			assert.equal(orcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString(), prevOrcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString());
			assert.equal(orcData._lastDatapointCollection.toString(), prevOrcData._lastDatapointCollection.toString());
		}
	}

	async function assert_valid_subaccount_position(acct) {
		let yieldDeposited = await exchange.YieldDeposited(acct);
		let bondDeposited = await exchange.BondDeposited(acct);
		let subAcctPos = await NGBwrapperInstance.subAccountPositions(exchange.address, acct, fixCapitalPoolInstance.address);
		assert.equal(subAcctPos.yield.toString(), yieldDeposited.toString());
		assert.equal(subAcctPos.bond.toString(), bondDeposited.toString());
	}

	async function test_place_limit_order(amt, MCR, targetID, hintID, expectedIDs, isZCBLimitSell) {
		await helper.advanceTime(61);
		const maxSteps = 100;
		let prevZCBsellHeadID = await exchange.headZCBSellID();
		let prevYTsellHeadID = await exchange.headYTSellID();
		let prevMCRzcbHead = (await exchange.ZCBSells(prevZCBsellHeadID)).maturityConversionRate;
		let prevMCRytHead = (await exchange.YTSells(prevYTsellHeadID)).maturityConversionRate;
		let willSet = prevMCRzcbHead.toString() !== "0" && prevMCRytHead.toString() !== "0";
		let ratio = parseFloat((await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18)).toString());
		let ratioAdjZCBMCR = parseFloat(prevMCRzcbHead.toString()) / ratio;
		let ratioAdjYTMCR = parseFloat(prevMCRytHead.toString()) / ratio;
		let newMCRdatapoint = Math.sqrt(ratioAdjZCBMCR * ratioAdjYTMCR) * ratio;
		let prevOrcData = await exchange.getOracleData();
		let prevYD = YD;
		let prevBD = BD;
		let prevLockedYT = lockedYT;
		let prevLockedZCB = lockedZCB;
		let rec;
		if (isZCBLimitSell) {
			rec = await exchange.limitSellZCB(amt, MCR, hintID, maxSteps);
			let log = rec.receipt.logs[0];
			let logArgs = log.args;
			assert.equal(log.event, 'MakeLimitSellZCB');

			let targetIndex = expectedIDs.indexOf(targetID);
			if (targetIndex === -1) {
				assert.fail('Target ID not present in expectedIDs array, invalid test');
			}
			let prevID = targetIndex === 0 ? "0" : expectedIDs[targetIndex-1];
			assert.equal(logArgs.maker, accounts[0]);
			assert.equal(logArgs.prevID.toString(), prevID);
			assert.equal(logArgs.amount.toString(), amt.toString());
			assert.equal(logArgs.maturityConversionRate.toString(), MCR.toString());

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);
			lockedZCB = await exchange.lockedZCB(accounts[0]);

			let currentID = (await exchange.headZCBSellID()).toString();
			let order;
			for (let i = 0; i < expectedIDs.length; i++) {
				order = await exchange.ZCBSells(currentID);
				assert.equal(currentID, expectedIDs[i]);
				currentID = order.nextID.toString();
			}
			assert.equal(currentID, "0", "end of orderbook refers to null order");

			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(BD.toString(), prevBD.toString());
			assert.equal(lockedYT.toString(), prevLockedYT.toString());
			assert.equal(lockedZCB.sub(prevLockedZCB).toString(), amt.toString());

			order = await exchange.ZCBSells(targetID);

			assert.equal(order.maker, accounts[0]);
			assert.equal(order.amount.toString(), amt.toString());
			assert.equal(order.maturityConversionRate.toString(), MCR.toString());
		}
		else {

			rec = await exchange.limitSellYT(amt, MCR, hintID, maxSteps);

			let log = rec.receipt.logs[0];
			let logArgs = log.args;
			assert.equal(log.event, 'MakeLimitSellYT');

			let targetIndex = expectedIDs.indexOf(targetID);
			if (targetIndex === -1) {
				assert.fail('Target ID not present in expectedIDs array, invalid test');
			}
			let prevID = targetIndex === 0 ? "0" : expectedIDs[targetIndex-1];
			assert.equal(logArgs.maker, accounts[0]);
			assert.equal(logArgs.prevID.toString(), prevID);
			assert.equal(logArgs.amount.toString(), amt.toString());
			assert.equal(logArgs.maturityConversionRate.toString(), MCR.toString());

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);
			lockedZCB = await exchange.lockedZCB(accounts[0]);

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
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let orcData = await exchange.getOracleData();
		if (willSet) {
			assert.equal(orcData._toSet.toString(), prevOrcData._toSet.add(new BN(1)).mod(LENGTH_RATE_SERIES_BN).toString());
			let numberActualMCR = parseFloat(orcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString());
			assert.isBelow(AmountError(numberActualMCR, newMCRdatapoint), ErrorRange);
			assert.equal(orcData._lastDatapointCollection.toString(), timestamp.toString());
		}
		else {
			assert.equal(orcData._toSet.toString(), prevOrcData._toSet.toString());
			assert.equal(orcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString(), prevOrcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString());
			assert.equal(orcData._lastDatapointCollection.toString(), prevOrcData._lastDatapointCollection.toString());
		}
		await assert_valid_subaccount_position(accounts[0]);
		return rec;
	}

	async function test_modify(change, ID, hintID, maxSteps, removeBelowLimit, isZCBLimitSell) {
		await helper.advanceTime(61);
		let prevYD = YD;
		let prevBD = BD;
		let prevLockedYT = lockedYT;
		let prevLockedZCB = lockedZCB;
		let prevZCBsellHeadID = await exchange.headZCBSellID();
		let prevYTsellHeadID = await exchange.headYTSellID();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		let prevMCRzcbHead = (await exchange.ZCBSells(prevZCBsellHeadID)).maturityConversionRate;
		let prevMCRytHead = (await exchange.YTSells(prevYTsellHeadID)).maturityConversionRate;
		let willSet = prevMCRzcbHead.toString() !== "0" && prevMCRytHead.toString() !== "0";
		let ratioNum = parseFloat(ratio.toString());
		let ratioAdjZCBMCR = parseFloat(prevMCRzcbHead.toString()) / ratioNum;
		let ratioAdjYTMCR = parseFloat(prevMCRytHead.toString()) / ratioNum;
		let newMCRdatapoint = Math.sqrt(ratioAdjZCBMCR * ratioAdjYTMCR) * ratioNum;
		let prevOrcData = await exchange.getOracleData();
		let prevOrder = isZCBLimitSell ? await exchange.ZCBSells(ID) : await exchange.YTSells(ID);
		let prevHeadID = (isZCBLimitSell ? prevZCBsellHeadID : prevYTsellHeadID).toString();
		let expectedDeleted = change.neg().cmp(prevOrder.amount) >= 0;
		let expectedChange = expectedDeleted ? prevOrder.amount.neg() : change;
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let order, headID, rec;
		if (isZCBLimitSell) {
			//Z == U * yieldToMaturity
			let minimumZCB = minimumOrderSize.mul(prevOrder.maturityConversionRate).div(ratio);
			if (change.cmp(new BN(0)) == -1 && minimumZCB.cmp(prevOrder.amount.add(change)) > -1) {
				if (expectedDeleted || removeBelowLimit) {
					expectedChange = prevOrder.amount.neg();
					expectedDeleted = true;
				}
				else if (minimumZCB.cmp(prevOrder.amount) == 1) {
					expectedChange = 0;
				}
				else {
					expectedChange = prevOrder.amount.sub(minimumZCB).neg();
				}
			}

			rec = await exchange.modifyZCBLimitSell(change, ID, hintID, maxSteps, removeBelowLimit);
			let log = rec.receipt.logs[0];
			let logArgs = log.args;

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);
			lockedZCB = await exchange.lockedZCB(accounts[0]);

			assert.equal(log.event, 'ModifyOrder');

			order = await exchange.ZCBSells(ID);
			headID = (await exchange.headZCBSellID()).toString();
			let resultantChange = order.amount.sub(prevOrder.amount);

			assert.equal(logArgs.orderID.toString(), ID.toString());
			assert.equal(logArgs.change.toString(), expectedChange.toString(), "correct change value logged");

			assert.equal(resultantChange.toString(), expectedChange.toString());
			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(BD.toString(), prevBD.toString());
			assert.equal(lockedYT.toString(), prevLockedYT.toString());
			assert.equal(lockedZCB.sub(prevLockedZCB).toString(), expectedChange.toString());
		}
		else {
			//YT == U / ((1 - zcbDilutiontoMatutity) * ratio)
			let dilutionToMaturity = ratio.mul(_10To18).div(prevOrder.maturityConversionRate);
			let minimumYT = minimumOrderSize.mul(_10To18).div(_10To18.sub(dilutionToMaturity).mul(ratio).div(_10To18));
			if (change.cmp(new BN(0)) == -1 && minimumYT.cmp(prevOrder.amount.add(change)) > -1) {
				if (expectedDeleted || removeBelowLimit) {
					expectedChange = prevOrder.amount.neg();
					expectedDeleted = true;
				}
				else if (minimumYT.cmp(prevOrder.amount) == 1) {
					expectedChange = 0;
				}
				else {
					expectedChange = prevOrder.amount.sub(minimumYT).neg();
				}
			}

			rec = await exchange.modifyYTLimitSell(change, ID, hintID, maxSteps, removeBelowLimit);
			let log = rec.receipt.logs[0];
			let logArgs = log.args;
			assert.equal(log.event, 'ModifyOrder');

			order = await exchange.YTSells(ID);
			headID = (await exchange.headYTSellID()).toString();
			let resultantChange = order.amount.sub(prevOrder.amount);

			assert.equal(logArgs.orderID.toString(), ID.toString());
			assert.equal(logArgs.change.toString(), expectedChange.toString(), "correct change value logged");

			YD = await exchange.YieldDeposited(accounts[0]);
			BD = await exchange.BondDeposited(accounts[0]);
			lockedYT = await exchange.lockedYT(accounts[0]);
			lockedZCB = await exchange.lockedZCB(accounts[0]);

			assert.equal(resultantChange.toString(), expectedChange.toString());
			assert.equal(BD.toString(), prevBD.toString());
			assert.equal(YD.toString(), prevYD.toString());
			assert.equal(lockedYT.sub(prevLockedYT).toString(), resultantChange.toString());
			assert.equal(lockedZCB.toString(), prevLockedZCB.toString());
		}
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
		let orcData = await exchange.getOracleData();
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		if (willSet) {
			assert.equal(orcData._toSet.toString(), prevOrcData._toSet.add(new BN(1)).mod(LENGTH_RATE_SERIES_BN).toString());
			let numberActualMCR = parseFloat(orcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString());
			assert.isBelow(AmountError(numberActualMCR, newMCRdatapoint), ErrorRange);
			assert.equal(orcData._lastDatapointCollection.toString(), timestamp.toString());
		}
		else {
			assert.equal(orcData._toSet.toString(), prevOrcData._toSet.toString());
			assert.equal(orcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString(), prevOrcData._impliedMCRs[prevOrcData._toSet.toNumber()].toString());
			assert.equal(orcData._lastDatapointCollection.toString(), prevOrcData._lastDatapointCollection.toString());
		}
		await assert_valid_subaccount_position(accounts[0]);
		return rec;
	}

	it('limitSellZCB at head, blank list', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(200));
		let MCR = _10To18.mul(new BN(5));
		let expectedIDs = ["1"];
		await test_place_limit_order(amtZCB, MCR, "1", "0", expectedIDs, true);
	});

	it('limitSellZCB at head, head exists', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(500));
		let MCR = _10To18.mul(new BN(8));
		let expectedIDs = ["2", "1"];
		await test_place_limit_order(amtZCB, MCR, "2", "0", expectedIDs, true);
	});

	it('limitSellZCB in middle, no hint', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(500));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["2", "3", "1"];
		await test_place_limit_order(amtZCB, MCR, "3", "0", expectedIDs, true);
	});

	it('limitSellZCB in middle, use hint', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(500));
		let MCR = _10To18.mul(new BN(6));
		let expectedIDs = ["2", "3", "4", "1"];
		await test_place_limit_order(amtZCB, MCR, "4", "2", expectedIDs, true);
	});

	it('limitSellZCB at tail, no hint', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(800));
		let MCR = _10To18.mul(new BN(4));
		let expectedIDs = ["2", "3", "4", "1", "5"];
		await test_place_limit_order(amtZCB, MCR, "5", "0", expectedIDs, true);
	});

	it('limitSellZCB at tail, use hint', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(700));
		let MCR = _10To18.mul(new BN(3));
		let expectedIDs = ["2", "3", "4", "1", "5", "6"];
		await test_place_limit_order(amtZCB, MCR, "6", "5", expectedIDs, true);
	});

	it('cannot limitSellZCB where MCR is under current ratio', async () => {
		await addRewards();
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
		await addRewards();
		await test_modify(_10To18.div(new BN(1200)), "2", "0", 10, false, true);
	});

	it('modifyZCBLimitSell in middle, no hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(7500)).neg(), "4", "0", 10, false, true);
	});

	it('modifyZCBLimitSell in middle, use hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(6500)).neg(), "4", "3", 10, false, true);
	});

	it('modifyZCBLimitSell at tail, no hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(6500)).neg(), "6", "0", 10, false, true);
	});

	it('modifyZCBLimitSell at tail, use hint', async () => {
		await addRewards();
		await test_modify(_10To18.neg(), "6", "1", 10, false, true);
	});

	it('modifyZCBLimitSell at head, reultant amount under minimum', async () => {
		await addRewards();
		let order = await exchange.ZCBSells("2");
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		let minimumZCB = minimumOrderSize.mul(order.maturityConversionRate).div(ratio);
		let change = order.amount.sub(minimumZCB).add(new BN(100)).neg();
		await test_modify(change, "2", "0", 10, false, true);
		//add back
		await test_modify(change.neg(), "2", "0", 10, false, true);
		//tets again with removeUnderMinimum:true
		await test_modify(change, "2", "0", 10, true, true);
	});

	it('modifyZCBLimitSell in middle use hint, resultant amount under minimum', async () => {
		await addRewards();
		let order = await exchange.ZCBSells("1");
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		let minimumZCB = minimumOrderSize.mul(order.maturityConversionRate).div(ratio);
		let change = order.amount.sub(minimumZCB).add(new BN(100)).neg();
		await test_modify(change, "1", "4", 10, false, true);
		//add back
		await test_modify(change.neg().sub(new BN(100)), "1", "4", 10, false, true);
		//tets again with removeUnderMinimum:true
		await test_modify(change, "1", "4", 10, true, true);
	});

	it('modifyZCBLimitSell in middle no hint, resultant amount under minimum', async () => {
		await addRewards();
		let order = await exchange.ZCBSells("4");
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		let minimumZCB = minimumOrderSize.mul(order.maturityConversionRate).div(ratio);
		let change = order.amount.sub(minimumZCB).add(new BN(100)).neg();
		await test_modify(change, "4", "0", 10, false, true);
		//add back
		await test_modify(change.neg(), "4", "0", 10, false, true);
		//tets again with removeUnderMinimum:true
		await test_modify(change, "4", "0", 10, true, true);
	});

	it('Resupply Liquidity to ZCB Sell side of orderbook', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(200));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["3", "7", "5"];
		await test_place_limit_order(amtZCB, MCR, "7", "0", expectedIDs, true);
		expectedIDs = ["3", "7", "8", "5"];
		await test_place_limit_order(amtZCB, MCR, "8", "0", expectedIDs, true);
	});

	//other side of orderbook

	it('limitSellYT at head, blank list', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(800));
		let MCR = _10To18.mul(new BN(6));
		let expectedIDs = ["9"];
		await test_place_limit_order(amtYT, MCR, "9", "0", expectedIDs, false);
	});

	it('limitSellYT at head, head exists', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(900));
		let MCR = _10To18.mul(new BN(3));
		let expectedIDs = ["10", "9"];
		await test_place_limit_order(amtYT, MCR, "10", "0", expectedIDs, false);
	});

	it('limitSellYT in middle, no hint', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(700));
		let MCR = _10To18.mul(new BN(4));
		let expectedIDs = ["10", "11", "9"];
		await test_place_limit_order(amtYT, MCR, "11", "0", expectedIDs, false);
	});

	it('limitSellYT in middle, use hint', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(450));
		let MCR = _10To18.mul(new BN(5));
		let expectedIDs = ["10", "11", "12", "9"];
		await test_place_limit_order(amtYT, MCR, "12", "11", expectedIDs, false);
	});

	it('limitSellYT at tail, no hint', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(870));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["10", "11", "12", "9", "13"];
		await test_place_limit_order(amtYT, MCR, "13", "0", expectedIDs, false);
	});

	it('limitSellYT at tail, use hint', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(900));
		let MCR = _10To18.mul(new BN(7));
		let expectedIDs = ["10", "11", "12", "9", "13", "14"];
		await test_place_limit_order(amtYT, MCR, "14", "9", expectedIDs, false);
	});

	it('cannot limitSellYT where MCR is under current ratio', async () => {
		await addRewards();
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
		await addRewards();
		await test_modify(_10To18.neg(), "10", "0", 10, false, false);
	});

	it('modifyYTLimitSell in middle, no hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(5000)), "12", "0", 10, false, false);
	});

	it('modifyYTLimitSell in middle, use hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(1000)), "13", "12", 10, false, false);
	});

	it('modifyYTLimitSell at tail, no hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(7000)).neg(), "14", "0", 10, false, false);
	});

	it('modifyYTLimitSell at tail, use hint', async () => {
		await addRewards();
		await test_modify(_10To18.div(new BN(9000)).neg(), "14", "13", 10, false, false);
	});

	it('modifyYTLimitSell at head, reultant amount under minimum', async () => {
		await addRewards();
		let order = await exchange.YTSells("11");
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		//YT == U / ((1 - zcbDilutiontoMatutity) * ratio)
		let dilutionToMaturity = ratio.mul(_10To18).div(order.maturityConversionRate);
		let minimumYT = minimumOrderSize.mul(_10To18).div(_10To18.sub(dilutionToMaturity).mul(ratio).div(_10To18));
		let change = order.amount.sub(minimumYT).add(new BN(100)).neg();
		await test_modify(change, "11", "0", 10, false, false);
		//add back
		await test_modify(change.neg(), "11", "0", 10, false, false);
		//tets again with removeUnderMinimum:true
		await test_modify(change, "11", "0", 10, true, false);
	});

	it('modifyYTLimitSell in middle use hint, reultant amount under minimum', async () => {
		await addRewards();
		let order = await exchange.YTSells("9");
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		//YT == U / ((1 - zcbDilutiontoMatutity) * ratio)
		let dilutionToMaturity = ratio.mul(_10To18).div(order.maturityConversionRate);
		let minimumYT = minimumOrderSize.mul(_10To18).div(_10To18.sub(dilutionToMaturity).mul(ratio).div(_10To18));
		let change = order.amount.sub(minimumYT).add(new BN(100)).neg();
		await test_modify(change, "9", "12", 10, false, false);
		//add back
		await test_modify(change.neg(), "9", "12", 10, false, false);
		//tets again with removeUnderMinimum:true
		await test_modify(change, "9", "12", 10, true, false);
	});

	it('modifyYTLimitSell at tail no hint, reultant amount under minimum', async () => {
		let order = await exchange.YTSells("14");
		await addRewards();
		let minimumOrderSize = await exchange.getMinimumOrderSize();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		//YT == U / ((1 - zcbDilutiontoMatutity) * ratio)
		let dilutionToMaturity = ratio.mul(_10To18).div(order.maturityConversionRate);
		let minimumYT = minimumOrderSize.mul(_10To18).div(_10To18.sub(dilutionToMaturity).mul(ratio).div(_10To18));
		let change = order.amount.sub(minimumYT).add(new BN(100)).neg();
		await test_modify(change, "14", "0", 10, false, false);
		//add back
		await test_modify(change.neg(), "14", "0", 10, false, false);
		//tets again with removeUnderMinimum:true
		await test_modify(change, "14", "0", 10, true, false);
	});

	it('Resupply Liquidity to YT Sell side of orderbook', async () => {
		await addRewards();
		let amtYT = _10To18.div(new BN(450));
		let MCR = _10To18.mul(new BN(6));
		let expectedIDs = ["12", "15", "13"];
		await test_place_limit_order(amtYT, MCR, "15", "12", expectedIDs, false);
		expectedIDs = ["12", "15", "16", "13"];
		await test_place_limit_order(amtYT, MCR, "16", "0", expectedIDs, false);
	});

	function impliedZCBamount(amountYT, ratio, MCR) {
		let yieldToMaturity = MCR.mul(_10To18).div(ratio);
		let dynamicYT = amountYT.mul(ratio).div(_10To18);
		let amountZCB = dynamicYT.mul(yieldToMaturity.sub(_10To18)).div(_10To18);
		return amountZCB;
	}

	function impliedYTamount(amountZCB, ratio, MCR) {
		let yieldToMaturity = MCR.mul(_10To18).div(ratio);
		let dynamicYT = amountZCB.mul(_10To18).div(yieldToMaturity.sub(_10To18));
		let amountYT = dynamicYT.mul(_10To18).div(ratio);
		return amountYT;
	}

	async function test_market_buy_YT(amtToBuy, maxMCR, maxCumulativeMCR, maxSteps) {
		let orderbook = [];
		let currentID = (await exchange.headYTSellID()).toString();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		while (currentID !== "0") {
			let order = await exchange.YTSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}

		let prevBalBonds = await exchange.BondDeposited(accounts[1]);
		let prevBalYield = await exchange.YieldDeposited(accounts[1]);


		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let prevBondRevenue = prevSubAcctPosTreasury.bond;
		let prevYieldRevenue = prevSubAcctPosTreasury.yield;

		let rec = await exchange.marketBuyYT(amtToBuy, maxMCR, maxCumulativeMCR, maxSteps, true, {from: accounts[1]});
		let log = rec.receipt.logs[0];
		assert.equal(log.event, 'MarketBuyYT');
		let logArgs = log.args;

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let bondRevenue = subAcctPosTreasury.bond;
		let yieldRevenue = subAcctPosTreasury.yield;

		balBonds = await exchange.BondDeposited(accounts[1]);
		balYield = await exchange.YieldDeposited(accounts[1]);

		let expectedResultantOrderbook = [...orderbook];
		for (let i = 0; i < expectedResultantOrderbook.length; i++) {
			expectedResultantOrderbook[i] = {...expectedResultantOrderbook[i]}; //clone each object
		}
		let remaining = amtToBuy;
		let ZCBsold = new BN(0);
		while (
			remaining.toString() !== "0" &&
			expectedResultantOrderbook.length > 0 &&
			expectedResultantOrderbook[0].maturityConversionRate.cmp(maxMCR) != 1
		) {
			let order = expectedResultantOrderbook[0];
			let cmp = remaining.cmp(order.amount);
			let orderZCBamt = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			if (cmp === -1) {
				//partially accept order, set remaining to 0
				let scaledZCBamt = orderZCBamt.mul(remaining);
				scaledZCBamt = scaledZCBamt.div(order.amount).add(new BN(scaledZCBamt.mod(order.amount).toString() === "0" ? 0 : 1));

				order.amount = order.amount.sub(remaining);
				ZCBsold = ZCBsold.add(scaledZCBamt);
				remaining = new BN(0);
			}
			else {
				//delete order from list & decrement remaining
				remaining = remaining.sub(order.amount);
				expectedResultantOrderbook.shift();
				ZCBsold = ZCBsold.add(orderZCBamt);
			}
		}
		let fee = ZCBsold.mul(new BN(FeeBips)).div(new BN(10_000));
		ZCBsold = ZCBsold.add(fee);

		assert.equal(logArgs.newYTSellHeadID.toString(), expectedResultantOrderbook[0].ID.toString());
		assert.equal(logArgs.headAmount.toString(), expectedResultantOrderbook[0].amount.toString());
		assert.equal(logArgs.taker, accounts[1]);

		assert.equal(bondRevenue.sub(prevBondRevenue).toString(), fee.toString());
		assert.equal(yieldRevenue.toString(), prevYieldRevenue.toString());

		let YTbought = amtToBuy.sub(remaining);
		orderbook = [];
		currentID = (await exchange.headYTSellID()).toString();
		while (currentID !== "0") {
			let order = await exchange.YTSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		assert.equal(orderbook.length, expectedResultantOrderbook.length);
		for (let i = 0; i < orderbook.length; i++) {
			assert.equal(orderbook[i].amount.toString(), expectedResultantOrderbook[i].amount.toString());
			assert.equal(orderbook[i].maturityConversionRate.toString(), expectedResultantOrderbook[i].maturityConversionRate.toString());
			assert.equal(orderbook[i].maker, expectedResultantOrderbook[i].maker);
			assert.equal(orderbook[i].nextID.toString(), expectedResultantOrderbook[i].nextID.toString());
		}

		let dynamicYTbought = YTbought.mul(ratio).div(_10To18);
		assert.equal(balYield.sub(prevBalYield).toString(), YTbought.toString());
		let changeBondNum = prevBalBonds.sub(balBonds).toString();
		assert.equal(changeBondNum, dynamicYTbought.add(ZCBsold).toString());
		await assert_valid_subaccount_position(accounts[0]);
		await assert_valid_subaccount_position(accounts[1]);
		return rec;
	}

	async function test_market_sell_ZCB(amtToSell, maxMCR, maxCumulativeMCR, maxSteps) {
		let orderbook = [];
		let currentID = (await exchange.headYTSellID()).toString();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		while (currentID !== "0") {
			let order = await exchange.YTSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}

		let defAmtToSell = amtToSell.mul(new BN(10_000)).div(new BN(10_000 + FeeBips));
		let prevBalBonds = await exchange.BondDeposited(accounts[1]);
		let prevBalYield = await exchange.YieldDeposited(accounts[1]);

		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let prevBondRevenue = prevSubAcctPosTreasury.bond;
		let prevYieldRevenue = prevSubAcctPosTreasury.yield;

		let rec = await exchange.marketSellZCB(amtToSell, maxMCR, maxCumulativeMCR, maxSteps, true, {from: accounts[1]});
		let log = rec.receipt.logs[0];
		assert.equal(log.event, 'MarketBuyYT');
		let logArgs = log.args;

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let bondRevenue = subAcctPosTreasury.bond;
		let yieldRevenue = subAcctPosTreasury.yield;

		balBonds = await exchange.BondDeposited(accounts[1]);
		balYield = await exchange.YieldDeposited(accounts[1]);

		let expectedResultantOrderbook = [...orderbook];
		for (let i = 0; i < expectedResultantOrderbook.length; i++) {
			expectedResultantOrderbook[i] = {...expectedResultantOrderbook[i]}; //clone each object
		}
		let remaining = defAmtToSell;
		let YTbought = new BN(0);

		while (
			remaining.toString() !== "0" &&
			expectedResultantOrderbook.length > 0 &&
			expectedResultantOrderbook[0].maturityConversionRate.cmp(maxMCR) != 1
		) {
			let order = expectedResultantOrderbook[0];
			let orderZCBamount = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			let cmp = remaining.cmp(orderZCBamount);
			if (cmp === -1) {
				//partially accept order, set remaining to 0
				let scaledYTamt = order.amount.mul(remaining).div(orderZCBamount);

				order.amount = order.amount.sub(scaledYTamt);
				YTbought = YTbought.add(scaledYTamt);
				remaining = new BN(0);
			}
			else {
				//delete order from list & decrement remaining
				remaining = remaining.sub(orderZCBamount);
				expectedResultantOrderbook.shift();
				YTbought = YTbought.add(order.amount);
			}
		}

		assert.equal(logArgs.newYTSellHeadID.toString(), expectedResultantOrderbook[0].ID.toString());
		assert.equal(logArgs.headAmount.toString(), expectedResultantOrderbook[0].amount.toString());
		assert.equal(logArgs.taker, accounts[1]);

		let ZCBsold = defAmtToSell.sub(remaining);
		let fee = ZCBsold.mul(new BN(FeeBips)).div(new BN(10_000));
		ZCBsold = ZCBsold.add(fee);

		assert.equal(bondRevenue.sub(prevBondRevenue).toString(), fee.toString());
		assert.equal(yieldRevenue.toString(), prevYieldRevenue.toString());

		orderbook = [];
		currentID = (await exchange.headYTSellID()).toString();
		while (currentID !== "0") {
			let order = await exchange.YTSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		assert.equal(orderbook.length, expectedResultantOrderbook.length);
		for (let i = 0; i < orderbook.length; i++) {
			assert.equal(orderbook[i].amount.toString(), expectedResultantOrderbook[i].amount.toString());
			assert.equal(orderbook[i].maturityConversionRate.toString(), expectedResultantOrderbook[i].maturityConversionRate.toString());
			assert.equal(orderbook[i].maker, expectedResultantOrderbook[i].maker);
			assert.equal(orderbook[i].nextID.toString(), expectedResultantOrderbook[i].nextID.toString());
		}

		let dynamicYTbought = YTbought.mul(ratio).div(_10To18);
		assert.equal(balYield.sub(prevBalYield).toString(), YTbought.toString());
		let changeBondNum = prevBalBonds.sub(balBonds).toString();
		assert.equal(changeBondNum, dynamicYTbought.add(ZCBsold).toString());
		await assert_valid_subaccount_position(accounts[0]);
		await assert_valid_subaccount_position(accounts[1]);
		return rec;
	}

	async function test_market_buy_ZCB(amtToBuy, minMCR, minCumulativeMCR, maxSteps) {
		let orderbook = [];
		let currentID = (await exchange.headZCBSellID()).toString();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		while (currentID !== "0") {
			let order = await exchange.ZCBSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}

		let prevBalBonds = await exchange.BondDeposited(accounts[1]);
		let prevBalYield = await exchange.YieldDeposited(accounts[1]);

		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let prevBondRevenue = prevSubAcctPosTreasury.bond;
		let prevYieldRevenue = prevSubAcctPosTreasury.yield;

		let rec = await exchange.marketBuyZCB(amtToBuy, minMCR, minCumulativeMCR, maxSteps, true, {from: accounts[1]});
		let log = rec.receipt.logs[0];
		assert.equal(log.event, 'MarketBuyZCB');
		let logArgs = log.args;

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let bondRevenue = subAcctPosTreasury.bond;
		let yieldRevenue = subAcctPosTreasury.yield;

		balBonds = await exchange.BondDeposited(accounts[1]);
		balYield = await exchange.YieldDeposited(accounts[1]);

		let expectedResultantOrderbook = [...orderbook];
		for (let i = 0; i < expectedResultantOrderbook.length; i++) {
			expectedResultantOrderbook[i] = {...expectedResultantOrderbook[i]}; //clone each object
		}
		let remaining = amtToBuy;
		let YTsold = new BN(0);
		while (
			remaining.toString() !== "0" &&
			expectedResultantOrderbook.length > 0 &&
			expectedResultantOrderbook[0].maturityConversionRate.cmp(minMCR) != -1
		) {
			let order = expectedResultantOrderbook[0];
			let cmp = remaining.cmp(order.amount);
			let orderYTamt = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			if (cmp === -1) {
				//partially accept order, set remaining to 0
				let scaledYTamt = orderYTamt.mul(remaining);
				scaledYTamt = scaledYTamt.div(order.amount).add(new BN(scaledYTamt.mod(order.amount).toString() === "0" ? 0 : 1));

				order.amount = order.amount.sub(remaining);
				YTsold = YTsold.add(scaledYTamt);
				remaining = new BN(0);
			}
			else {
				//delete order from list & decrement remaining
				remaining = remaining.sub(order.amount);
				expectedResultantOrderbook.shift();
				YTsold = YTsold.add(orderYTamt);
			}
		}
		let fee = YTsold.mul(new BN(FeeBips)).div(new BN(10_000));
		YTsold = YTsold.add(fee);

		assert.equal(logArgs.newZCBSellHeadID.toString(), expectedResultantOrderbook[0].ID.toString());
		assert.equal(logArgs.headAmount.toString(), expectedResultantOrderbook[0].amount.toString());
		assert.equal(logArgs.taker, accounts[1]);

		let bondNum = fee.mul(ratio).div(_10To18);
		assert.equal(prevBondRevenue.sub(bondRevenue).toString(), bondNum.toString());
		assert.equal(yieldRevenue.sub(prevYieldRevenue).toString(), fee.toString());

		let ZCBbought = amtToBuy.sub(remaining);
		orderbook = [];
		currentID = (await exchange.headZCBSellID()).toString();
		while (currentID !== "0") {
			let order = await exchange.ZCBSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		assert.equal(orderbook.length, expectedResultantOrderbook.length);
		for (let i = 0; i < orderbook.length; i++) {
			assert.equal(orderbook[i].amount.toString(), expectedResultantOrderbook[i].amount.toString());
			assert.equal(orderbook[i].maturityConversionRate.toString(), expectedResultantOrderbook[i].maturityConversionRate.toString());
			assert.equal(orderbook[i].maker, expectedResultantOrderbook[i].maker);
			assert.equal(orderbook[i].nextID.toString(), expectedResultantOrderbook[i].nextID.toString());
		}

		let dynamicYTsold = YTsold.mul(ratio).div(_10To18);
		let change = prevBalYield.sub(balYield);
		let expected = YTsold;
		let diff = change.sub(expected).abs();
		let cmp = diff.cmp(new BN(3));
		assert.equal(cmp, -1, "acceptable range of error is 2 units");
		let changeBondNum = balBonds.sub(prevBalBonds).toString();
		assert.equal(changeBondNum, dynamicYTsold.add(ZCBbought).toString());
		await assert_valid_subaccount_position(accounts[0]);
		await assert_valid_subaccount_position(accounts[1]);
		return rec;
	}

	async function test_market_sell_YT(amtToSell, minMCR, minCumulativeMCR, maxSteps) {
		let orderbook = [];
		let currentID = (await exchange.headZCBSellID()).toString();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		while (currentID !== "0") {
			let order = await exchange.ZCBSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		let defAmtToSell = amtToSell.mul(new BN(10_000)).div(new BN(10_000 + FeeBips));
		let prevBalBonds = await exchange.BondDeposited(accounts[1]);
		let prevBalYield = await exchange.YieldDeposited(accounts[1]);

		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let prevBondRevenue = prevSubAcctPosTreasury.bond;
		let prevYieldRevenue = prevSubAcctPosTreasury.yield;

		let rec = await exchange.marketSellYT(amtToSell, minMCR, minCumulativeMCR, maxSteps, true, {from: accounts[1]});
		let log = rec.receipt.logs[0];
		assert.equal(log.event, 'MarketBuyZCB');
		let logArgs = log.args;

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let bondRevenue = subAcctPosTreasury.bond;
		let yieldRevenue = subAcctPosTreasury.yield;

		balBonds = await exchange.BondDeposited(accounts[1]);
		balYield = await exchange.YieldDeposited(accounts[1]);

		let expectedResultantOrderbook = [...orderbook];
		for (let i = 0; i < expectedResultantOrderbook.length; i++) {
			expectedResultantOrderbook[i] = {...expectedResultantOrderbook[i]}; //clone each object
		}
		let remaining = defAmtToSell;
		let ZCBbought = new BN(0);

		while (
			remaining.toString() !== "0" &&
			expectedResultantOrderbook.length > 0 &&
			expectedResultantOrderbook[0].maturityConversionRate.cmp(minMCR) != -1
		) {
			let order = expectedResultantOrderbook[0];
			let orderYTamount = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			let cmp = remaining.cmp(orderYTamount);
			if (cmp === -1) {
				//partially accept order, set remaining to 0
				let scaledZCBamt = order.amount.mul(remaining).div(orderYTamount);

				order.amount = order.amount.sub(scaledZCBamt);
				ZCBbought = ZCBbought.add(scaledZCBamt);
				remaining = new BN(0);
			}
			else {
				//delete order from list & decrement remaining
				remaining = remaining.sub(orderYTamount);
				expectedResultantOrderbook.shift();
				ZCBbought = ZCBbought.add(order.amount);
			}
		}

		assert.equal(logArgs.newZCBSellHeadID.toString(), expectedResultantOrderbook[0].ID.toString());
		assert.equal(logArgs.headAmount.toString(), expectedResultantOrderbook[0].amount.toString());
		assert.equal(logArgs.taker, accounts[1]);

		let YTsold = defAmtToSell.sub(remaining);
		let fee = YTsold.mul(new BN(FeeBips)).div(new BN(10_000));
		YTsold = YTsold.add(fee);

		let bondNum = fee.mul(ratio).div(_10To18);
		assert.equal(prevBondRevenue.sub(bondRevenue).toString(), bondNum.toString());
		assert.equal(yieldRevenue.sub(prevYieldRevenue).toString(), fee.toString());

		orderbook = [];
		currentID = (await exchange.headZCBSellID()).toString();
		while (currentID !== "0") {
			let order = await exchange.ZCBSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		assert.equal(orderbook.length, expectedResultantOrderbook.length);
		for (let i = 0; i < orderbook.length; i++) {
			assert.equal(orderbook[i].amount.toString(), expectedResultantOrderbook[i].amount.toString());
			assert.equal(orderbook[i].maturityConversionRate.toString(), expectedResultantOrderbook[i].maturityConversionRate.toString());
			assert.equal(orderbook[i].maker, expectedResultantOrderbook[i].maker);
			assert.equal(orderbook[i].nextID.toString(), expectedResultantOrderbook[i].nextID.toString());
		}

		let dynamicYTsold = YTsold.mul(ratio).div(_10To18);
		let change = prevBalYield.sub(balYield);
		let expected = YTsold;
		let diff = change.sub(expected).abs();
		let cmp = diff.cmp(new BN(3));
		assert.equal(cmp, -1, "acceptable range of error is 2 units");
		let changeBondNum = balBonds.sub(prevBalBonds).toString();
		assert.equal(changeBondNum, dynamicYTsold.add(ZCBbought).toString());
		await assert_valid_subaccount_position(accounts[0]);
		await assert_valid_subaccount_position(accounts[1]);
		return rec;
	}

	async function market_sell_ZCB_to_U(amtToSell, maxMCR, maxCumulativeMCR, maxSteps) {
		let orderbook = [];
		let currentID = (await exchange.headYTSellID()).toString();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		while (currentID !== "0") {
			let order = await exchange.YTSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}

		let prevBalBonds = await exchange.BondDeposited(accounts[1]);
		let prevBalYield = await exchange.YieldDeposited(accounts[1]);

		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let prevBondRevenue = prevSubAcctPosTreasury.bond;
		let prevYieldRevenue = prevSubAcctPosTreasury.yield;

		let rec = await exchange.marketSellZCBtoU(amtToSell, maxMCR, maxCumulativeMCR, maxSteps, true, {from: accounts[1]});
		let log = rec.receipt.logs[0];
		assert.equal(log.event, 'MarketBuyYT');
		let logArgs = log.args;

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let bondRevenue = subAcctPosTreasury.bond;
		let yieldRevenue = subAcctPosTreasury.yield;

		balBonds = await exchange.BondDeposited(accounts[1]);
		balYield = await exchange.YieldDeposited(accounts[1]);

		let expectedResultantOrderbook = [...orderbook];
		for (let i = 0; i < expectedResultantOrderbook.length; i++) {
			expectedResultantOrderbook[i] = {...expectedResultantOrderbook[i]}; //clone each object
		}
		let remaining = amtToSell;
		let YTbought = new BN(0);

		while (
			expectedResultantOrderbook.length > 0 &&
			expectedResultantOrderbook[0].maturityConversionRate.cmp(maxMCR) != 1
		) {
			let order = expectedResultantOrderbook[0];
			let orderZCBamount = impliedZCBamount(order.amount, ratio, order.maturityConversionRate);
			let orderUnitYTamt = order.amount.mul(ratio).div(_10To18);
			let feeAdjOrderZCBamt = orderZCBamount.mul(new BN(10_000 + FeeBips)).div(new BN(10_000));
			let unitYTbought = YTbought.mul(ratio).div(_10To18);
			let cmp = orderUnitYTamt.add(unitYTbought).cmp(remaining.sub(feeAdjOrderZCBamt));
			if (cmp === 1) {
				//partially accept offer
				/*
					unitAmtYTbought + unitYTtoBuy == _amountZCB - ZCBtoSell
					ZCBtoSell == YTtoBuy * orderRatio
					unitYTtoBuy = YTtoBuy * ratio

					unitAmtYTbought + YTtoBuy*ratio == _amountZCB - YTtoBuy*orderRatio
					YTtoBuy * (orderRatio + ratio) == _amountZCB - unitAmtYTbought
					YTtoBuy == (_amountZCB - unitAmtYTbought) / (orderRatio + ratio)
				*/
				let orderRatio = feeAdjOrderZCBamt.mul(_10To18).div(order.amount);
				let YTtoBuy = remaining.sub(unitYTbought).mul(_10To18).div(orderRatio.add(ratio));
				let ZCBtoSell = YTtoBuy.mul(orderRatio).div(_10To18);

				order.amount = order.amount.sub(YTtoBuy);
				YTbought = YTbought.add(YTtoBuy);
				remaining = remaining.sub(ZCBtoSell);
			}
			else {
				//delete order from list & decrement remaining
				remaining = remaining.sub(feeAdjOrderZCBamt);
				expectedResultantOrderbook.shift();
				YTbought = YTbought.add(order.amount);
			}
			if (cmp !== -1) break; //lazy hack
		}

		assert.equal(logArgs.newYTSellHeadID.toString(), expectedResultantOrderbook[0].ID.toString());
		assert.equal(logArgs.headAmount.toString(), expectedResultantOrderbook[0].amount.toString());
		assert.equal(logArgs.taker, accounts[1]);

		let ZCBsold = amtToSell.sub(remaining);
		let totalZCBreceived = ZCBsold.mul(new BN(10_000)).div(new BN(10_000 + FeeBips));
		let fee = ZCBsold.sub(totalZCBreceived).sub(new BN(1));

		assert.equal(bondRevenue.sub(prevBondRevenue).toString(), fee.toString());
		assert.equal(yieldRevenue.toString(), prevYieldRevenue.toString());
		orderbook = [];
		currentID = (await exchange.headYTSellID()).toString();
		while (currentID !== "0") {
			let order = await exchange.YTSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		assert.equal(orderbook.length, expectedResultantOrderbook.length);
		for (let i = 0; i < orderbook.length; i++) {
			assert.equal(orderbook[i].amount.toString(), expectedResultantOrderbook[i].amount.toString());
			assert.equal(orderbook[i].maturityConversionRate.toString(), expectedResultantOrderbook[i].maturityConversionRate.toString());
			assert.equal(orderbook[i].maker, expectedResultantOrderbook[i].maker);
			assert.equal(orderbook[i].nextID.toString(), expectedResultantOrderbook[i].nextID.toString());
		}

		let dynamicYTbought = YTbought.mul(ratio).div(_10To18);
		assert.equal(balYield.sub(prevBalYield).toString(), YTbought.toString());
		let changeBondNum = prevBalBonds.sub(balBonds).toString();
		assert.equal(changeBondNum, dynamicYTbought.add(ZCBsold).toString());
		await assert_valid_subaccount_position(accounts[0]);
		await assert_valid_subaccount_position(accounts[1]);
		return rec;
	}

	async function test_market_sell_unitYT_to_U(amtToSell, minMCR, minCumulativeMCR, maxSteps) {
		let orderbook = [];
		let currentID = (await exchange.headZCBSellID()).toString();
		let ratio = await NGBwrapperInstance.WrappedAmtToUnitAmt_RoundDown(_10To18);
		while (currentID !== "0") {
			let order = await exchange.ZCBSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}

		let prevBalBonds = await exchange.BondDeposited(accounts[1]);
		let prevBalYield = await exchange.YieldDeposited(accounts[1]);

		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let prevBondRevenue = prevSubAcctPosTreasury.bond;
		let prevYieldRevenue = prevSubAcctPosTreasury.yield;

		let rec = await exchange.marketSellUnitYTtoU(amtToSell, minMCR, minCumulativeMCR, maxSteps, true, {from: accounts[1]});
		let log = rec.receipt.logs[0];
		assert.equal(log.event, 'MarketBuyZCB');
		let logArgs = log.args;

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let bondRevenue = subAcctPosTreasury.bond;
		let yieldRevenue = subAcctPosTreasury.yield;

		balBonds = await exchange.BondDeposited(accounts[1]);
		balYield = await exchange.YieldDeposited(accounts[1]);

		let expectedResultantOrderbook = [...orderbook];
		for (let i = 0; i < expectedResultantOrderbook.length; i++) {
			expectedResultantOrderbook[i] = {...expectedResultantOrderbook[i]}; //clone each object
		}
		let remaining = amtToSell;
		let ZCBbought = new BN(0);

		while (
			expectedResultantOrderbook.length > 0 &&
			expectedResultantOrderbook[0].maturityConversionRate.cmp(minMCR) != -1
		) {
			let order = expectedResultantOrderbook[0];
			let orderYTamount = impliedYTamount(order.amount, ratio, order.maturityConversionRate);
			let orderUnitYTamount = orderYTamount.mul(ratio).div(_10To18);
			let feeAdjOrderUnitYTamt = orderUnitYTamount.mul(new BN(10_000 + FeeBips)).div(new BN(10_000));
			let lhs = ZCBbought.add(order.amount);
			let rhs = remaining.sub(feeAdjOrderUnitYTamt);
			let cmp = lhs.cmp(rhs);
			if (cmp === 1) {
				/*
					_unitAmountYT - unitYTtoSell == ZCBbought + ZCBtoBuy
					ZCBtoBuy == unitYTtoSell * orderRatio
					YTtoSell = unitYTtoSell / ratio

					_unitAmountYT - unitYTtoSell == ZCBbought + unitYTtoSell*orderRatio
					unitYTtoSell*(orderRatio + 1) == _unitAmountYT - ZCBbought
					unitYTtoSell == (_unitAmountYT - ZCBbought) / (orderRatio + 1)
				*/
				let orderRatio = order.amount.mul(_10To18).div(feeAdjOrderUnitYTamt);
				let unitYTtoSell = remaining.sub(ZCBbought).mul(_10To18).div(orderRatio.add(_10To18));
				let ZCBtoBuy = unitYTtoSell.mul(orderRatio).div(_10To18);
				let YTtoSell = unitYTtoSell.mul(_10To18).div(ratio);

				order.amount = order.amount.sub(ZCBtoBuy);
				ZCBbought = ZCBbought.add(ZCBtoBuy);
				remaining = remaining.sub(unitYTtoSell);
			}
			else {
				//delete order from list & decrement remaining
				remaining = remaining.sub(feeAdjOrderUnitYTamt);
				expectedResultantOrderbook.shift();
				ZCBbought = ZCBbought.add(order.amount);
			}
			if (cmp !== -1) break; //lazy hack
		}

		assert.equal(logArgs.newZCBSellHeadID.toString(), expectedResultantOrderbook[0].ID.toString());
		assert.equal(logArgs.headAmount.toString(), expectedResultantOrderbook[0].amount.toString());
		assert.equal(logArgs.taker, accounts[1]);

		let dynamicYTsold = amtToSell.sub(remaining);
		let YTsold = dynamicYTsold.mul(_10To18).div(ratio);
		let totalYTreceived = YTsold.mul(new BN(10_000)).div(new BN(10_000 + FeeBips));
		let fee = YTsold.sub(totalYTreceived).sub(new BN(1));

		let bondNum = fee.mul(ratio).div(_10To18);
		assert.equal(prevBondRevenue.sub(bondRevenue).toString(), bondNum.toString());
		assert.equal(yieldRevenue.sub(prevYieldRevenue).toString(), fee.toString());

		orderbook = [];
		currentID = (await exchange.headZCBSellID()).toString();
		while (currentID !== "0") {
			let order = await exchange.ZCBSells(currentID);
			order.ID = currentID;
			orderbook.push(order);
			currentID = order.nextID.toString();
		}
		assert.equal(orderbook.length, expectedResultantOrderbook.length);
		for (let i = 0; i < orderbook.length; i++) {
			assert.equal(orderbook[i].amount.toString(), expectedResultantOrderbook[i].amount.toString());
			assert.equal(orderbook[i].maturityConversionRate.toString(), expectedResultantOrderbook[i].maturityConversionRate.toString());
			assert.equal(orderbook[i].maker, expectedResultantOrderbook[i].maker);
			assert.equal(orderbook[i].nextID.toString(), expectedResultantOrderbook[i].nextID.toString());
		}

		let change = prevBalYield.sub(balYield);
		let expected = YTsold;
		let diff = change.sub(expected).abs();
		let cmp = diff.cmp(new BN(3));
		assert.equal(cmp, -1, "acceptable range of error is 2 units");
		let changeBondNum = balBonds.sub(prevBalBonds);
		expected = dynamicYTsold.add(ZCBbought);
		diff = parseInt(changeBondNum.sub(expected).toString());
		assert.isBelow(diff, 1, "actual must be less than or equal to expected");
		assert.isBelow(Math.abs(diff), 3, "acceptable range of error is 2 units");
		await assert_valid_subaccount_position(accounts[0]);
		await assert_valid_subaccount_position(accounts[1]);
		return rec;
	}

	it('marketBuyYT, no mcr blockers', async () => {
		await addRewards();
		let amtToBuy = _10To18.div(new BN(300));
		let maxMCR = _10To18.mul(new BN(10));
		let maxCumulativeMCR = maxMCR;
		let maxSteps = 10;
		let func = async () => await test_market_buy_YT(amtToBuy, maxMCR, maxCumulativeMCR, maxSteps);
		await test_and_check_oracle(func);
	});

	it('marketSellZCB, no mcr blockers', async () => {
		await addRewards();
		let amtToSell = _10To18.div(new BN(780));
		let maxMCR = _10To18.mul(new BN(10));
		let maxCumulativeMCR = maxMCR;
		let maxSteps = 10;
		let func = async () => await test_market_sell_ZCB(amtToSell, maxMCR, maxCumulativeMCR, maxSteps);
		await test_and_check_oracle(func);
	});

	it('marketBuyZCB, no mcr blockers', async () => {
		await addRewards();
		let amtToBuy = _10To18.div(new BN(300));
		let minMCR = _10To18.div(new BN(10));
		let minCumulativeMCR = minMCR;
		let maxSteps = 10;
		let func = async () => await test_market_buy_ZCB(amtToBuy, minMCR, minCumulativeMCR, maxSteps);
		await test_and_check_oracle(func);
	});

	it('marketSellYT, no mcr blockers', async () => {
		await addRewards();
		let amtToSell = _10To18.div(new BN(780));
		let minMCR = _10To18.div(new BN(10));
		let minCumulativeMCR = minMCR;
		let maxSteps = 10;
		let func = async () => await test_market_sell_YT(amtToSell, minMCR, minCumulativeMCR, maxSteps);
		await test_and_check_oracle(func);
	});

	it('marketSellZCBtoU, no mcr blockers', async () => {
		await addRewards();
		let amtZCB = _10To18.div(new BN(780));
		let maxMCR = _10To18.mul(new BN(10));
		let maxCumulativeMCR = maxMCR;
		let maxSteps = 10;
		let func = async () => await market_sell_ZCB_to_U(amtZCB, maxMCR, maxCumulativeMCR, maxSteps);
		await test_and_check_oracle(func);
	});

	it('marketSellUnitYTtoU, no mcr blockers', async () => {
		await addRewards();
		let unitAmtToSell = _10To18.div(new BN(780));
		let minMCR = _10To18.div(new BN(10));
		let minCumulativeMCR = minMCR;
		let maxSteps = 10;
		let func = async () => await test_market_sell_unitYT_to_U(unitAmtToSell, minMCR, minCumulativeMCR, maxSteps);
		await test_and_check_oracle(func);
	});

	it('Set Oracle MCR', async () => {
		await addRewards();
		let orcData = await exchange.getOracleData();
		for (let i = LENGTH_RATE_SERIES-1; orcData._impliedMCRs[i].cmp(new BN(0)) === 0; i--) {
			await helper.advanceTime(61);
			await exchange.forceRateDataUpdate();
		}
		orcData = await exchange.getOracleData();
		assert.notEqual(orcData._impliedMCRs[LENGTH_RATE_SERIES-1].toString(), "0");
		let median = medianBN(orcData._impliedMCRs);
		await exchange.setOracleMCR(median);
		orcData = await exchange.getOracleData();
		assert.equal(orcData._oracleMCR.toString(), median.toString());
	});

	it('Cannot Set wrong MCR', async () => {
		let orcData = await exchange.getOracleData();
		let median = medianBN(orcData._impliedMCRs);
		let notMedian = median.add(new BN(100));
		let caught = false;
		try {
			await exchange.setOracleMCR(notMedian);
		} catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail('managed to set the wrong median MCR as the MCR');
		}
	});
	it('Claim Revenue', async () => {
		let owner = accounts[0];
		let prevSubAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let YR = prevSubAcctPosTreasury.yield;
		let BR = prevSubAcctPosTreasury.bond;
		let prevYieldTreasury = await fixCapitalPoolInstance.balanceYield(treasuryAddress);
		let prevBondTreasury = await fixCapitalPoolInstance.balanceBonds(treasuryAddress);
		let prevYieldOwner = await fixCapitalPoolInstance.balanceYield(owner);
		let prevBondOwner = await fixCapitalPoolInstance.balanceBonds(owner);

		await exchange.claimRevenue();

		let subAcctPosTreasury = await NGBwrapperInstance.subAccountPositions(exchange.address, treasuryAddress, fixCapitalPoolInstance.address);
		let yieldTreasury = await fixCapitalPoolInstance.balanceYield(treasuryAddress);
		let bondTreasury = await fixCapitalPoolInstance.balanceBonds(treasuryAddress);
		let yieldOwner = await fixCapitalPoolInstance.balanceYield(owner);
		let bondOwner = await fixCapitalPoolInstance.balanceBonds(owner);
		let expectedYieldToTreasury = YR.div(new BN(2));
		let expectedBondToTreasury = BR.div(new BN(2));
		let expectedYieldToOwner = YR.sub(expectedYieldToTreasury);
		let expectedBondToOwner = BR.sub(expectedBondToTreasury);
		assert.equal(subAcctPosTreasury.yield.toString(), "0");
		assert.equal(subAcctPosTreasury.bond.toString(), "0");
		assert.equal(prevSubAcctPosTreasury.yield.toString(), YR.toString());
		assert.equal(prevSubAcctPosTreasury.bond.toString(), BR.toString());
		assert.equal(yieldTreasury.sub(prevYieldTreasury).toString(), expectedYieldToTreasury.toString());
		assert.equal(bondTreasury.sub(prevBondTreasury).toString(), expectedBondToTreasury.toString());
		assert.equal(yieldOwner.sub(prevYieldOwner).toString(), expectedYieldToOwner.toString());
		assert.equal(bondOwner.sub(prevBondOwner).toString(), expectedBondToOwner.toString());
	});

	it('Handle all sub account obligations', async () => {
		let cumulativePositions = {yield: new BN(0), bond: new BN(0)};
		for (let i = 0; i < accounts.length; i++) {
			let subAcctPos = await NGBwrapperInstance.subAccountPositions(exchange.address, accounts[i], fixCapitalPoolInstance.address);
			cumulativePositions.yield = cumulativePositions.yield.add(subAcctPos.yield);
			cumulativePositions.bond = cumulativePositions.bond.add(subAcctPos.bond);
			await exchange.forceClaimSubAccountRewards({from: accounts[i]});
		}
		let subAcctPosContract = await NGBwrapperInstance.subAccountPositions(fixCapitalPoolInstance.address, exchange.address, fixCapitalPoolInstance.address);
		let yieldErr = subAcctPosContract.yield.sub(cumulativePositions.yield);
		let bondErr = subAcctPosContract.bond.sub(cumulativePositions.bond);
		assert.equal(yieldErr.cmp(new BN(-1)), 1, "cumulative yield of sub accounts must be less than or equal to total yield of distribution account");
		assert.equal(yieldErr.cmp(new BN(100)), -1, "diff between cumulative yield of sub accts and total dist acct yield must be under 100");
		assert.equal(bondErr.cmp(yieldErr.neg()), 1, "cumulative sub acct bond - total dist acct bond must be greater than negative yield error");
		assert.equal(bondErr.abs().cmp(new BN(100)), -1, "diff between cumulative bond of sub accts and total dist acct bond must be under 100");
		let rewards = (await NGBwrapperInstance.distributionAccountRewards(0, exchange.address)).toNumber();
		assert.isBelow(rewards, 100, "untouched rewards are within accpetable error range");
	});

	it('Withdraw locked funds after payout phase', async () => {
		await addRewards();
		//make limit orders
		let amt = _10To18.div(new BN(34287));
		let MCR = _10To18.mul(new BN(4));
		let hintID = "0";
		let maxSteps = 10;
		let rec0 = await exchange.limitSellYT(amt, MCR, hintID, maxSteps);
		let rec1 = await exchange.limitSellZCB(amt, MCR, hintID, maxSteps);
		YD = await exchange.YieldDeposited(accounts[0]);
		BD = await exchange.BondDeposited(accounts[0]);
		let lockedYT = await exchange.lockedYT(accounts[0]);
		let lockedZBC = await exchange.lockedZCB(accounts[0]);
		assert.equal(lockedYT.cmp(new BN(0)), 1);
		assert.equal(lockedZCB.cmp(new BN(0)), 1);

		//funds are now locked
		//advance to payout phase
		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		let toAdvance = maturity - timestamp + 1;
		await helper.advanceTime(toAdvance);
		await fixCapitalPoolInstance.enterPayoutPhase();
		let prevYieldA0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevBondA0 = await fixCapitalPoolInstance.balanceBonds(accounts[0]);

		await exchange.withdraw(YD, BD);

		let prevYD = YD;
		let prevBD = BD;
		let yieldA0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let bondA0 = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		YD = await exchange.YieldDeposited(accounts[0]);
		BD = await exchange.BondDeposited(accounts[0]);
		assert.equal(YD.toString(), "0");
		assert.equal(BD.toString(), "0");
		assert.equal(yieldA0.sub(prevYieldA0).toString(), prevYD.toString());
		assert.equal(bondA0.sub(prevBondA0).toString(), prevBD.toString());
		for (let i = 1; i < accounts.length; i++) {
			await addRewards();
			let y = await exchange.YieldDeposited(accounts[i]);
			let b = await exchange.BondDeposited(accounts[i]);
			await exchange.withdraw(y, b, {from: accounts[i]});
		}
		let subAcctPosContract = await NGBwrapperInstance.subAccountPositions(fixCapitalPoolInstance.address, exchange.address, fixCapitalPoolInstance.address);
		assert.equal(subAcctPosContract.yield.cmp(new BN(100)), -1, "total dist acct yield must be under 100");
		assert.equal(subAcctPosContract.bond.cmp(subAcctPosContract.yield.neg()), 1, "total dist acct bond must be greater than negative dist acct yield");
		assert.equal(subAcctPosContract.bond.abs().cmp(new BN(100)), -1, "abs of total dist acct bond must be under 100");
		let rewards = (await NGBwrapperInstance.distributionAccountRewards(0, exchange.address)).toNumber();
		assert.isBelow(rewards, 100, "untouched rewards are within accpetable error range");
	});
});