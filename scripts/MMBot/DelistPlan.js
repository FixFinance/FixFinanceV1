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

const ROOT_DIR_NAME = 'FixFinanceV1';
const dir = process.cwd();
let split = dir.split('/');
let indexRootDir = split.indexOf(ROOT_DIR_NAME);
while(split.length > indexRootDir+1) split.pop();
let ROOT_DIR_ABS_PATH = split.join('/');
const inFilename = ROOT_DIR_ABS_PATH + '/scripts/MMBot/JSON/LoadedPlan.json';

module.exports = async function(callback) {
	try {

	let zones;
	let OrderbookAddress;
	let accounts = await web3.eth.getAccounts();
	try {
		let output = fs.readFileSync(inFilename, 'utf8');
		let mainAccount;
		[zones, OrderbookAddress, mainAccount] = JSON.parse(output);

		if (mainAccount !== accounts[0]) {
			throw new Error("Please Configure The truffle-config.js file to ensure the first account provided is "+mainAccount+" the current main account is "+accounts[0]);
		}
	}
	catch(err) {
		console.error(err);
		callback();
		process.exit();
	}

	let exchange = await IOrderbookExchange.at(OrderbookAddress);
	let baseWrapper = await IWrapper.at(await exchange.wrapper());
	let currentRatio = await baseWrapper.WrappedAmtToUnitAmt_RoundDown(_10To18);


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
			zones[i].orders[j].amount = new BN(zones[i].orders[j].amount);
			let status = zones[i].orders[j].status;
			if (status == 'ZCBSell') {
				let ID = zones[i].orders[j].ID;
				let order = await exchange.ZCBSells(ID)
				if (order.amount.gt(_0)) {
					let changeAmt = order.amount.neg();
					let hintID = "0";
					let maxSteps = 10;
					let removeBelowMin = true;
					console.log("removing ZCB Sell, ID:", ID);
					await exchange.modifyZCBLimitSell(changeAmt, ID, hintID, maxSteps, removeBelowMin);
				}
			}
			else if (status == 'YTSell') {
				let ID = zones[i].orders[j].ID;
				let order = await exchange.YTSells(ID);
				if (order.amount.gt(_0)) {
					let changeAmt = order.amount.neg();
					let hintID = "0";
					let maxSteps = 10;
					let removeBelowMin = true;
					console.log("removing YT Sell, ID:", ID);
					await exchange.modifyYTLimitSell(changeAmt, ID, hintID, maxSteps, removeBelowMin);
				}
			}
		}
	}

	//plan has been deleted, now remove LoadedPlan.json
	console.log("deleting file "+inFilename+" ...");
	fs.unlinkSync(inFilename);
	console.log(inFilename+" has been deleted");

	}
	catch (err) {
		console.error(err);
	}

	callback();
}
