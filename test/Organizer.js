const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const FCPDelegate2 = artifacts.require('FCPDelegate2');
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
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const QuickDepositorDeployer = artifacts.require('QuickDepositorDeployer');
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
		BigMathInstance = await BigMath.new();
		fcpDelegate1Instance = await FCPDelegate1.new();
		fcpDelegate2Instance = await FCPDelegate2.new();
		fixCapitalPoolDeployerInstance = await FixCapitalPoolDeployer.new(fcpDelegate1Instance.address, fcpDelegate2Instance.address);
		infoOracleInstance = await InfoOracle.new(treasuryAddress, true);
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
			orderbookDeployerInstance.address,
			quickDepositorDeployerInstance.address,
			infoOracleInstance.address
		);
		assert.equal(await organizerInstance.InfoOracleAddress(), infoOracleInstance.address);
		assert.notEqual(await organizerInstance.QuickDepositorAddress(), nullAddress);

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

});