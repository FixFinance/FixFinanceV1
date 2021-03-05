const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const AaveWrapper = artifacts.require('AaveWrapper');
const CapitalHandler = artifacts.require('CapitalHandler');
const YieldToken = artifacts.require('YieldToken');
const yieldTokenDeployer = artifacts.require('YieldTokenDeployer');
const organizer = artifacts.require('organizer');
const BondMinter = artifacts.require('BondMinter');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const CapitalHandlerDeployer = artifacts.require('CapitalHandlerDeployer');
const ZCBamm = artifacts.require('ZCBamm');
const YTamm = artifacts.require('YTamm');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDeployer = artifacts.require('YTammDeployer');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
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
		bondMinterInstance = await BondMinter.new(vaultHealthInstance.address);
		BigMathInstance = await BigMath.new();
		await ZCBammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDeployer.link("BigMath", BigMathInstance.address);
		ZCBammDeployerInstance = await ZCBammDeployer.new();
		YTammDeployerInstance = await YTammDeployer.new();
		capitalHandlerDeployerInstance = await CapitalHandlerDeployer.new();
		swapRouterDeployerInstance = await SwapRouterDeployer.new();
		ammInfoOracleInstance = await AmmInfoOracle.new("0", "0", "0", "0", nullAddress);
		organizerInstance = await organizer.new(
			yieldTokenDeployerInstance.address,
			bondMinterInstance.address,
			capitalHandlerDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			swapRouterDeployerInstance.address,
			ammInfoOracleInstance.address
		);
		assert.equal(await organizerInstance.AmmInfoOracleAddress(), ammInfoOracleInstance.address);
		await organizerInstance.DeploySwapRouter();
		router = await SwapRouter.at(await organizerInstance.SwapRouterAddress());

		assert.notEqual(router.address, nullAddress, "SwapRouter is non null");
		maturity = (await web3.eth.getBlock('latest')).timestamp + 1000000;
		asset0 = await dummyAToken.new("aCOIN");
	});

	it('deploy aToken wrapper', async () => {
		await organizerInstance.deployAssetWrapper(asset0.address);
		wAsset0 = await AaveWrapper.at(await organizerInstance.assetWrappers(asset0.address));
		assert.notEqual(wAsset0.address, nullAddress, "organizer::assetWrappers[asset0] must be non-null");
	});

	it('cannot override aToken wrapper deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployAssetWrapper(asset0.address);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::assetWrappers[asset0] was overridden');
	});

	it('deploy CapitalHandler', async () => {
		await organizerInstance.deployCapitalHandlerInstance(asset0.address, maturity);
		capitalHandlerInstance = await CapitalHandler.at(await organizerInstance.capitalHandlerMapping(asset0.address, maturity));
		yieldTokenInstance = await YieldToken.at(await capitalHandlerInstance.yieldTokenAddress());
		assert.notEqual(capitalHandlerInstance.address, nullAddress, "organizer::capitalHandlerMapping[asset0] must be non-null");
	});

	it('cannot override CapitalHandler deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployCapitalHandlerInstance(asset0.address, maturity);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('capital handler deployment was overridden');
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