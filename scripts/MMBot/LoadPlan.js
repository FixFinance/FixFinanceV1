const IOrderbookExchange = artifacts.require("IOrderbookExchange");
const IWrapper = artifacts.require("IWrapper");
const fs = require('fs');
const BN = web3.utils.BN;
let Mul, Div, Pow, ApproxNthRoot;
({Mul, Div, Pow, ApproxNthRoot} = require('../../helper/BBN.js').getFunctionality(BN));
const _0 = new BN(0);
const _1 = new BN(1);
const _2 = new BN(2);
const _10To18 = (new BN(10)).pow(new BN(18));
const NULL_ORDER_STATUS = '';
const ZCBSELL_ORDER_STATUS = 'ZCBSell';
const YTSELL_ORDER_STATUS = 'YTSell';

const ROOT_DIR_NAME = 'FixFinanceV1';
const dir = process.cwd();
let split = dir.split('/');
let indexRootDir = split.indexOf(ROOT_DIR_NAME);
while(split.length > indexRootDir+1) split.pop();
let ROOT_DIR_ABS_PATH = split.join('/');
const inFilename = ROOT_DIR_ABS_PATH + '/scripts/MMBot/GeneratedPlan.json';
const outFilename = ROOT_DIR_ABS_PATH + '/scripts/MMBot/LoadedPlan.json';

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

	let zones;
	let OrderbookAddress;
	let accounts = await web3.eth.getAccounts();
	try {
		let inData = fs.readFileSync(inFilename, 'utf8');
		let mainAccount;
		[zones, OrderbookAddress, mainAccount] = JSON.parse(inData);

		if (mainAccount !== accounts[0]) {
			throw new Error("Please Configure The truffle-config.js file to ensure the first account provided is "+mainAccount+" the current main account is "+accounts[0]);
		}

	//	if (await fileExists(outFilename) && fs.readFileSync(outFilename).length > 0) {
	//		throw new Error("Out File "+outFilename+" must be empty to execute the LoadPlan script");
	//	}
	}
	catch(err) {
		console.error(err);
		callback();
		process.exit();
	}

	for (let i = 0; i < zones.length; i++) {
		zones[i].lower = new BN(zones[i].lower);
		zones[i].upper = new BN(zones[i].upper);
		zones[i].weightScalar = new BN(zones[i].weightScalar);
		zones[i].totalZCBWeight = new BN(zones[i].totalZCBWeight);
		zones[i].totalYTWeight = new BN(zones[i].totalYTWeight);
		for (let j = 0; j < zones[i].orders.length; j++) {
			zones[i].orders[j].MCR = new BN(zones[i].orders[j].MCR);
			zones[i].orders[j].ZCBweight = new BN(zones[i].orders[j].ZCBweight);
			zones[i].orders[j].YTweight = new BN(zones[i].orders[j].YTweight);
			zones[i].orders[j].status = NULL_ORDER_STATUS;
			zones[i].orders[j].amount = _0;
			zones[i].orders[j].ID = '0';
		}
	}

	let exchange = await IOrderbookExchange.at(OrderbookAddress);
	let baseWrapper = await IWrapper.at(await exchange.wrapper());
	let currentRatio = await baseWrapper.WrappedAmtToUnitAmt_RoundDown(_10To18);

	let yieldBalance = await exchange.YieldDeposited(accounts[0]);
	let bondBalance = await exchange.BondDeposited(accounts[0]);
	let ytBalance = yieldBalance;
	let zcbBalance = yieldBalance.mul(currentRatio).div(_10To18).add(bondBalance);

	if (!_0.eq(await exchange.lockedZCB(accounts[0]))) {
		throw new Error("to load plan no ZCB may be locked");
	}
	if (!_0.eq(await exchange.lockedYT(accounts[0]))) {
		throw new Error("to load plan no YT may be locked");
	}


	let oracleMCR = await exchange.getImpliedMCRFromOracle();

	if (oracleMCR.eq(_0)) {
		throw new Error("Oracle must report back a rate to load a plan");
	}

	let zcbSellHeadID = await exchange.headZCBSellID();
	let zcbSellHeadMCR = (await exchange.ZCBSells(zcbSellHeadID)).maturityConversionRate;
	zcbSellHeadMCR = zcbSellHeadMCR.eq(_0) ? oracleMCR : zcbSellHeadMCR;
	let ytSellHeadID = await exchange.headZCBSellID();
	let ytSellHeadMCR = (await exchange.YTSells(ytSellHeadID)).maturityConversionRate;
	ytSellHeadMCR = ytSellHeadMCR.eq(_0) ? oracleMCR : ytSellHeadMCR;

	let ytBoundMCRLiquidityProvision = BN.max(ytSellHeadMCR, oracleMCR.add(_1));
	let zcbBoundMCRLiquidityProvision = BN.min(zcbSellHeadMCR, oracleMCR.sub(_1));

	console.log("YT lower bound MCR", ytBoundMCRLiquidityProvision.toString());
	console.log("ZCB higher bound MCR", zcbBoundMCRLiquidityProvision.toString());

	console.log("YieldDeposited",yieldBalance.toString(), "BondDeposited", bondBalance.toString());

	let highestActiveZone = -1; //ZCBSellZone
	let lowestActiveZone = -1; //YTSellZone

	let totalZCBSellweightedScalars = _0;
	let totalYTSellweightedScalars = _0;

	for (let i = zones.length-1; i >= 0; i--) {
		let lowestOrderMCR = zones[i].orders[0].MCR;
		if (ytBoundMCRLiquidityProvision.gte(lowestOrderMCR) && highestActiveZone == -1) {
			highestActiveZone = i;
		}
		if (highestActiveZone != -1) {
			totalZCBSellweightedScalars = totalZCBSellweightedScalars.add(zones[i].weightScalar);
		}
	}

	for (let i = 0; i < zones.length; i++) {
		let orders = zones[i].orders;
		let highestOrderMCR = orders[orders.length-1].MCR;
		if (ytBoundMCRLiquidityProvision.lte(highestOrderMCR) && lowestActiveZone == -1) {
			lowestActiveZone = i;
		}
		if (lowestActiveZone != -1) {
			totalYTSellweightedScalars = totalYTSellweightedScalars.add(zones[i].weightScalar);
		}
	}

	console.log("Total ZCB Weights", totalZCBSellweightedScalars.toString());
	console.log("Total YT Weights", totalYTSellweightedScalars.toString());

	let pctWeightSuppliedLowestActiveZone; // inflated by 10**18
	let pctWeightSuppliedHighestActiveZone; // inflated by 10**18
	let ZCBsellAmtPctIncrease;
	let YTsellAmtPctIncrease;

	let highestActiveZCBSellOrderIndex = -2; //index in highestZone.orders array
	let lowestActiveYTSellOrderIndex = -2; //index in lowestZone.orders array

	if (highestActiveZone > -1) {
		let totalWeight = zones[highestActiveZone].totalZCBWeight;
		let totalWeightActive = _0;
		for (let i = 0; i < zones[highestActiveZone].orders.length; i++) {
			if (zones[highestActiveZone].orders[i].MCR.lte(zcbBoundMCRLiquidityProvision)) {
				totalWeightActive = totalWeightActive.add(zones[highestActiveZone].orders[i].ZCBweight);
			}
			else if (highestActiveZCBSellOrderIndex == -2) {
				highestActiveZCBSellOrderIndex = i-1;
			}
		}
		pctWeightSuppliedHighestActiveZone = Div(totalWeightActive, totalWeight);
		let pctWeightUnsupplied = _10To18.sub(pctWeightSuppliedHighestActiveZone);
		//total weight / (total weight - weight unsupplied)
		//total weight * 10**18 / (total weight * 10**18 - weight unsupplied * 10**18)
		let numerator = totalZCBSellweightedScalars.mul(_10To18);
		let weightUnsupplied = zones[highestActiveZone].weightScalar.mul(pctWeightUnsupplied);
		let denominator = numerator.sub(weightUnsupplied)
		ZCBsellAmtPctIncrease = Div(numerator, denominator);
	}

	if (lowestActiveZone > -1) {
		let totalWeight = zones[lowestActiveZone].totalYTWeight;
		let totalWeightActive = _0;
		for (let i = 0; i < zones[lowestActiveZone].orders.length; i++) {
			if (zones[lowestActiveZone].orders[i].MCR.gte(ytBoundMCRLiquidityProvision)) {
				totalWeightActive = totalWeightActive.add(zones[lowestActiveZone].orders[i].YTweight);
				if (lowestActiveYTSellOrderIndex == -2) {
					lowestActiveYTSellOrderIndex = i;
				}
			}
		}
		pctWeightSuppliedLowestActiveZone = Div(totalWeightActive, totalWeight);
		let pctWeightUnsupplied = _10To18.sub(pctWeightSuppliedLowestActiveZone);
		//total weight / (total weight - weight unsupplied)
		//total weight * 10**18 / (total weight * 10**18 - weight unsupplied * 10**18)
		let numerator = totalYTSellweightedScalars.mul(_10To18);
		let weightUnsupplied = zones[lowestActiveZone].weightScalar.mul(pctWeightUnsupplied);
		let denominator = numerator.sub(weightUnsupplied)
		YTsellAmtPctIncrease = Div(numerator, denominator);
	}

	let zcbInc = parseInt(ZCBsellAmtPctIncrease.toString()) * Math.pow(10, -18);
	let ytInc = parseInt(YTsellAmtPctIncrease.toString()) * Math.pow(10, -18);
	console.log("ZCB Sell Liquidity Supplied up to Zone", highestActiveZone, "with super bip pct supplied at", pctWeightSuppliedHighestActiveZone.toString(), "PCT INC ELSEWHERE", zcbInc);
	console.log("YT Sell Liquidity Supplied up to Zone", lowestActiveZone, "with super bip pct supplied at", pctWeightSuppliedLowestActiveZone.toString(), "PCR INC ELSEWHERE", ytInc);

	console.log("\n\nZCB Sells");
	for(let i = 0; i <= highestActiveZone; i++) {
		console.log("ZONE",i);
		let orders = zones[i].orders;
		let numOrders = i == highestActiveZone ? highestActiveZCBSellOrderIndex+1 : orders.length;
		let weightScalar = zones[i].weightScalar;
		let zoneZCBAllocation = zcbBalance.mul(weightScalar).div(totalZCBSellweightedScalars);
		let totalZCBWeight = zones[i].totalZCBWeight;
		for (let j = 0; j < numOrders; j++) {
			let unAdjustedAmount = zoneZCBAllocation.mul(orders[j].ZCBweight).div(totalZCBWeight);
			let amount = unAdjustedAmount.mul(ZCBsellAmtPctIncrease).div(_10To18);
			orders[j].amount = amount;
			orders[j].status = ZCBSELL_ORDER_STATUS;

			let zcbLocked = await exchange.lockedZCB(accounts[0]);

			let currZCBbal = zcbBalance.sub(zcbLocked);

			let rec = await exchange.limitSellZCB(amount, orders[j].MCR, "0", 100);
			orders[j].ID = rec.receipt.logs[0].args.newID.toString();
			console.log("ZONE[",i,"] Order[",j,"] ID:", orders[j].ID," MCR:",orders[j].MCR.toString()," Amount:",amount.toString());
		}
	}

	console.log("\n\nYT Sells");
	for(let i = zones.length-1; i >= lowestActiveZone; i--) {
		console.log("ZONE",i);
		let orders = zones[i].orders;
		let minIndex = i == lowestActiveZone ? lowestActiveYTSellOrderIndex : 0;
		let weightScalar = zones[i].weightScalar;
		let zoneYTAllocation = ytBalance.mul(weightScalar).div(totalYTSellweightedScalars);
		let totalYTWeight = zones[i].totalYTWeight;
		for (let j = orders.length-1; j >= minIndex; j--) {
			let unAdjustedAmount = zoneYTAllocation.mul(orders[j].YTweight).div(totalYTWeight);
			let amount = unAdjustedAmount.mul(YTsellAmtPctIncrease).div(_10To18);
			orders[j].amount = amount;
			orders[j].status = YTSELL_ORDER_STATUS;

			let ytLocked = await exchange.lockedYT(accounts[0]);

			let currYTbal = ytBalance.sub(ytLocked);

			let rec = await exchange.limitSellYT(amount, orders[j].MCR, "0", 100);
			orders[j].ID = rec.receipt.logs[0].args.newID.toString();
			console.log("ZONE[",i,"] Order[",j,"] ID:", orders[j].ID," MCR:",orders[j].MCR.toString()," Amount:",amount.toString());
		}
	}


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
			console.log("\torder index:", j, "order ID:", zones[i].orders[j].ID,"MCR: ", zones[i].orders[j].MCR.toString(), "ZCBweight:", zones[i].orders[j].ZCBweight.toString(), "YTweight:", zones[i].orders[j].YTweight.toString());
			zones[i].orders[j].MCR = zones[i].orders[j].MCR.toString();
			zones[i].orders[j].ZCBweight = zones[i].orders[j].ZCBweight.toString();
			zones[i].orders[j].YTweight = zones[i].orders[j].YTweight.toString();
			zones[i].orders[j].amount = zones[i].orders[j].amount.toString();
			zones[i].orders[j].targetAmount = zones[i].orders[j].amount;
			zones[i].orders[j].targetStatus = zones[i].orders[j].status;
		}
	}
	console.log("\n-------------------------JSON OUTPUT----------------------\n");

	let jsonOut = JSON.stringify([zones, OrderbookAddress, accounts[0]]);
	console.log(jsonOut);
	fs.writeFile(outFilename, jsonOut, 'utf8', callback);


	}
	catch (err) {
		console.error(err);
		callback();
	}

}