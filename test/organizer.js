const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const CapitalHandler = artifacts.require('CapitalHandler');
const YieldToken = artifacts.require('YieldToken');
const yieldTokenDeployer = artifacts.require('YieldTokenDeployer');
const organizer = artifacts.require('organizer');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const CapitalHandlerDeployer = artifacts.require('CapitalHandlerDeployer');
const ZCBamm = artifacts.require('ZCBamm');
const YTamm = artifacts.require('YTamm');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
const SwapRouter = artifacts.require("SwapRouter");
const AmmInfoOracle = artifacts.require("AmmInfoOracle");

const helper = require("../helper/helper.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10To18BN = (new BN("10")).pow(new BN("18"));
const LENGTH_RATE_SERIES = 31;

contract('organizer', function(accounts) {

	it('before each', async () => {

		yieldTokenDeployerInstance = await yieldTokenDeployer.new();
		vaultHealthInstance = await dummyVaultHealth.new();
		EiInstance = await Ei.new();
		await BigMath.link("Ei", EiInstance.address);
		BigMathInstance = await BigMath.new();
		await ZCBammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDelegate.link("BigMath", BigMathInstance.address);
		ZCBammDeployerInstance = await ZCBammDeployer.new();
		YTammDelegateInstance = await YTammDelegate.new();
		YTammDeployerInstance = await YTammDeployer.new(YTammDelegateInstance.address);
		capitalHandlerDeployerInstance = await CapitalHandlerDeployer.new();
		swapRouterDelegateInstance = await SwapRouterDelegate.new();
		swapRouterDeployerInstance = await SwapRouterDeployer.new(swapRouterDelegateInstance.address);
		ammInfoOracleInstance = await AmmInfoOracle.new("0", nullAddress);
		organizerInstance = await organizer.new(
			yieldTokenDeployerInstance.address,
			capitalHandlerDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			swapRouterDeployerInstance.address,
			ammInfoOracleInstance.address,
			accounts[4]
		);
		assert.equal(await organizerInstance.AmmInfoOracleAddress(), ammInfoOracleInstance.address);
		await organizerInstance.DeploySwapRouter();
		router = await SwapRouter.at(await organizerInstance.SwapRouterAddress());

		assert.notEqual(router.address, nullAddress, "SwapRouter is non null");
		maturity = (await web3.eth.getBlock('latest')).timestamp + 1000000;
		asset0 = await dummyAToken.new("aCOIN");
	});

	it('deploy aToken wrapper', async () => {
		let rec = await organizerInstance.deployAssetWrapper(asset0.address);
		assert.equal(rec.receipt.logs[0].args.underlyingAddress, asset0.address, "correct value in event of underlyingAddress");
		assert.notEqual(rec.receipt.logs[0].args.wrapperAddress, nullAddress, "wrapper address must be non null");
		wAsset0 = await NGBwrapper.at(rec.receipt.logs[0].args.wrapperAddress);
	});

	it('deploy CapitalHandler', async () => {
		let rec = await organizerInstance.deployCapitalHandlerInstance(wAsset0.address, maturity);
		capitalHandlerInstance = await CapitalHandler.at(rec.receipt.logs[0].args.addr);
		yieldTokenInstance = await YieldToken.at(await capitalHandlerInstance.yieldTokenAddress());
		assert.notEqual(capitalHandlerInstance.address, nullAddress, "organizer::capitalHandlerMapping[asset0] must be non-null");
	});

	it('deploy ZCBamm', async () => {
		await organizerInstance.deployZCBamm(capitalHandlerInstance.address);
		ZCBammInstance = await ZCBamm.at(await organizerInstance.ZCBamms(capitalHandlerInstance.address));
	});

	it('cannot override ZCBamm deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployZCBamm(capitalHandlerInstance.address);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::ZCBamms[capitalHandlerInstance] was overridden');


		//set the rate in the ZCBamm so that they YT amm may be deployed
		amm0 = await ZCBamm.at(await organizerInstance.ZCBamms(capitalHandlerInstance.address));

		balance = _10To18BN;
		await asset0.approve(wAsset0.address, balance);
		await wAsset0.depositUnitAmount(accounts[0], balance);
		await wAsset0.approve(capitalHandlerInstance.address, balance);
		await capitalHandlerInstance.depositWrappedToken(accounts[0], balance);
		await capitalHandlerInstance.approve(amm0.address, balance);
		await yieldTokenInstance.approve(amm0.address, balance);

		Uin = balance.div(new BN("10"));
		ZCBin = balance.div(new BN("300"));
		rec = await amm0.firstMint(Uin, ZCBin);
		/*
			set rate in amm0
		*/
		for (let i = 0; i < LENGTH_RATE_SERIES; i++) {
			await amm0.forceRateDataUpdate();
			//advance 2 minuites
			helper.advanceTime(121);
		}
		let OracleRateString = (await amm0.getImpliedRateData())._impliedRates[0].toString();
		await amm0.setOracleRate(OracleRateString);
	});

	it('deploy YTamm', async () => {
		await organizerInstance.deployYTamm(capitalHandlerInstance.address);
		YTammInstance = await YTamm.at(await organizerInstance.YTamms(capitalHandlerInstance.address));
	});

	it('cannot override YTamm deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployYTamm(capitalHandlerInstance.address);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::YTamms[capitalHandlerInstance] was overridden');
	});

});