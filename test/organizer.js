const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const AaveWrapper = artifacts.require('AaveWrapper');
const CapitalHandler = artifacts.require('CapitalHandler');
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
const FeeOracle = artifacts.require("FeeOracle");

const nullAddress = "0x0000000000000000000000000000000000000000";

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
		feeOracleInstance = await FeeOracle.new("0", "0");
		organizerInstance = await organizer.new(
			yieldTokenDeployerInstance.address,
			bondMinterInstance.address,
			capitalHandlerDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			swapRouterDeployerInstance.address,
			feeOracleInstance.address
		);
		assert.equal(await organizerInstance.FeeOracleAddress(), feeOracleInstance.address);
		await organizerInstance.DeploySwapRouter();
		router = await SwapRouter.at(await organizerInstance.SwapRouterAddress());

		assert.notEqual(router.address, nullAddress, "SwapRouter is non null");
		maturity = (await web3.eth.getBlock('latest')).timestamp + 1000000;
		asset0 = await dummyAToken.new();
	});

	it('deploy aToken wrapper', async () => {
		await organizerInstance.deployATokenWrapper(asset0.address);
		wAsset0 = await AaveWrapper.at(await organizerInstance.aTokenWrappers(asset0.address));
		assert.notEqual(wAsset0.address, nullAddress, "organizer::aTokenWrappers[asset0] must be non-null");
	});

	it('cannot override aToken wrapper deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployATokenWrapper(asset0.address);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::aTokenWrappers[asset0] was overridden');
	});

	it('deploy CapitalHandler', async () => {
		await organizerInstance.deployCapitalHandlerInstance(asset0.address, maturity);
		capitalHandlerInstance = await CapitalHandler.at(await organizerInstance.capitalHandlerMapping(asset0.address, maturity));
		assert.notEqual(capitalHandlerInstance.address, nullAddress, "organizer::capitalHandlerMapping[asset0] must be non-null");
	});

	it('cannot override CapitalHandler deployment', async () => {
		let caught = false;
		try {
			await organizerInstance.deployCapitalHandlerInstance(asset0.address, maturity);
		} catch (err) {
			caught = true
		}
		if (!caught) assert.fail('organizer::aTokenWrappers[asset0] was overridden');
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