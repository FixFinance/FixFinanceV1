const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const FCPDelegate2 = artifacts.require('FCPDelegate2');
const FixCapitalPool = artifacts.require('FixCapitalPool');
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const dummyAToken = artifacts.require('dummyAToken');
const organizer = artifacts.require('Organizer');
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapperDeployer = artifacts.require('NGBwrapperDeployer');
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const OracleContainer = artifacts.require('OracleContainer');
const OracleDeployer = artifacts.require('OracleDeployer');
const VaultHealth = artifacts.require("VaultHealth");
const VaultHealthDeployer = artifacts.require("VaultHealthDeployer");
//NSFVaultFactory
const NSFVaultFactoryDelegate1 = artifacts.require("NSFVaultFactoryDelegate1");
const NSFVaultFactoryDelegate2 = artifacts.require("NSFVaultFactoryDelegate2");
const NSFVaultFactoryDelegate3 = artifacts.require("NSFVaultFactoryDelegate3");
const NSFVaultFactoryDelegate4 = artifacts.require("NSFVaultFactoryDelegate4");
const NSFVaultFactoryDelegate5 = artifacts.require("NSFVaultFactoryDelegate5");
const NSFVFDeployer = artifacts.require("NSFVaultFactoryDeployer");
const NSFVaultFactory = artifacts.require("NSFVaultFactory");
//SBNSFVaultFactory
const SBNSFVaultFactoryDelegate1 = artifacts.require("SBNSFVaultFactoryDelegate1");
const SBNSFVaultFactoryDelegate2 = artifacts.require("SBNSFVaultFactoryDelegate2");
const SBNSFVaultFactoryDelegate3 = artifacts.require("SBNSFVaultFactoryDelegate3");
const SBNSFVaultFactoryDelegate4 = artifacts.require("SBNSFVaultFactoryDelegate4");
const SBNSFVaultFactoryDelegate5 = artifacts.require("SBNSFVaultFactoryDelegate5");
const SBNSFVFDeployer = artifacts.require("SBNSFVaultFactoryDeployer");
const SBNSFVaultFactory = artifacts.require("SBNSFVaultFactory");
//DBSFVaultFactory
const DBSFVaultFactoryDelegate1 = artifacts.require("DBSFVaultFactoryDelegate1");
const DBSFVaultFactoryDelegate2 = artifacts.require("DBSFVaultFactoryDelegate2");
const DBSFVaultFactoryDelegate3 = artifacts.require("DBSFVaultFactoryDelegate3");
const DBSFVaultFactoryDelegate4 = artifacts.require("DBSFVaultFactoryDelegate4");
const DBSFVaultFactoryDelegate5 = artifacts.require("DBSFVaultFactoryDelegate5");
const DBSFVFDeployer = artifacts.require("DBSFVaultFactoryDeployer");
const DBSFVaultFactory = artifacts.require("DBSFVaultFactory");

const OrderbookDelegate1 = artifacts.require("OrderbookDelegate1");
const OrderbookDelegate2 = artifacts.require("OrderbookDelegate2");
const OrderbookDelegate3 = artifacts.require("OrderbookDelegate3");
const OrderbookDeployer = artifacts.require("OrderbookDeployer");
const OrderbookExchange = artifacts.require("OrderbookExchange");
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const QuickDepositorDeployer = artifacts.require('QuickDepositorDeployer');
const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
const InfoOracle = artifacts.require("InfoOracle");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");

const UniswapV2FactoryAddress = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";

const kovanAEthAddress = "0xD483B49F2d55D2c53D32bE6efF735cB001880F79";

const nullAddress = "0x0000000000000000000000000000000000000000";

const WETH = nullAddress;

const BN = web3.utils.BN;

const _10To18 = (new BN(10)).pow(new BN(18));

