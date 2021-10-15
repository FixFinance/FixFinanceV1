const IOrderbookExchange = artifacts.require("IOrderbookExchange");
const IWrapper = artifacts.require("IWrapper");
const fs = require('fs');
const path = require('path');
const BN = web3.utils.BN;
let Mul, Div, Pow, ApproxNthRoot;
({Mul, Div, Pow, ApproxNthRoot} = require('../../helper/BBN.js').getFunctionality(BN));
const _0 = new BN(0);
const _1 = new BN(1);
const _2 = new BN(2);
const _10To18 = (new BN(10)).pow(new BN(18));

const OrderbookAddress = "0x9df217c3c76b194b131e2dD004e2FCda653A2Ab0";

const USE_CURRENT_RATIO_BALANCE_RATIO = false;

const startRatio = new BN("1000000000000000000"); //ratio for which to calculate initial MCRs
let balanceRatio = new BN("1000000000000000000"); //ratio for which to balance liquidity
const numOrdersByZone = [
	new BN("5"),
	new BN("3"),
	new BN("4")
];
const zoneWeightScalars = [
	new BN("1"),
	new BN("5"),
	new BN("1")
];
const zoneMCRBorders = [
	new BN("2000000000000000000"),
	new BN("4000000000000000000"),
	new BN("4500000000000000000"),
	new BN("6500000000000000000")
];

const ROOT_DIR_NAME = 'FixFinanceV1';
const dir = process.cwd();
let split = dir.split('/');
let indexRootDir = split.indexOf(ROOT_DIR_NAME);
while(split.length > indexRootDir+1) split.pop();
const outFilename = split.join('/') + '/scripts/MMBot/GeneratedPlan.json';

async function fileExists(filename) {
	return await new Promise((res, rej) => {
		fs.access(filename, fs.constants.F_OK, (err) => {
			if (err) res(false);
			else res(true);
		})
	});
}

module.exports = async function(callback) {

	try {
		if (await fileExists(outFilename) && fs.readFileSync(outFilename).length > 0) {
			throw new Error("Out File "+outFilename+" must be empty to execute the LoadPlan script");
		}
	} catch (err) {
		console.error(err);
		callback();
		process.exit();
	}


	//Sanity Check
	if (numOrdersByZone.length + 1 != zoneMCRBorders.length) {
		throw new Error("The number of Zone MCR Borders must be exactly 1 greater than the number of zone");
	}

	if (numOrdersByZone.length != zoneWeightScalars.length) {
		throw new Error("The number of zones implied by the numOrderByZone array and zoneWeightScalars array must be the same");
	}

	for (let i = 0; i < numOrdersByZone.length; i++) {
		if (numOrdersByZone[i].lt(_1)) {
			throw new Error("Each Liquidity Zone must have at least one order");
		}
		if (zoneMCRBorders[i].gte(zoneMCRBorders[i+1])) {
			throw new Error("MCR Borders must be ascending");
		}
	}

	let accounts = await web3.eth.getAccounts();
	let exchange = await IOrderbookExchange.at(OrderbookAddress);
	let baseWrapper = await IWrapper.at(await exchange.wrapper());
	let currentRatio = await baseWrapper.WrappedAmtToUnitAmt_RoundDown(_10To18);
	if(currentRatio.eq(_0)) {
		throw new Error("Current wrapped to unit ratio must be greater than 0");
	}
	if (USE_CURRENT_RATIO_BALANCE_RATIO) {
		balanceRatio = currentRatio;
	}

	console.log("-----SANITY CHECKS PASSED-----");

	const zones = (() => {
		let ret = new Array(numOrdersByZone.length);
		for (let i = 0; i < ret.length; i++) {
			let lower = zoneMCRBorders[i];
			let upper = zoneMCRBorders[i+1];

			let lowerYTM = Div(lower, startRatio);
			let upperYTM = Div(upper, startRatio);
			let YTMboundsMultiplier = Div(upperYTM, lowerYTM)

			let numOrders = numOrdersByZone[i];

			if (numOrders.lt(_1)) {
				let zone = {
					lower,
					upper,
					orders: [],
					weightScalar: _0,
					totalZCBWeight: _0,
					totalYTWeight: _0
				}
				ret[i] = zone;
				continue;
			}

			let orders = new Array(numOrders);
			let weightScalar = zoneWeightScalars[i];

			let MCRmultiplier = ApproxNthRoot(YTMboundsMultiplier, numOrders);
			let SQRTMCRmultiplier = ApproxNthRoot(MCRmultiplier, _2);

			let totalZCBWeight = _0;
			let totalYTWeight = _0;

			let firstMultiplier = numOrders
			for (let j = 0, orderYTM = Mul(lower, SQRTMCRmultiplier); j < numOrders; j++, orderYTM = Mul(orderYTM, MCRmultiplier)) {
				let MCR = Mul(orderYTM, startRatio);
				let adjYTM = Div(MCR, balanceRatio);

				/*
					ZCB NPV = 1/YTM
					YT NPV = 1 - (1/YTM) = (YTM - 1) / YTM

					ZCB weight =  1 / ZCBnpv = YTM
					YT weight = 1 / YTnpv = YTM / (YTM - 1)
				*/

				let ZCBweight = adjYTM;
				let YTweight = Div(adjYTM, adjYTM.sub(_10To18));
				let order = {
					MCR,
					ZCBweight,
					YTweight
				}
				orders[j] = order;
				totalZCBWeight = totalZCBWeight.add(ZCBweight);
				totalYTWeight = totalYTWeight.add(YTweight);
			}

			let zone = {
				lower,
				upper,
				orders,
				weightScalar,
				totalZCBWeight,
				totalYTWeight
			}
			ret[i] = zone;
		}

		return ret;
	})();

	for (let i = 0; i < zones.length; i++) {
		console.log("ZONE", i);
		console.log("liquidity range MCR", zones[i].lower.toString(), "to", zones[i].upper.toString());
		zones[i].lower = zones[i].lower.toString();
		zones[i].upper = zones[i].upper.toString();
		console.log("Zone weight scalar:", zones[i].weightScalar.toString());
		zones[i].weightScalar = zones[i].weightScalar.toString();
		console.log("Total zone ZCB weight:", zones[i].totalZCBWeight.toString());
		zones[i].totalZCBWeight = zones[i].totalZCBWeight.toString();
		console.log("Total zone YT weight:", zones[i].totalYTWeight.toString());
		zones[i].totalYTWeight = zones[i].totalYTWeight.toString();
		console.log(zones[i].orders.length, "orders in zone", i);
		for (let j = 0; j < zones[i].orders.length; j++) {
			console.log("\torder", j, "MCR: ", zones[i].orders[j].MCR.toString(), "ZCBweight:", zones[i].orders[j].ZCBweight.toString(), "YTweight:", zones[i].orders[j].YTweight.toString());
			zones[i].orders[j].MCR = zones[i].orders[j].MCR.toString();
			zones[i].orders[j].ZCBweight = zones[i].orders[j].ZCBweight.toString();
			zones[i].orders[j].YTweight = zones[i].orders[j].YTweight.toString();
		}
	}
	console.log("\n-------------------------JSON OUTPUT----------------------\n");
	let jsonOut = JSON.stringify([zones, OrderbookAddress, accounts[0]]);
	console.log(jsonOut);

	fs.writeFile(outFilename, jsonOut, 'utf8', callback);
}