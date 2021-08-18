const dummyAToken = artifacts.require('dummyAToken');
const VaultHealth = artifacts.require('VaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const fixCapitalPool = artifacts.require('FixCapitalPool');
const YieldToken = artifacts.require("YieldToken");
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapperDeployer = artifacts.require('NGBwrapperDeployer');
const organizer = artifacts.require('Organizer');
const NSFVaultFactoryDelegate1 = artifacts.require('NSFVaultFactoryDelegate1');
const NSFVaultFactoryDelegate2 = artifacts.require('NSFVaultFactoryDelegate2');
const NSFVaultFactoryDelegate3 = artifacts.require('NSFVaultFactoryDelegate3');
const NSFVaultFactoryDelegate4 = artifacts.require('NSFVaultFactoryDelegate4');
const NSFVaultFactoryDelegate5 = artifacts.require('NSFVaultFactoryDelegate5');
const NSFVaultFactory = artifacts.require('NSFVaultFactory');
const OrderbookDelegate1 = artifacts.require("OrderbookDelegate1");
const OrderbookDelegate2 = artifacts.require("OrderbookDelegate2");
const OrderbookDelegate3 = artifacts.require("OrderbookDelegate3");
const OrderbookDeployer = artifacts.require("OrderbookDeployer");
const OrderbookExchange = artifacts.require("OrderbookExchange");
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const InfoOracle = artifacts.require("InfoOracle");
const OracleContainer = artifacts.require("OracleContainer");
const dummyAggregator = artifacts.require("dummyAggregator");
const ZCBamm = artifacts.require("ZCBamm");

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const DECIMALS = 18;
const _10 = new BN(10);
const _10To18 = _10.pow(new BN('18'));
const _10To19 = _10To18.mul(_10);

const symbol0 = "aETH";
const symbol1 = "aUSDT";
const phrase = symbol0.substring(1)+" / "+symbol1.substring(1);
const _8days = 8*24*60*60;
const _80days = 10*_8days;

const LENGTH_RATE_SERIES = 31;

const TotalBasisPoints = 10000;

const SecondsPerYear = 31556926;

const minUpperRateAdjustment = 0.01;
const minLowerRateAdjustment = 0.005;

const ErrorRange = 2 * Math.pow(10,-6);

function basisPointsToABDKString(bips) {
	return (new BN(bips)).mul((new BN(2)).pow(new BN(64))).div(_10.pow(new BN(4))).toString();
}

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

const ABDK_1 = basisPointsToABDKString(TotalBasisPoints);

async function setOracleMCR(orderbook, MCR) {
	let headZCBID = await orderbook.headZCBSellID();
	let headYTID = await orderbook.headYTSellID();
	const modifyDownAmt = _10To18.neg();
	const maxSteps = 10;
	while (headZCBID.toString() !== "0") {
		await orderbook.modifyZCBLimitSell(modifyDownAmt, headZCBID, "0", maxSteps, true);
		headZCBID = await orderbook.headZCBSellID();
	}
	while (headYTID.toString() !== "0") {
		await orderbook.modifyYTLimitSell(modifyDownAmt, headYTID, "0", maxSteps, true);
		headYTID = await orderbook.headYTSellID();
	}
	const postLimitAmt = _10To18.div(new BN(10000));
	await orderbook.limitSellZCB(postLimitAmt, MCR, "0", maxSteps);
	await orderbook.limitSellYT(postLimitAmt, MCR, "0", maxSteps);
	for (let i = 0; i < LENGTH_RATE_SERIES; i++) {
		await orderbook.forceRateDataUpdate();
		//advance 1 minuites
		helper.advanceTime(61);
	}
	let actualMCR = (await orderbook.getOracleData())._impliedMCRs[3];
	await orderbook.setOracleMCR(actualMCR);
	return actualMCR;
}

contract('VaultHealth', async function(accounts) {
	it('before each', async () => {
		//borrow asset 0
		asset0 = await dummyAToken.new(symbol0);
		//supply asset 1
		asset1 = await dummyAToken.new(symbol1);
		aggregator0 = await dummyAggregator.new(DECIMALS, symbol0.substring(1)+" / ETH");
		aggregator1 = await dummyAggregator.new(DECIMALS, symbol1.substring(1)+" / ETH");
		await aggregator0.addRound(_10To18);
		price = 0;
		OracleContainerInstance = await OracleContainer.new(nullAddress.substring(0, nullAddress.length-1)+"1");
		zcbYtDeployerInstance = await zcbYtDeployer.new();
		vaultHealthInstance = await VaultHealth.new(OracleContainerInstance.address);
		nsfVaultFactoryDelegate1Instance = await NSFVaultFactoryDelegate1.new();
		nsfVaultFactoryDelegate2Instance = await NSFVaultFactoryDelegate2.new();
		nsfVaultFactoryDelegate3Instance = await NSFVaultFactoryDelegate3.new();
		nsfVaultFactoryDelegate4Instance = await NSFVaultFactoryDelegate4.new();
		nsfVaultFactoryDelegate5Instance = await NSFVaultFactoryDelegate5.new();
		vaultFactoryInstance = await NSFVaultFactory.new(
			vaultHealthInstance.address,
			nullAddress,
			nsfVaultFactoryDelegate1Instance.address,
			nsfVaultFactoryDelegate2Instance.address,
			nsfVaultFactoryDelegate3Instance.address,
			nsfVaultFactoryDelegate4Instance.address,
			nsfVaultFactoryDelegate5Instance.address
		);
		EiInstance = await Ei.new();
		await BigMath.link("Ei", EiInstance.address);
		BigMathInstance = await BigMath.new();
		await ZCBammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDeployer.link("BigMath", BigMathInstance.address);
		ZCBammDeployerInstance = await ZCBammDeployer.new();
		YTammDelegateInstance = await YTammDelegate.new();
		YTammDeployerInstance = await YTammDeployer.new(YTammDelegateInstance.address);
		fcpDelegate1Instance = await FCPDelegate1.new();
		FixCapitalPoolDeployerInstance = await FixCapitalPoolDeployer.new(fcpDelegate1Instance.address);
		infoOracleInstance = await InfoOracle.new("0", nullAddress);
		ngbwDelegate1Instance = await NGBwrapperDelegate1.new();
		ngbwDelegate2Instance = await NGBwrapperDelegate2.new();
		ngbwDelegate3Instance = await NGBwrapperDelegate3.new();
		NGBwrapperDeployerInstance = await NGBwrapperDeployer.new(
			infoOracleInstance.address,
			ngbwDelegate1Instance.address,
			ngbwDelegate2Instance.address,
			ngbwDelegate3Instance.address
		);
		orderbookDelegate1Instance = await OrderbookDelegate1.new();
		orderbookDelegate2Instance = await OrderbookDelegate2.new();
		orderbookDelegate3Instance = await OrderbookDelegate3.new();
		orderbookDeployerInstance = await OrderbookDeployer.new(
			nullAddress,
			infoOracleInstance.address,
			orderbookDelegate1Instance.address,
			orderbookDelegate2Instance.address,
			orderbookDelegate3Instance.address
		);
		organizerInstance = await organizer.new(
			NGBwrapperDeployerInstance.address,
			zcbYtDeployerInstance.address,
			FixCapitalPoolDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			orderbookDeployerInstance.address,
			nullAddress,
			infoOracleInstance.address
		);
		await vaultHealthInstance.setOrganizerAddress(organizerInstance.address);

		maturity = ((await web3.eth.getBlock('latest')).timestamp + _80days).toString();
		shortMaturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

		let reca = await organizerInstance.deployNGBWrapper(asset0.address);
		let recb = await organizerInstance.deployNGBWrapper(asset1.address);

		wAsset0 = await NGBwrapper.at(reca.receipt.logs[0].args.wrapperAddress);
		wAsset1 = await NGBwrapper.at(recb.receipt.logs[0].args.wrapperAddress);

		let upperStr = basisPointsToABDKString(100);
		let lowerStr = basisPointsToABDKString(50);
		await vaultHealthInstance.setMinimumRateAdjustments(wAsset0.address, upperStr, lowerStr);
		await vaultHealthInstance.setMinimumRateAdjustments(wAsset1.address, upperStr, lowerStr);

		let rec0 = await organizerInstance.deployFixCapitalPoolInstance(wAsset0.address, maturity);
		let rec1 = await organizerInstance.deployFixCapitalPoolInstance(wAsset1.address, maturity);
		let rec2 = await organizerInstance.deployFixCapitalPoolInstance(wAsset1.address, shortMaturity);

		await OracleContainerInstance.addAggregators([aggregator0.address, aggregator1.address]);
		await OracleContainerInstance.AddAToken(wAsset0.address, symbol0.substring(1));
		await OracleContainerInstance.AddAToken(wAsset1.address, symbol1.substring(1));

		await asset0.approve(wAsset0.address, _10To18.toString());
		await asset1.approve(wAsset1.address, _10To18.toString());

		await wAsset0.depositUnitAmount(accounts[0], _10To18.toString());
		await wAsset1.depositUnitAmount(accounts[0], _10To18.toString());

		fcp0 = await fixCapitalPool.at(rec0.receipt.logs[0].args.addr);
		fcp1 = await fixCapitalPool.at(rec1.receipt.logs[0].args.addr);
		fcp2 = await fixCapitalPool.at(rec2.receipt.logs[0].args.addr);

		zcbAsset0 = await IERC20.at(await fcp0.zeroCouponBondAddress());
		zcbAsset1 = await IERC20.at(await fcp1.zeroCouponBondAddress());
		zcbAsset2 = await IERC20.at(await fcp2.zeroCouponBondAddress());

		ytAsset0 = await YieldToken.at(await fcp0.yieldTokenAddress());
		ytAsset1 = await YieldToken.at(await fcp1.yieldTokenAddress());
		ytAsset2 = await YieldToken.at(await fcp2.yieldTokenAddress());

		await organizerInstance.deployOrderbook(fcp0.address);
		await organizerInstance.deployOrderbook(fcp1.address);
		await organizerInstance.deployOrderbook(fcp2.address);

		orderbook0 = await OrderbookExchange.at(await organizerInstance.Orderbooks(fcp0.address));
		orderbook1 = await OrderbookExchange.at(await organizerInstance.Orderbooks(fcp1.address));
		orderbook2 = await OrderbookExchange.at(await organizerInstance.Orderbooks(fcp2.address));

		//mint asset0 assets to account 0
		await asset0.mintTo(accounts[0], _10To19.mul(_10));
		await asset0.approve(wAsset0.address, _10To19.mul(_10));
		await wAsset0.depositUnitAmount(accounts[0], _10To19.mul(_10));
		await wAsset0.approve(fcp0.address, _10To19);
		await fcp0.depositWrappedToken(accounts[0], _10To19);
		await wAsset0.approve(vaultFactoryInstance.address, _10To19);
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To19);
		await zcbAsset0.approve(orderbook0.address, _10To19);
		await ytAsset0.approve(orderbook0.address, _10To19);

		//mint asset1 assets to account 0
		await asset1.mintTo(accounts[0], _10To19.mul(_10));
		await asset1.approve(wAsset1.address, _10To19.mul(_10));
		await wAsset1.depositUnitAmount(accounts[0], _10To19.mul(_10));
		await wAsset1.approve(fcp1.address, _10To19);
		await fcp1.depositWrappedToken(accounts[0], _10To19);
		await wAsset1.approve(vaultFactoryInstance.address, _10To19);
		await zcbAsset1.approve(vaultFactoryInstance.address, _10To19);
		await zcbAsset1.approve(orderbook1.address, _10To19);
		await ytAsset1.approve(orderbook1.address, _10To19);

		await wAsset1.approve(fcp2.address, _10To19);
		await fcp2.depositWrappedToken(accounts[0], _10To19);
		await wAsset1.approve(vaultFactoryInstance.address, _10To19);
		await zcbAsset2.approve(vaultFactoryInstance.address, _10To19);
		await zcbAsset2.approve(orderbook2.address, _10To19);
		await ytAsset2.approve(orderbook2.address, _10To19);

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To19.mul(_10));
		await asset0.approve(wAsset0.address, _10To19.mul(_10), {from: accounts[1]});
		await wAsset0.depositUnitAmount(accounts[1], _10To19.mul(_10), {from: accounts[1]});
		await wAsset0.approve(fcp0.address, _10To19, {from: accounts[1]});
		await fcp0.depositWrappedToken(accounts[1], _10To19, {from: accounts[1]});
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To19, {from: accounts[1]});
		await wAsset0.approve(vaultFactoryInstance.address, _10To19, {from: accounts[1]});

		//add liquidity to amms
		let toSendYield = _10To18.div(_10).div(_10);
		let toSendBond = toSendYield.div(_10);
		await orderbook0.deposit(toSendYield, toSendBond);
		await orderbook1.deposit(toSendYield, toSendBond);
		await orderbook2.deposit(toSendYield, toSendBond);

		MCR0 = _10To18.mul(new BN(21)).div(_10);
		MCR1 = _10To18.mul(new BN(22)).div(_10);
		MCR2 = _10To18.mul(new BN(11)).div(_10);

		let limitAmt = _10To18.div(new BN(1000));
		await orderbook0.limitSellZCB(limitAmt, MCR0, 0, 10);
		await orderbook0.limitSellYT(limitAmt, MCR0, 0, 10);
		await orderbook1.limitSellZCB(limitAmt, MCR1, 0, 10);
		await orderbook1.limitSellYT(limitAmt, MCR1, 0, 10);
		await orderbook2.limitSellZCB(limitAmt, MCR2, 0, 10);
		await orderbook2.limitSellYT(limitAmt, MCR2, 0, 10);

		for (let i = 0; i < LENGTH_RATE_SERIES; i++) {
			await orderbook0.forceRateDataUpdate();
			await orderbook1.forceRateDataUpdate();
			await orderbook2.forceRateDataUpdate();
			//advance 1 minuites
			helper.advanceTime(61);
		}
		let data0 = await orderbook0.getOracleData();
		let data1 = await orderbook1.getOracleData();
		let data2 = await orderbook2.getOracleData();
		MCR0 = data0._impliedMCRs[3];
		MCR1 = data1._impliedMCRs[3];
		MCR2 = data2._impliedMCRs[3];
		await orderbook0.setOracleMCR(MCR0);
		await orderbook1.setOracleMCR(MCR1);
		await orderbook2.setOracleMCR(MCR2);
	});

	//price inflated by _10Ti18
	//price is of asset0/asset1
	//asset0 is the deposited asset and asset1 is the borrowed asset
	async function setPrice(_price) {
		price = parseInt(_price.toString()) * 10**-18;
		await aggregator1.addRound(_price);
	}


	it('set rate collateralization ratios', async () => {
		//asset0 ratios
		upperRatio0 = 1.07;
		lowerRatio0 = 1.05;
		UpperRatio0Str = basisPointsToABDKString(10700);	//107%
		LowerRatio0Str = basisPointsToABDKString(10500);	//105%
		await vaultHealthInstance.setCollateralizationRatios(wAsset0.address, UpperRatio0Str, LowerRatio0Str);
		let _upper = await vaultHealthInstance.UpperCollateralizationRatio(wAsset0.address);
		let _lower = await vaultHealthInstance.LowerCollateralizationRatio(wAsset0.address);
		assert.equal(_upper.toString(), UpperRatio0Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerRatio0Str, "correct lower rate threshold");

		//asset1 ratios
		upperRatio1 = 1.12;
		lowerRatio1 = 1.09;
		UpperRatio1Str = basisPointsToABDKString(11200);	//112%
		LowerRatio1Str = basisPointsToABDKString(10900);	//109%
		await vaultHealthInstance.setCollateralizationRatios(wAsset1.address, UpperRatio1Str, LowerRatio1Str);
		_upper = await vaultHealthInstance.UpperCollateralizationRatio(wAsset1.address);
		_lower = await vaultHealthInstance.LowerCollateralizationRatio(wAsset1.address);
		assert.equal(_upper.toString(), UpperRatio1Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerRatio1Str, "correct lower rate threshold");
	});

	it('set rate thresholds', async () => {
		//asset0 thresholds
		upperThreshold0 = 1.5;
		lowerThreshold0 = 1.3;
		UpperThreshold0Str = basisPointsToABDKString(15000);	//150%
		LowerThreshold0Str = basisPointsToABDKString(13000);	//130%
		await vaultHealthInstance.setRateThresholds(wAsset0.address, UpperThreshold0Str, LowerThreshold0Str);
		let _upper = await vaultHealthInstance.UpperRateThreshold(wAsset0.address);
		let _lower = await vaultHealthInstance.LowerRateThreshold(wAsset0.address);
		assert.equal(_upper.toString(), UpperThreshold0Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerThreshold0Str, "correct lower rate threshold");

		//asset1 thresholds
		upperThreshold1 = 2.0;
		lowerThreshold1 = 1.5;
		UpperThreshold1Str = basisPointsToABDKString(20000);	//200%
		LowerThreshold1Str = basisPointsToABDKString(15000);	//150%
		await vaultHealthInstance.setRateThresholds(wAsset1.address, UpperThreshold1Str, LowerThreshold1Str);
		_upper = await vaultHealthInstance.UpperRateThreshold(wAsset1.address);
		_lower = await vaultHealthInstance.LowerRateThreshold(wAsset1.address);
		assert.equal(_upper.toString(), UpperThreshold1Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerThreshold1Str, "correct lower rate threshold");
	});

	it('amountSuppliedAtUpperLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		/*
			asset0 is borrowed
			asset1 is supplied
		*/
		apy0BN = await orderbook0.getAPYFromOracle();
		apy1BN = await orderbook1.getAPYFromOracle();
		apy2BN = await orderbook2.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);
		APY2 = (parseInt(apy2BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;
		let adjAPY1 = (APY1-1)*upperThreshold1 + 1;

		let temp0 = APY0-minUpperRateAdjustment;
		let temp1 = APY1+minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsRemaining2 = (shortMaturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountBorrowed = 100000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(zcbAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());
		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtUpperLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountBorrowed = 100000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(wAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(wAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(wAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtLowerLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await orderbook0.getAPYFromOracle();
		apy1BN = await orderbook1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;
		let adjAPY1 = (APY1-1)*lowerThreshold1 + 1;

		let temp0 = APY0-minLowerRateAdjustment;
		let temp1 = APY1+minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountBorrowed = 100000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtLowerLimit(zcbAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesLowerLimit");
	});

	it('amountSuppliedAtLowerLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountBorrowed = 100000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtLowerLimit(wAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(wAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(wAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesLowerLimit");
	});

	it('amountBorrowedAtUpperLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await orderbook0.getAPYFromOracle();
		apy1BN = await orderbook1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;
		let adjAPY1 = (APY1-1)*upperThreshold1 + 1;

		let temp0 = APY0-minUpperRateAdjustment;
		let temp1 = APY1+minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;	//asset1
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(amountSupplied * rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);

		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesUpperLimit");
	});

	it('amountBorrowedAtUpperLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 100000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(amountSupplied * rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtUpperLimit(wAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(wAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(wAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesUpperLimit");
	});

	it('amountBorrowedAtLowerLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await orderbook0.getAPYFromOracle();
		apy1BN = await orderbook1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;
		let adjAPY1 = (APY1-1)*lowerThreshold1 + 1;

		let temp0 = APY0-minLowerRateAdjustment;
		let temp1 = APY1+minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;	//asset1
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountBorrowed = Math.floor(amountSupplied * rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtLowerLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);

		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesLowerLimit");
	});

	it('amountBorrowedAtLowerLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 100000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountBorrowed = Math.floor(amountSupplied * rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtLowerLimit(wAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(wAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(wAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesLowerLimit");
	});

	it('amountSuppliedAtUpperLimit: borrow zcb with same wrapped asset as collateral asset', async () => {
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);

		let amountBorrowed = 100000000;	//asset0
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(wAsset0.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(wAsset0.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(wAsset0.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtUpperLimit: zcb time spread, borrow later maturity', async () => {
		apy1BN = await orderbook1.getAPYFromOracle();
		apy2BN = await orderbook2.getAPYFromOracle();
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);
		APY2 = (parseInt(apy2BN.toString()) * 2**-64);

		let yearsRemaining1 = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsRemaining2 = (shortMaturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsSpread = yearsRemaining1 - yearsRemaining2;

		let ytm1 = Math.pow(APY1, yearsRemaining1);
		let ytm2 = Math.pow(APY2, yearsRemaining2);

		let yr1 = (new BN(Math.floor(yearsRemaining1 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));
		let yr2 = (new BN(Math.floor(yearsRemaining2 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));

		let yieldSpread = ytm1 / ytm2;

		let APYs = Math.pow(yieldSpread, 1/yearsSpread);

		let adjAPYs = (APYs-1)/upperThreshold1 + 1;

		let temp = APYs-minUpperRateAdjustment;

		adjAPYs = Math.min(adjAPYs, temp);

		adjAPYs = Math.max(adjAPYs, 1);

		let rateMultiplier = adjAPYs**(-yearsSpread);

		let amountBorrowed = 100000000;	//zcb asset 1
		let expectedAmountSupplied = Math.floor(amountBorrowed/rateMultiplier);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(zcbAsset2.address, zcbAsset1.address, amountBorrowed);
		let actual = parseInt(actualBN.toString());
		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset2.address, zcbAsset1.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset2.address, zcbAsset1.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtUpperLimit: zcb time spread, borrow earlier maturity', async () => {
		apy1BN = await orderbook1.getAPYFromOracle();
		apy2BN = await orderbook2.getAPYFromOracle();
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);
		APY2 = (parseInt(apy2BN.toString()) * 2**-64);

		let yearsRemaining1 = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsRemaining2 = (shortMaturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsSpread = yearsRemaining1 - yearsRemaining2;

		let ytm1 = Math.pow(APY1, yearsRemaining1);
		let ytm2 = Math.pow(APY2, yearsRemaining2);

		let yr1 = (new BN(Math.floor(yearsRemaining1 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));
		let yr2 = (new BN(Math.floor(yearsRemaining2 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));

		let yieldSpread = ytm1 / ytm2;

		let APYs = Math.pow(yieldSpread, 1/yearsSpread);

		let adjAPYs = (APYs-1)*upperThreshold1 + 1;

		let temp = APYs+minUpperRateAdjustment;

		adjAPYs = Math.max(adjAPYs, temp);

		adjAPYs = Math.max(adjAPYs, 1);

		let rateMultiplier = adjAPYs**(-yearsSpread);

		let amountBorrowed = 100000000;	//zcb asset 2
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(zcbAsset1.address, zcbAsset2.address, amountBorrowed);
		let actual = parseInt(actualBN.toString());
		let error = AmountError(expectedAmountSupplied, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset2.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset2.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): FCP borrowed == FCP supplied', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);

		let amountSupplied = 100000000;
		let amountBond = -100000000;

		//when fcp borrowed == fcp supplied we consider as if both amountBond and amountBorrowed are being borrowed against amountSupplied
		//deposits of the base wrapper asset

		let totalToBorrow = Math.floor(amountSupplied / rateMultiplier0);
		let expectedAmountBorrowed = totalToBorrow + amountBond;
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp0.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied-amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp0.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp0.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): time spread, borrow later maturity', async () => {
		apy1BN = await orderbook1.getAPYFromOracle();
		apy2BN = await orderbook2.getAPYFromOracle();
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);
		APY2 = (parseInt(apy2BN.toString()) * 2**-64);

		let yearsRemaining1 = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsRemaining2 = (shortMaturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsSpread = yearsRemaining1 - yearsRemaining2;

		let ytm1 = Math.pow(APY1, yearsRemaining1);
		let ytm2 = Math.pow(APY2, yearsRemaining2);

		let yr1 = (new BN(Math.floor(yearsRemaining1 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));
		let yr2 = (new BN(Math.floor(yearsRemaining2 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));

		let yieldSpread = ytm1 / ytm2;

		let APYs = Math.pow(yieldSpread, 1/yearsSpread);

		let adjAPYs = (APYs-1)/upperThreshold1 + 1;
		let adjAPY1 = (APY1-1)/upperThreshold1 + 1;

		let temp = APYs-minUpperRateAdjustment;
		let temp1 = APY1-minUpperRateAdjustment;

		adjAPYs = Math.min(adjAPYs, temp);
		adjAPY1 = Math.min(adjAPY1, temp1);

		adjAPYs = Math.max(adjAPYs, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let rateMultiplierSpread = adjAPYs**(-yearsSpread);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining1);

		let amountSupplied = 20000000;
		let amountBond = 100000000;

		let borrowAgainstYield = Math.floor(amountSupplied/rateMultiplier1);
		let borrowAgainstSpread = Math.floor(amountBond/rateMultiplierSpread);
		let expectedAmountBorrowed = borrowAgainstYield + borrowAgainstSpread;
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp2.address, fcp1.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());
		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/expectedAmountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp2.address, fcp1.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp2.address, fcp1.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): time spread, borrow earlier maturity', async () => {
		apy1BN = await orderbook1.getAPYFromOracle();
		apy2BN = await orderbook2.getAPYFromOracle();
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);
		APY2 = (parseInt(apy2BN.toString()) * 2**-64);

		let yearsRemaining1 = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsRemaining2 = (shortMaturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;
		let yearsSpread = yearsRemaining1 - yearsRemaining2;

		let ytm1 = Math.pow(APY1, yearsRemaining1);
		let ytm2 = Math.pow(APY2, yearsRemaining2);

		let yr1 = (new BN(Math.floor(yearsRemaining1 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));
		let yr2 = (new BN(Math.floor(yearsRemaining2 * SecondsPerYear))).mul((new BN(2)).pow(new BN(64))).div(new BN(SecondsPerYear));

		let yieldSpread = ytm1 / ytm2;

		let APYs = Math.pow(yieldSpread, 1/yearsSpread);

		let adjAPYs = (APYs-1)*upperThreshold1 + 1;
		let adjAPY2 = (APY2-1)/upperThreshold1 + 1;

		let temp = APYs+minUpperRateAdjustment;
		let temp2 = APY2-minUpperRateAdjustment;

		adjAPYs = Math.max(adjAPYs, temp);
		adjAPY2 = Math.min(adjAPY2, temp2);

		adjAPYs = Math.max(adjAPYs, 1);
		adjAPY2 = Math.max(adjAPY2, 1);

		let rateMultiplierSpread = adjAPYs**(-yearsSpread);
		let rateMultiplier2 = adjAPY2**(-yearsRemaining2);

		let amountSupplied = 20000000;
		let amountBond = 100000000;

		let borrowAgainstYield = Math.floor(amountSupplied/rateMultiplier2);
		let borrowAgainstSpread = Math.floor(amountBond/rateMultiplierSpread);
		let expectedAmountBorrowed = borrowAgainstYield + borrowAgainstSpread;
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp1.address, fcp2.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());
		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/expectedAmountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp2.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp2.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");

	});

	it('amountSuppliedAtUpperLimit: matured zcb (not in payout phase) deposited', async () => {
		await helper.advanceTime(_8days+1);
		await asset1.setInflation(_10To18.mul(new BN(2)));
		MCR2 = _10To18.mul(new BN(21)).div(_10)
		MCR2 = await setOracleMCR(orderbook2, MCR2);
		await wAsset1.forceHarvest();
		await setPrice(_10To18.mul(new BN(3)));
		/*
			asset0 is borrowed
			asset1 is supplied
		*/
		apy0BN = await orderbook0.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		apy1BN = await orderbook1.getAPYFromOracle();
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountBorrowed = 100000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(zcbAsset2.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset2.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset2.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): ZCB > YT, (FCP supplied matured, not in payout phase)', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 100000000;
		let amountBond = 20000000;
		let collateralizationRatio = upperRatio0*upperRatio1;
		let compositeSupplied = amountSupplied + amountBond*rateMultiplier1;
		let expectedAmountBorrowed = Math.floor(compositeSupplied/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp2.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied+amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp2.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp2.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtUpperLimit: matured zcb (in payout phase) deposited', async () => {
		await fcp2.enterPayoutPhase();
		await asset1.setInflation(_10To18.mul(new BN(4)));
		MCR1 = _10To18.mul(new BN(45)).div(_10);
		MCR1 = await setOracleMCR(orderbook1, MCR1);
		await wAsset1.forceHarvest();
		await setPrice(_10To18.mul(new BN(3)));
		/*
			asset0 is borrowed
			asset1 is supplied
		*/
		apy0BN = await orderbook0.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 2.0;

		let amountBorrowed = 100000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(zcbAsset2.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset2.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset2.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): ZCB > YT, (FCP supplied in payout phase)', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 2.0;

		let amountSupplied = 100000000;
		let amountBond = 20000000;
		let collateralizationRatio = upperRatio0*upperRatio1;
		let compositeSupplied = amountSupplied + amountBond*rateMultiplier1;
		let expectedAmountBorrowed = Math.floor(compositeSupplied/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp2.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		if (error > ErrorRange) {
			console.log(amountSupplied, amountBond);
			console.log(rateMultiplier0, rateMultiplier1);
			console.log(price, collateralizationRatio);
			console.log(compositeSupplied);
			console.log(expectedAmountBorrowed);
			console.log(rec.tx);
		}
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied+amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp2.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp2.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): ZCB == YT', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 100000000;
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(amountSupplied * rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp1.address, fcp0.address, amountSupplied, 0);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp0.address, amountSupplied, 0, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp0.address, amountSupplied, 0, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesLowerLimit(): ZCB == YT', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 100000000;
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountBorrowed = Math.floor(amountSupplied * rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtLowerLimit(fcp1.address, fcp0.address, amountSupplied, 0);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesLowerLimit(fcp1.address, fcp0.address, amountSupplied, 0, actualBN), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesLowerLimit(fcp1.address, fcp0.address, amountSupplied, 0, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesLowerLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): ZCB > YT', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy1BN = await orderbook1.getAPYFromOracle();
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let adjAPY1 = (APY1-1)*upperThreshold1 + 1;

		let temp1 = APY1+minUpperRateAdjustment;

		adjAPY1 = Math.max(adjAPY1, temp1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;
		let amountBond = 20000000;
		let collateralizationRatio = upperRatio0*upperRatio1;
		let compositeSupplied = amountSupplied + amountBond*rateMultiplier1;
		let expectedAmountBorrowed = Math.floor(compositeSupplied/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp1.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied+amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesLowerLimit(): ZCB > YT', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let adjAPY1 = (APY1-1)*lowerThreshold1 + 1;

		let temp1 = APY1+minLowerRateAdjustment;

		adjAPY1 = Math.max(adjAPY1, temp1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;
		let amountBond = 20000000;
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let compositeSupplied = amountSupplied + amountBond*rateMultiplier1;
		let expectedAmountBorrowed = Math.floor(compositeSupplied/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtLowerLimit(fcp1.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied+amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesLowerLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesLowerLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesLowerLimit");
	});

	it('YTvaultSatisfiesUpperLimit(): ZCB < YT', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let adjAPY1 = (APY1-1)/upperThreshold1 + 1;

		let temp1 = APY1-minUpperRateAdjustment;

		adjAPY1 = Math.min(adjAPY1, temp1);

		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;
		let amountBond = -20000000;
		let collateralizationRatio = upperRatio0*upperRatio1;
		let compositeSupplied = amountSupplied + amountBond*rateMultiplier1;
		let expectedAmountBorrowed = Math.floor(compositeSupplied/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtUpperLimit(fcp1.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied-amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesUpperLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesUpperLimit");
	});

	it('YTvaultSatisfiesLowerLimit(): ZCB < YT', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minLowerRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let adjAPY1 = (APY1-1)/lowerThreshold1 + 1;

		let temp1 = APY1-minLowerRateAdjustment;

		adjAPY1 = Math.min(adjAPY1, temp1);

		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;
		let amountBond = -20000000;
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let compositeSupplied = amountSupplied + amountBond*rateMultiplier1;
		let expectedAmountBorrowed = Math.floor(compositeSupplied/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.YTvaultAmountBorrowedAtLowerLimit(fcp1.address, fcp0.address, amountSupplied, amountBond);
		let actual = parseInt(actualBN.toString());

		let error = AmountError(expectedAmountBorrowed, actual);
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/(amountSupplied-amountBond)) + 1);
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesLowerLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.YTvaultSatisfiesLowerLimit(fcp1.address, fcp0.address, amountSupplied, amountBond, actualBN.sub(new BN(needed))), true, "correct value returned by satisfiesLowerLimit");
	});

	it('vaultWithstandsChange: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await orderbook0.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 100000000;	//asset1
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtUpperLimit(wAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let res = await vaultHealthInstance.vaultWithstandsChange(false, wAsset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints, ABDK_1, ABDK_1);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(false, wAsset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints+1, ABDK_1, ABDK_1);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const _0 = "0";

		rateMultiplier0 = 1.0;
		rateMultiplier1 = 1.0;

		let priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(false, wAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, _0, _0);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(false, wAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, _0, _0);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const rateChange0 = 2.43;
		const rateChange0Str = basisPointsToABDKString(24300);

		adjAPY0 = (APY0-1)/upperThreshold0*rateChange0 + 1;

		temp0 = (APY0-1)*rateChange0-minUpperRateAdjustment + 1;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		rateMultiplier0 = adjAPY0**(-yearsRemaining);

		priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(false, wAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, _0, rateChange0Str);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(false, wAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, _0, rateChange0Str);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");
	});

	it('vaultWithstandsChange: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await orderbook0.getAPYFromOracle();
		apy1BN = await orderbook1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;
		let adjAPY1 = (APY1-1)*upperThreshold1 + 1;

		let temp0 = APY0-minUpperRateAdjustment;
		let temp1 = APY1+minUpperRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 100000000;	//asset1
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let res = await vaultHealthInstance.vaultWithstandsChange(false, zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints, ABDK_1, ABDK_1);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(false, zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints+1, ABDK_1, ABDK_1);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const _0 = "0";

		adjAPY0 = 1.0;
		adjAPY1 = 1.0+minUpperRateAdjustment;

		rateMultiplier0 = 1.0;
		rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(false, zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, _0, _0);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(false, zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, _0, _0);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const rateChange0 = 1.5;
		const rateChange1 = 0.94;
		const rateChange0Str = basisPointsToABDKString(15000);
		const rateChange1Str = basisPointsToABDKString(9400);

		adjAPY0 = (APY0-1)/upperThreshold0*rateChange0 + 1;
		adjAPY1 = (APY1-1)*upperThreshold1*rateChange1 + 1;

		temp0 = (APY0-1)*rateChange0-minUpperRateAdjustment + 1;
		temp1 = (APY1-1)*rateChange1+minUpperRateAdjustment + 1;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		rateMultiplier0 = adjAPY0**(-yearsRemaining);
		rateMultiplier1 = adjAPY1**(-yearsRemaining);

		priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(false, zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, rateChange1Str, rateChange0Str);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(false, zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, rateChange1Str, rateChange0Str);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");
	});

	it('set maximum short interest', async () => {
		let setTo = '23123123123';

		let caught = false;
		try {
			await vaultHealthInstance.setMaximumShortInterest(asset0.address, setTo, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail('setMaximumShortInterest() should be onlyOwner');
		}

		await vaultHealthInstance.setMaximumShortInterest(asset0.address, setTo);

		assert.equal((await vaultHealthInstance.maximumShortInterest(asset0.address)).toString(), setTo, "correct value for maximum short interest");
	});
});