module.exports = async function (callback) {
	try {


	accounts = await web3.eth.getAccounts();
	const treasuryAddress = accounts[0];
	dummyATokenInstance = await dummyAToken.new("aETH");
	dummyATokenInstance = await dummyAToken.new("aUSDC");
	zcbYtDeployerInstance = await zcbYtDeployer.new();

	infoOracle = await InfoOracle.new("0", treasuryAddress, true);

	nsfVaultFactoryDelegate1Instance = await NSFVaultFactoryDelegate1.new();
	nsfVaultFactoryDelegate2Instance = await NSFVaultFactoryDelegate2.new();
	nsfVaultFactoryDelegate3Instance = await NSFVaultFactoryDelegate3.new();
	nsfVaultFactoryDelegate4Instance = await NSFVaultFactoryDelegate4.new();
	nsfVaultFactoryDelegate5Instance = await NSFVaultFactoryDelegate5.new();
	nsfvfDeployerInstance = await NSFVFDeployer.new(
		infoOracle.address,
		nsfVaultFactoryDelegate1Instance.address,
		nsfVaultFactoryDelegate2Instance.address,
		nsfVaultFactoryDelegate3Instance.address,
		nsfVaultFactoryDelegate4Instance.address,
		nsfVaultFactoryDelegate5Instance.address
	);
/*
	sbnsfVaultFactoryDelegate1Instance = await SBNSFVaultFactoryDelegate1.new();
	sbnsfVaultFactoryDelegate2Instance = await SBNSFVaultFactoryDelegate2.new();
	sbnsfVaultFactoryDelegate3Instance = await SBNSFVaultFactoryDelegate3.new();
	sbnsfVaultFactoryDelegate4Instance = await SBNSFVaultFactoryDelegate4.new();
	sbnsfVaultFactoryDelegate5Instance = await SBNSFVaultFactoryDelegate5.new();
	sbnsfvfDeployerInstance = await SBNSFVFDeployer.new(
		infoOracle.address,
		sbnsfVaultFactoryDelegate1Instance.address,
		sbnsfVaultFactoryDelegate2Instance.address,
		sbnsfVaultFactoryDelegate3Instance.address,
		sbnsfVaultFactoryDelegate4Instance.address,
		sbnsfVaultFactoryDelegate5Instance.address
	);

	dbsfVaultFactoryDelegate1Instance = await DBSFVaultFactoryDelegate1.new();
	dbsfVaultFactoryDelegate2Instance = await DBSFVaultFactoryDelegate2.new();
	dbsfVaultFactoryDelegate3Instance = await DBSFVaultFactoryDelegate3.new();
	dbsfVaultFactoryDelegate4Instance = await DBSFVaultFactoryDelegate4.new();
	dbsfVaultFactoryDelegate5Instance = await DBSFVaultFactoryDelegate5.new();
	dbsfvfDeployerInstance = await DBSFVFDeployer.new(
		infoOracle.address,
		dbsfVaultFactoryDelegate1Instance.address,
		dbsfVaultFactoryDelegate2Instance.address,
		dbsfVaultFactoryDelegate3Instance.address,
		dbsfVaultFactoryDelegate4Instance.address,
		dbsfVaultFactoryDelegate5Instance.address
	);
*/
	oracleDeployerInstance = await OracleDeployer.new();
	let rec = await oracleDeployerInstance.deploy(WETH);
	oracleContainerInstance = await OracleContainer.at(rec.logs[0].args.addr);
	vhDeployerInstance = await VaultHealthDeployer.new();
	rec = await vhDeployerInstance.deploy(oracleContainerInstance.address);
	vhInstance = await VaultHealth.at(rec.logs[0].args.addr);	
	rec = await nsfvfDeployerInstance.deploy(vhInstance.address);
	nsfvfInstance = await NSFVaultFactory.at(rec.logs[0].args.addr);
	fcpDelegate1Instance = await FCPDelegate1.new();
	fcpDelegate2Instance = await FCPDelegate2.new();
	fcpDelployerInstance = await FixCapitalPoolDeployer.new(fcpDelegate1Instance.address, fcpDelegate2Instance.address);
	quickDepositorDeployerInstance = await QuickDepositorDeployer.new();
	swapRouterDelegateInstance = await SwapRouterDelegate.new();
	swapRouterDeployerInstance = await SwapRouterDeployer.new(swapRouterDelegateInstance.address);
	ngbwDelegate1Instance = await NGBwrapperDelegate1.new();
	ngbwDelegate2Instance = await NGBwrapperDelegate2.new();
	ngbwDelegate3Instance = await NGBwrapperDelegate3.new();
	NGBwrapperDeployerInstance = await NGBwrapperDeployer.new(
		infoOracle.address,
		ngbwDelegate1Instance.address,
		ngbwDelegate2Instance.address,
		ngbwDelegate3Instance.address
	);
	EiInstance = await Ei.new();
	await BigMath.link(EiInstance);
	bigMathInstance = await BigMath.new();
	await ZCBammDeployer.link(bigMathInstance);
	await YTammDeployer.link(bigMathInstance);
//	await deployer.link(BigMath, [ZCBammDeployer, YTammDeployer, YTammDelegate]);
	ZCBammDeployerInstance = await ZCBammDeployer.new();
	YTammDelegateInstance = await YTammDelegate.new();
	YTammDeployerInstance = await YTammDeployer.new(YTammDelegateInstance.address);
	orderbookDelegate1Instance = await OrderbookDelegate1.new();
	orderbookDelegate2Instance = await OrderbookDelegate2.new();
	orderbookDelegate3Instance = await OrderbookDelegate3.new();
	orderbookDeployerInstance = await OrderbookDeployer.new(
		infoOracle.address,
		orderbookDelegate1Instance.address,
		orderbookDelegate2Instance.address,
		orderbookDelegate3Instance.address
	);
	organizerInstance = await organizer.new(
		NGBwrapperDeployerInstance.address,
		zcbYtDeployerInstance.address,
		fcpDelployerInstance.address,
		ZCBammDeployerInstance.address,
		YTammDeployerInstance.address,
		orderbookDeployerInstance.address,
		quickDepositorDeployerInstance.address,
		swapRouterDeployerInstance.address,
		infoOracle.address
	);
	await organizerInstance.DeploySwapRouter();
	rec = await organizerInstance.deployNGBWrapper(dummyATokenInstance.address);
	wAsset = await NGBwrapper.at(rec.receipt.logs[0].args.wrapperAddress);
	let timestamp = (await web3.eth.getBlock('latest')).timestamp + 10*24*60*60;
	rec = await organizerInstance.deployFixCapitalPoolInstance(wAsset.address, timestamp);
	fcpInstance = await FixCapitalPool.at(rec.receipt.logs[0].args.FCPaddress);
	rec = await organizerInstance.deployOrderbook(fcpInstance.address);
	let exchange = await OrderbookExchange.at(rec.receipt.logs[0].args.OrderbookAddress);
	console.log("NGBwrapper:", wAsset.address);
	console.log("FixCapitalPool:", fcpInstance.address);
	console.log("Orderbook Exchange:", exchange.address);
	await dummyATokenInstance.approve(wAsset.address, _10To18);
	await wAsset.depositUnitAmount(accounts[0], _10To18);
	await wAsset.approve(fcpInstance.address, _10To18);
	await fcpInstance.depositWrappedToken(accounts[0], _10To18);
	await fcpInstance.dualApprove(exchange.address, _10To18, _10To18);
	await exchange.deposit(_10To18, 0);
	console.log("First Orderbook Deposit Completed")
	await dummyATokenInstance.mintTo(accounts[1], _10To18, {from: accounts[1]});
	await dummyATokenInstance.approve(wAsset.address, _10To18, {from: accounts[1]});
	await wAsset.depositUnitAmount(accounts[1], _10To18, {from: accounts[1]});
	await wAsset.approve(fcpInstance.address, _10To18, {from: accounts[1]});
	await fcpInstance.depositWrappedToken(accounts[1], _10To18, {from: accounts[1]});
	await fcpInstance.dualApprove(exchange.address, _10To18, _10To18, {from: accounts[1]});
	await exchange.deposit(_10To18, 0, {from: accounts[1]});
	console.log("Second Orderbook Deposit Completed");

	} catch (err) {
		console.error(err);
	}
	callback();
};
