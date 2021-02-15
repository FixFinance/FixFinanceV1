const dummyAToken = artifacts.require('dummyAToken');
const VaultHealth = artifacts.require('VaultHealth');
const aaveWrapper = artifacts.require('AaveWrapper');
const capitalHandler = artifacts.require('CapitalHandler');
const YieldToken = artifacts.require("YieldToken");
const yieldTokenDeployer = artifacts.require('YieldTokenDeployer');
const organizer = artifacts.require('organizer');
const BondMinter = artifacts.require('BondMinter');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const DeployCapitalHandler = artifacts.require('DeployCapitalHandler');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDeployer = artifacts.require('YTammDeployer');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
const FeeOracle = artifacts.require("FeeOracle");
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
const _80days = 80*24*60*60;

const TotalBasisPoints = 10000;

const SecondsPerYear = 31556926;

const minRateAdjustment = 0.01;

const ErrorRange = 10**-7;

function basisPointsToABDKString(bips) {
	return (new BN(bips)).mul((new BN(2)).pow(new BN(64))).div(_10.pow(new BN(4))).toString();
}

const ABDK_1 = basisPointsToABDKString(TotalBasisPoints);

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
		OracleContainerInstance = await OracleContainer.new(nullAddress);
		await OracleContainerInstance.addAggregators([aggregator0.address, aggregator1.address]);
		await OracleContainerInstance.AddAToken(asset0.address);
		await OracleContainerInstance.AddAToken(asset1.address);

		yieldTokenDeployerInstance = await yieldTokenDeployer.new();
		vaultHealthInstance = await VaultHealth.new(OracleContainerInstance.address);
		bondMinterInstance = await BondMinter.new(vaultHealthInstance.address);
		BigMathInstance = await BigMath.new();
		await ZCBammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDeployer.link("BigMath", BigMathInstance.address);
		ZCBammDeployerInstance = await ZCBammDeployer.new();
		YTammDeployerInstance = await YTammDeployer.new();
		DeployCapitalHandlerInstance = await DeployCapitalHandler.new();
		swapRouterDeployerInstance = await SwapRouterDeployer.new();
		feeOracleInstance = await FeeOracle.new("0", "0");
		organizerInstance = await organizer.new(
			yieldTokenDeployerInstance.address,
			bondMinterInstance.address,
			DeployCapitalHandlerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			swapRouterDeployerInstance.address,
			feeOracleInstance.address
		);
		await vaultHealthInstance.setOrganizerAddress(organizerInstance.address);

		maturity = ((await web3.eth.getBlock('latest')).timestamp + _80days).toString();

		await organizerInstance.deployATokenWrapper(asset0.address);
		await organizerInstance.deployATokenWrapper(asset1.address);
		await organizerInstance.deployCapitalHandlerInstance(asset0.address, maturity);
		await organizerInstance.deployCapitalHandlerInstance(asset1.address, maturity);

		wAsset0 = await aaveWrapper.at(await organizerInstance.aTokenWrappers(asset0.address));
		wAsset1 = await aaveWrapper.at(await organizerInstance.aTokenWrappers(asset1.address));

		await asset0.approve(wAsset0.address, _10To18.toString());
		await asset1.approve(wAsset1.address, _10To18.toString());

		await wAsset0.deposit(accounts[0], _10To18.toString());
		await wAsset1.deposit(accounts[0], _10To18.toString());

		zcbAsset0 = await capitalHandler.at(await organizerInstance.capitalHandlerMapping(asset0.address, maturity));
		zcbAsset1 = await capitalHandler.at(await organizerInstance.capitalHandlerMapping(asset1.address, maturity));

		ytAsset0 = await YieldToken.at(await zcbAsset0.yieldTokenAddress());
		ytAsset1 = await YieldToken.at(await zcbAsset1.yieldTokenAddress());

		await organizerInstance.deployZCBamm(zcbAsset0.address);
		await organizerInstance.deployZCBamm(zcbAsset1.address);

		amm0 = await ZCBamm.at(await organizerInstance.ZCBamms(zcbAsset0.address));
		amm1 = await ZCBamm.at(await organizerInstance.ZCBamms(zcbAsset1.address));


		//mint asset0 assets to account 0
		await asset0.mintTo(accounts[0], _10To19.mul(_10));
		await asset0.approve(wAsset0.address, _10To19.mul(_10));
		await wAsset0.deposit(accounts[0], _10To19.mul(_10));
		await wAsset0.approve(zcbAsset0.address, _10To19);
		await zcbAsset0.depositWrappedToken(accounts[0], _10To19);
		await wAsset0.approve(bondMinterInstance.address, _10To19);
		await zcbAsset0.approve(bondMinterInstance.address, _10To19);
		await zcbAsset0.approve(amm0.address, _10To19);
		await ytAsset0.approve(amm0.address, _10To19);

		//mint asset1 assets to account 0
		await asset1.mintTo(accounts[0], _10To19.mul(_10));
		await asset1.approve(wAsset1.address, _10To19.mul(_10));
		await wAsset1.deposit(accounts[0], _10To19.mul(_10));
		await wAsset1.approve(zcbAsset1.address, _10To19);
		await zcbAsset1.depositWrappedToken(accounts[0], _10To19);
		await wAsset1.approve(bondMinterInstance.address, _10To19);
		await zcbAsset1.approve(bondMinterInstance.address, _10To19);
		await zcbAsset1.approve(amm1.address, _10To19);
		await ytAsset1.approve(amm1.address, _10To19);

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To19.mul(_10));
		await asset0.approve(wAsset0.address, _10To19.mul(_10), {from: accounts[1]});
		await wAsset0.deposit(accounts[1], _10To19.mul(_10), {from: accounts[1]});
		await wAsset0.approve(zcbAsset0.address, _10To19, {from: accounts[1]});
		await zcbAsset0.depositWrappedToken(accounts[1], _10To19, {from: accounts[1]});
		await zcbAsset0.approve(bondMinterInstance.address, _10To19, {from: accounts[1]});
		await wAsset0.approve(bondMinterInstance.address, _10To19, {from: accounts[1]});

		//add liquidity to amms
		let toSend = _10To18.div(_10).div(_10);
		await amm0.firstMint(toSend, toSend.div(_10));
		await amm1.firstMint(toSend, toSend.div(_10));
		//mint a few more times such that we have 3 records of the pool apys
		await amm0.mint(_10, _10To18, _10To18);
		await amm0.mint(_10, _10To18, _10To18);
		await amm0.mint(_10, _10To18, _10To18);

		await amm1.mint(_10, _10To18, _10To18);
		await amm1.mint(_10, _10To18, _10To18);
		await amm1.mint(_10, _10To18, _10To18);
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
		middleRatio0 = 1.06;
		lowerRatio0 = 1.05;
		UpperRatio0Str = basisPointsToABDKString(10700);	//107%
		MiddleRatio0Str = basisPointsToABDKString(10600);	//106%
		LowerRatio0Str = basisPointsToABDKString(10500);	//105%
		await vaultHealthInstance.setCollateralizationRatios(asset0.address, UpperRatio0Str, MiddleRatio0Str, LowerRatio0Str);
		let _upper = await vaultHealthInstance.UpperCollateralizationRatio(asset0.address);
		let _middle = await vaultHealthInstance.MiddleCollateralizationRatio(asset0.address);
		let _lower = await vaultHealthInstance.LowerCollateralizationRatio(asset0.address);
		assert.equal(_upper.toString(), UpperRatio0Str, "correct lower rate threshold");
		assert.equal(_middle.toString(), MiddleRatio0Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerRatio0Str, "correct lower rate threshold");

		//asset1 ratios
		upperRatio1 = 1.12;
		middleRatio1 = 1.11;
		lowerRatio1 = 1.09;
		UpperRatio1Str = basisPointsToABDKString(11200);	//112%
		MiddleRatio1Str = basisPointsToABDKString(11100);	//111%
		LowerRatio1Str = basisPointsToABDKString(10900);	//109%
		await vaultHealthInstance.setCollateralizationRatios(asset1.address, UpperRatio1Str, MiddleRatio1Str, LowerRatio1Str);
		_upper = await vaultHealthInstance.UpperCollateralizationRatio(asset1.address);
		_middle = await vaultHealthInstance.MiddleCollateralizationRatio(asset1.address);
		_lower = await vaultHealthInstance.LowerCollateralizationRatio(asset1.address);
		assert.equal(_upper.toString(), UpperRatio1Str, "correct lower rate threshold");
		assert.equal(_middle.toString(), MiddleRatio1Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerRatio1Str, "correct lower rate threshold");
	});

	it('set rate thresholds', async () => {
		//asset0 thresholds
		upperThreshold0 = 1.5;
		middleThreshold0 = 1.4;
		lowerThreshold0 = 1.3;
		UpperThreshold0Str = basisPointsToABDKString(15000);	//150%
		MiddleThreshold0Str = basisPointsToABDKString(14000);	//140%
		LowerThreshold0Str = basisPointsToABDKString(13000);	//130%
		await vaultHealthInstance.setRateThresholds(asset0.address, UpperThreshold0Str, MiddleThreshold0Str, LowerThreshold0Str);
		let _upper = await vaultHealthInstance.UpperRateThreshold(asset0.address);
		let _middle = await vaultHealthInstance.MiddleRateThreshold(asset0.address);
		let _lower = await vaultHealthInstance.LowerRateThreshold(asset0.address);
		assert.equal(_upper.toString(), UpperThreshold0Str, "correct lower rate threshold");
		assert.equal(_middle.toString(), MiddleThreshold0Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerThreshold0Str, "correct lower rate threshold");

		//asset1 thresholds
		upperThreshold1 = 2.0;
		middleThreshold1 = 1.7;
		lowerThreshold1 = 1.5;
		UpperThreshold1Str = basisPointsToABDKString(20000);	//100%
		MiddleThreshold1Str = basisPointsToABDKString(17000);	//170%
		LowerThreshold1Str = basisPointsToABDKString(15000);	//150%
		await vaultHealthInstance.setRateThresholds(asset1.address, UpperThreshold1Str, MiddleThreshold1Str, LowerThreshold1Str);
		_upper = await vaultHealthInstance.UpperRateThreshold(asset1.address);
		_middle = await vaultHealthInstance.MiddleRateThreshold(asset1.address);
		_lower = await vaultHealthInstance.LowerRateThreshold(asset1.address);
		assert.equal(_upper.toString(), UpperThreshold1Str, "correct lower rate threshold");
		assert.equal(_middle.toString(), MiddleThreshold1Str, "correct lower rate threshold");
		assert.equal(_lower.toString(), LowerThreshold1Str, "correct lower rate threshold");
	});

	it('amountSuppliedAtUpperLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		/*
			asset0 is borrowed
			asset1 is supplied
		*/
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;
		let adjAPY1 = (APY1-1)*upperThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountBorrowed = 10000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(zcbAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtUpperLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountBorrowed = 10000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtUpperLimit(asset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(asset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(asset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesUpperLimit");
	});

	it('amountSuppliedAtMiddleLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/middleThreshold0 + 1;
		let adjAPY1 = (APY1-1)*middleThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountBorrowed = 10000000;	//asset0
		let collateralizationRatio = middleRatio0*middleRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtMiddleLimit(zcbAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesMiddleLimit(zcbAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesMiddleLimit");
		assert.equal(await vaultHealthInstance.satisfiesMiddleLimit(zcbAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesMiddleLimit");
	});

	it('amountSuppliedAtMiddleLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/middleThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountBorrowed = 10000000;	//asset0
		let collateralizationRatio = middleRatio0*middleRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtMiddleLimit(asset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesMiddleLimit(asset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesMiddleLimit");
		assert.equal(await vaultHealthInstance.satisfiesMiddleLimit(asset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesMiddleLimit");
	});

	it('amountSuppliedAtLowerLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;
		let adjAPY1 = (APY1-1)*lowerThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountBorrowed = 10000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtLowerLimit(zcbAsset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesLowerLimit");
	});

	it('amountSuppliedAtLowerLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountBorrowed = 10000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountSupplied = Math.floor(amountBorrowed*rateMultiplier0*price*collateralizationRatio/rateMultiplier1);
		let actualBN = await vaultHealthInstance.amountSuppliedAtLowerLimit(asset1.address, zcbAsset0.address, amountBorrowed)
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountSupplied-actual) / expectedAmountSupplied;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = Math.ceil(actual/amountBorrowed) + 1;
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(asset1.address, zcbAsset0.address, actualBN, amountBorrowed), false, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(asset1.address, zcbAsset0.address, actualBN.add(new BN(needed)), amountBorrowed), true, "correct value returned by satisfiesLowerLimit");
	});

	it('amountBorrowedAtUpperLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;
		let adjAPY1 = (APY1-1)*upperThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 10000000;	//asset1
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountBorrowed-actual) / expectedAmountBorrowed;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);

		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesUpperLimit");
	});

	it('amountBorrowedAtUpperLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/upperThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 10000000;	//asset0
		let collateralizationRatio = upperRatio0*upperRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtUpperLimit(asset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountBorrowed-actual) / expectedAmountBorrowed;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(asset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesUpperLimit");
		assert.equal(await vaultHealthInstance.satisfiesUpperLimit(asset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesUpperLimit");
	});

	it('amountBorrowedAtMiddleLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/middleThreshold0 + 1;
		let adjAPY1 = (APY1-1)*middleThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 10000000;	//asset1
		let collateralizationRatio = middleRatio0*middleRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtMiddleLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountBorrowed-actual) / expectedAmountBorrowed;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);

		assert.equal(await vaultHealthInstance.satisfiesMiddleLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesMiddleLimit");
		assert.equal(await vaultHealthInstance.satisfiesMiddleLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesMiddleLimit");
	});

	it('amountBorrowedAtMiddleLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 10000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtLowerLimit(asset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountBorrowed-actual) / expectedAmountBorrowed;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(asset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(asset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesLowerLimit");
	});

	it('amountBorrowedAtLowerLimit: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;
		let adjAPY1 = (APY1-1)*lowerThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 10000000;	//asset1
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtLowerLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountBorrowed-actual) / expectedAmountBorrowed;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);

		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesLowerLimit");
	});

	it('amountBorrowedAtLowerLimit: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		let adjAPY0 = (APY0-1)/lowerThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 10000000;	//asset0
		let collateralizationRatio = lowerRatio0*lowerRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtLowerLimit(asset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let error = (expectedAmountBorrowed-actual) / expectedAmountBorrowed;
		assert.isBelow(error, ErrorRange, "output within acceptable error range");

		let needed = new BN(Math.ceil(actual/amountSupplied) + 1);
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(asset1.address, zcbAsset0.address, amountSupplied, actualBN), true, "correct value returned by satisfiesLowerLimit");
		assert.equal(await vaultHealthInstance.satisfiesLowerLimit(asset1.address, zcbAsset0.address, amountSupplied, actualBN.add(new BN(needed))), false, "correct value returned by satisfiesLowerLimit");
	});

	it('vaultWithstandsChange: aToken deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/middleThreshold0 + 1;

		let temp0 = APY0-minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = 1.0;

		let amountSupplied = 10000000;	//asset1
		let collateralizationRatio = middleRatio0*middleRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtMiddleLimit(asset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let res = await vaultHealthInstance.vaultWithstandsChange(asset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints, ABDK_1, ABDK_1);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(asset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints+1, ABDK_1, ABDK_1);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const _0 = "0";

		rateMultiplier0 = 1.0;
		rateMultiplier1 = 1.0;

		let priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(asset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, _0, _0);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(asset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, _0, _0);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const rateChange0 = 2.43;
		const rateChange0Str = basisPointsToABDKString(24300);

		adjAPY0 = (APY0-1)/middleThreshold0*rateChange0 + 1;

		temp0 = (APY0-1)*rateChange0-minRateAdjustment + 1;

		adjAPY0 = Math.min(adjAPY0, temp0);

		adjAPY0 = Math.max(adjAPY0, 1);

		rateMultiplier0 = adjAPY0**(-yearsRemaining);

		priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(asset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, _0, rateChange0Str);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(asset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, _0, rateChange0Str);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");
	});

	it('vaultWithstandsChange: zcb deposited', async () => {
		await setPrice(_10To18.mul(new BN(3)));
		apy0BN = await amm0.getAPYFromOracle();
		apy1BN = await amm1.getAPYFromOracle();
		APY0 = (parseInt(apy0BN.toString()) * 2**-64);
		APY1 = (parseInt(apy1BN.toString()) * 2**-64);

		let adjAPY0 = (APY0-1)/middleThreshold0 + 1;
		let adjAPY1 = (APY1-1)*middleThreshold1 + 1;

		let temp0 = APY0-minRateAdjustment;
		let temp1 = APY1+minRateAdjustment;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		let yearsRemaining = (maturity - (await web3.eth.getBlock('latest')).timestamp)/ SecondsPerYear;

		let rateMultiplier0 = adjAPY0**(-yearsRemaining);
		let rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let amountSupplied = 10000000;	//asset1
		let collateralizationRatio = middleRatio0*middleRatio1;
		let expectedAmountBorrowed = Math.floor(rateMultiplier1/rateMultiplier0/price/collateralizationRatio);
		let actualBN = await vaultHealthInstance.amountBorrowedAtMiddleLimit(zcbAsset1.address, zcbAsset0.address, amountSupplied);
		let actual = parseInt(actualBN.toString());

		let res = await vaultHealthInstance.vaultWithstandsChange(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints, ABDK_1, ABDK_1);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, TotalBasisPoints+1, ABDK_1, ABDK_1);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const _0 = "0";

		adjAPY0 = 1.0;
		adjAPY1 = 1.0+minRateAdjustment;

		rateMultiplier0 = 1.0;
		rateMultiplier1 = adjAPY1**(-yearsRemaining);

		let priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, _0, _0);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, _0, _0);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");

		const rateChange0 = 1.5;
		const rateChange1 = 0.94;
		const rateChange0Str = basisPointsToABDKString(15000);
		const rateChange1Str = basisPointsToABDKString(9400);

		adjAPY0 = (APY0-1)/middleThreshold0*rateChange0 + 1;
		adjAPY1 = (APY1-1)*middleThreshold1*rateChange1 + 1;

		temp0 = (APY0-1)*rateChange0-minRateAdjustment + 1;
		temp1 = (APY1-1)*rateChange1+minRateAdjustment + 1;

		adjAPY0 = Math.min(adjAPY0, temp0);
		adjAPY1 = Math.max(adjAPY1, temp1);

		adjAPY0 = Math.max(adjAPY0, 1);
		adjAPY1 = Math.max(adjAPY1, 1);

		rateMultiplier0 = adjAPY0**(-yearsRemaining);
		rateMultiplier1 = adjAPY1**(-yearsRemaining);

		priceChange = Math.floor(TotalBasisPoints * amountSupplied / (actual * price * collateralizationRatio * rateMultiplier0 / rateMultiplier1));

		res = await vaultHealthInstance.vaultWithstandsChange(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange, rateChange1Str, rateChange0Str);
		assert.equal(res, true, "correct value returned by vaultWithstandsChange");

		res = await vaultHealthInstance.vaultWithstandsChange(zcbAsset1.address, zcbAsset0.address, amountSupplied, actualBN, priceChange+1, rateChange1Str, rateChange0Str);
		assert.equal(res, false, "correct value returned by vaultWithstandsChange");
	});
});
