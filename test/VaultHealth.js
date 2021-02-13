const dummyAToken = artifacts.require('dummyAToken');
const VaultHealth = artifacts.require('VaultHealth');
const aaveWrapper = artifacts.require('AaveWrapper');
const capitalHandler = artifacts.require('CapitalHandler');
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

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const DECIMALS = 18;
const _10To18 = (new BN('10')).pow(new BN('18'));

const symbol0 = "aETH";
const symbol1 = "aUSDT";
const phrase = symbol0.substring(1)+" / "+symbol1.substring(1);
const _8days = 8*24*60*60;

contract('VaultHealth', async function(accounts) {
	it('before each', async () => {
		//borrow asset 0
		asset0 = await dummyAToken.new(symbol0);
		//supply asset 1
		asset1 = await dummyAToken.new(symbol1);
		aggregator = await dummyAggregator.new(DECIMALS, phrase);
		OracleContainerInstance = await OracleContainer.new(nullAddress);
		await OracleContainerInstance.addAggregators([aggregator.address]);

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

		maturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

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

		//mint assets to account 0
		await asset1.mintTo(accounts[0], _10To18.mul(new BN("10")).toString());
		await asset1.approve(wAsset1.address, _10To18.mul(new BN("10")).toString());
		await wAsset1.deposit(accounts[0], _10To18.mul(new BN("10")).toString());
		await wAsset1.approve(bondMinterInstance.address, _10To18.mul(new BN("10")).toString());
		await zcbAsset0.approve(bondMinterInstance.address, _10To18.mul(new BN("10")).toString());

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To18.mul(new BN("10")).toString());
		await asset0.approve(wAsset0.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await wAsset0.deposit(accounts[1], _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await wAsset0.approve(zcbAsset0.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await zcbAsset0.depositWrappedToken(accounts[1], _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await zcbAsset0.approve(bondMinterInstance.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
	});


});