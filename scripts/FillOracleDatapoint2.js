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

const OrderbookAddress = "0x9df217c3c76b194b131e2dD004e2FCda653A2Ab0";
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

	await exchange.setOracleMCR(data._impliedMCRs[0].toString(), {from: accounts[1]});
	console.log("Oracle MCR successfully set");

	} catch (err) {
		console.error(err);
	}

	callback();
}