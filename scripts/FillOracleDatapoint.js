const IOrderbookExchange = artifacts.require("IOrderbookExchange");
const fs = require('fs');
const BN = web3.utils.BN;
let Mul, Div, Pow, ApproxNthRoot;
({Mul, Div, Pow, ApproxNthRoot} = require('../helper/BBN.js').getFunctionality(BN));
const helper = require("../helper/otherhelper.js")(web3);

const _0 = new BN(0);
const _1 = new BN(1);
const _2 = new BN(2);
const _10To18 = (new BN(10)).pow(new BN(18));

const NUM_ORACLE_DATAPOINTS = 31;

const OrderbookAddress = "0x581AE398E58f383460CA395a8db70EeA16cD011D";
const targetMCR = _10To18.mul(new BN(41)).div(new BN(10));
const MAX_STEPS = 50;
/*

	This script assumes
		a. This is a local ganache development network
		b. the orderbook is empty
*/



module.exports = async function(callback) {

	try {

	let accounts = await web3.eth.getAccounts();
	let exchange = await IOrderbookExchange.at(OrderbookAddress);

	let yieldBalance = await exchange.YieldDeposited(accounts[1]);
	let bondBalance = await exchange.BondDeposited(accounts[1]);

	let amount = yieldBalance.div(new BN(1000));

	console.log("Set Oracle MCR");

	console.log("Posting Limit Sell ZCB...");
	let rec = await exchange.limitSellZCB(amount, targetMCR, 0, MAX_STEPS, {from: accounts[1]});
	let zcbSellID = rec.receipt.logs[0].args.newID;
	console.log("ZCB Limit Sell successfully Posted");

	console.log("Posting Limit Sell YT...");
	rec = await exchange.limitSellYT(amount, targetMCR, 0, MAX_STEPS, {from: accounts[1]});
	let ytSellID = rec.receipt.logs[0].args.newID;
	console.log("YT Limit Sell successfully Posted ");

	console.log("Updating Rate Data ...");
	for (let i = 0; i < NUM_ORACLE_DATAPOINTS+1; i++) {
		try {
			await exchange.forceRateDataUpdate({from: accounts[1]});
			await helper.advanceTime(61);
		} catch (err) {
			console.error(err);
			callback();
		}
		console.log("Datapoint", i+1, "of", NUM_ORACLE_DATAPOINTS, "Set");
	}
	console.log("Successfully Set All Datapoints");

	console.log("Setting Oracle MCR...");
	let data = await exchange.getOracleData();
	if (data._impliedMCRs[0].sub(targetMCR).abs().gt(_1)) {
		for (let i = 0; i < data._impliedMCRs; i++) {
			console.log(data._impliedMCRs[i].toString());
		}
		let errStr = "Target MCR was "+targetMCR.toString()+" but implied MCR was "+data._impliedMCRs[0].toString();
		console.log(errStr);
		//throw new Error(errStr);
	}
	await exchange.setOracleMCR(data._impliedMCRs[0].toString(), {from: accounts[1]});
	console.log("Oracle MCR successfully set");

	console.log("Removing ZCB Limit Sell...");
	await exchange.modifyZCBLimitSell(amount.mul(new BN(-1)), zcbSellID, 0, MAX_STEPS, true, {from: accounts[1]});
	let order = await exchange.ZCBSells(zcbSellID);
	if (order.amount.gt(_0)) {
		throw new Error("Order was not successfully removed");
	}
	console.log("ZCB Limit Sell Successfully Removed");

	console.log("Removing YT Limit Sell...");
	await exchange.modifyYTLimitSell(amount.mul(new BN(-1)), ytSellID, 0, MAX_STEPS, true, {from: accounts[1]});
	order = await exchange.YTSells(ytSellID);
	if (order.amount.gt(_0)) {
		throw new Error("Order was not successfully removed");
	}
	console.log("YT Limit Sell Successfully Removed");
	} catch (err) {
		console.error(err);
	}

	callback();
}