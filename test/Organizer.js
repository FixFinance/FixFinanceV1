const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const FixCapitalPool = artifacts.require('FixCapitalPool');
const YieldToken = artifacts.require('YieldToken');
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapperDeployer = artifacts.require('NGBwrapperDeployer');
const OrderbookDelegate1 = artifacts.require("OrderbookDelegate1");
const OrderbookDelegate2 = artifacts.require("OrderbookDelegate2");
const OrderbookDelegate3 = artifacts.require("OrderbookDelegate3");
const OrderbookDeployer = artifacts.require("OrderbookDeployer");
const organizer = artifacts.require('Organizer');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const ZCBamm = artifacts.require('ZCBamm');
const YTamm = artifacts.require('YTamm');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const QuickDepositorDeployer = artifacts.require('QuickDepositorDeployer');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
const SwapRouter = artifacts.require("SwapRouter");
const InfoOracle = artifacts.require("InfoOracle");

const helper = require("../helper/helper.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const treasuryAddress = "0x0000000000000000000000000000000000000001";
const _10To18BN = (new BN("10")).pow(new BN("18"));
const LENGTH_RATE_SERIES = 31;

contract('Organizer', function(accounts) {

	it('before each', async () => {

		zcbYtDeployerInstance = await zcbYtDeployer.new();
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
		fcpDelegate1Instance = await FCPDelegate1.new();
		fixCapitalPoolDeployerInstance = await FixCapitalPoolDeployer.new(fcpDelegate1Instance.address);
		swapRouterDelegateInstance = await SwapRouterDelegate.new();
		swapRouterDeployerInstance = await SwapRouterDeployer.new(swapRouterDelegateInstance.address);
		infoOracleInstance = await InfoOracle.new("0", treasuryAddress);
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
			infoOracleInstance.address,
			orderbookDelegate1Instance.address,
			orderbookDelegate2Instance.address,
			orderbookDelegate3Instance.address
		);
		quickDepositorDeployerInstance = await QuickDepositorDeployer.new();
		organizerInstance = await organizer.new(
			NGBwrapperDeployerInstance.address,
			zcbYtDeployerInstance.address,
			fixCapitalPoolDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			orderbookDeployerInstance.address,
			quickDepositorDeployerInstance.address,
			swapRouterDeployerInstance.address,
			infoOracleInstance.address
		);
		assert.equal(await organizerInstance.InfoOracleAddress(), infoOracleInstance.address);
		assert.notEqual(await organizerInstance.QuickDepositorAddress(), nullAddress);
		await organizerInstance.DeploySwapRouter();
		router = await SwapRouter.at(await organizerInstance.SwapRouterAddress());

		assert.notEqual(router.address, nullAddress, "SwapRouter is non null");
		maturity = (await web3.eth.getBlock('latest')).timestamp + 1000000;
		asset0 = await dummyAToken.new("aCOIN");
	});

	it('deploy NGB wrapper', async () => {
		let rec = await organizerInstance.deployNGBWrapper(asset0.address);
		assert.equal(rec.receipt.logs[0].args.underlyingAddress, asset0.address, "correct value in event of underlyingAddress");
		assert.notEqual(rec.receipt.logs[0].args.wrapperAddress, nullAddress, "wrapper address must be non null");
		wAsset0 = await NGBwrapper.at(rec.receipt.logs[0].args.wrapperAddress);
	});

	it('deploy FixCapitalPool', async () => {
		let rec = await organizerInstance.deployFixCapitalPoolInstance(wAsset0.address, maturity);
		fixCapitalPoolInstance = await FixCapitalPool.at(rec.receipt.logs[0].args.FCPaddress);
		yieldTokenInstance = await YieldToken.at(await fixCapitalPoolInstance.yieldTokenAddress());
		zcbInstance = await IERC20.at(await fixCapitalPoolInstance.zeroCouponBondAddress());
		assert.notEqual(fixCapitalPoolInstance.address, nullAddress, "organizer::fixCapitalPoolMapping[asset0] must be non-null");
	});

	it('deploy ZCBamm', async () => {
		await organizerInstance.deployZCBamm(fixCapitalPoolInstance.address);
		ZCBammInstance = await ZCBamm.at(await organizerInstance.ZCBamms(fixCapitalPoolInstance.address));
	});

	it('cannot override ZCBamm deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployZCBamm(fixCapitalPoolInstance.address);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::ZCBamms[fixCapitalPoolInstance] was overridden');


		//set the rate in the ZCBamm so that they YT amm may be deployed
		amm0 = await ZCBamm.at(await organizerInstance.ZCBamms(fixCapitalPoolInstance.address));

		balance = _10To18BN;
		await asset0.approve(wAsset0.address, balance);
		await wAsset0.depositUnitAmount(accounts[0], balance);
		await wAsset0.approve(fixCapitalPoolInstance.address, balance);
		await fixCapitalPoolInstance.depositWrappedToken(accounts[0], balance);
		await zcbInstance.approve(amm0.address, balance);
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
		await organizerInstance.deployYTamm(fixCapitalPoolInstance.address);
		YTammInstance = await YTamm.at(await organizerInstance.YTamms(fixCapitalPoolInstance.address));
	});

	it('cannot override YTamm deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployYTamm(fixCapitalPoolInstance.address);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::YTamms[fixCapitalPoolInstance] was overridden');
	});

});