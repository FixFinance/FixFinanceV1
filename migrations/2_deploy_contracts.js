const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
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

module.exports = async function(deployer) {
	accounts = await web3.eth.getAccounts();
	const treasuryAddress = accounts[0];
	dummyATokenInstance = await deployer.deploy(dummyAToken, "aETH");
	dummyATokenInstance = await deployer.deploy(dummyAToken, "aUSDC");
	zcbYtDeployerInstance = await deployer.deploy(zcbYtDeployer);

	infoOracle = await deployer.deploy(InfoOracle, "0", treasuryAddress, true);

	nsfVaultFactoryDelegate1Instance = await deployer.deploy(NSFVaultFactoryDelegate1);
	nsfVaultFactoryDelegate2Instance = await deployer.deploy(NSFVaultFactoryDelegate2);
	nsfVaultFactoryDelegate3Instance = await deployer.deploy(NSFVaultFactoryDelegate3);
	nsfVaultFactoryDelegate4Instance = await deployer.deploy(NSFVaultFactoryDelegate4);
	nsfVaultFactoryDelegate5Instance = await deployer.deploy(NSFVaultFactoryDelegate5);
	nsfvfDeployerInstance = await deployer.deploy(
		NSFVFDeployer,
		infoOracle.address,
		nsfVaultFactoryDelegate1Instance.address,
		nsfVaultFactoryDelegate2Instance.address,
		nsfVaultFactoryDelegate3Instance.address,
		nsfVaultFactoryDelegate4Instance.address,
		nsfVaultFactoryDelegate5Instance.address
	);

	sbnsfVaultFactoryDelegate1Instance = await deployer.deploy(SBNSFVaultFactoryDelegate1);
	sbnsfVaultFactoryDelegate2Instance = await deployer.deploy(SBNSFVaultFactoryDelegate2);
	sbnsfVaultFactoryDelegate3Instance = await deployer.deploy(SBNSFVaultFactoryDelegate3);
	sbnsfVaultFactoryDelegate4Instance = await deployer.deploy(SBNSFVaultFactoryDelegate4);
	sbnsfVaultFactoryDelegate5Instance = await deployer.deploy(SBNSFVaultFactoryDelegate5);
	sbnsfvfDeployerInstance = await deployer.deploy(
		SBNSFVFDeployer,
		infoOracle.address,
		sbnsfVaultFactoryDelegate1Instance.address,
		sbnsfVaultFactoryDelegate2Instance.address,
		sbnsfVaultFactoryDelegate3Instance.address,
		sbnsfVaultFactoryDelegate4Instance.address,
		sbnsfVaultFactoryDelegate5Instance.address
	);

	dbsfVaultFactoryDelegate1Instance = await deployer.deploy(DBSFVaultFactoryDelegate1);
	dbsfVaultFactoryDelegate2Instance = await deployer.deploy(DBSFVaultFactoryDelegate2);
	dbsfVaultFactoryDelegate3Instance = await deployer.deploy(DBSFVaultFactoryDelegate3);
	dbsfVaultFactoryDelegate4Instance = await deployer.deploy(DBSFVaultFactoryDelegate4);
	dbsfVaultFactoryDelegate5Instance = await deployer.deploy(DBSFVaultFactoryDelegate5);
	dbsfvfDeployerInstance = await deployer.deploy(
		DBSFVFDeployer,
		infoOracle.address,
		dbsfVaultFactoryDelegate1Instance.address,
		dbsfVaultFactoryDelegate2Instance.address,
		dbsfVaultFactoryDelegate3Instance.address,
		dbsfVaultFactoryDelegate4Instance.address,
		dbsfVaultFactoryDelegate5Instance.address
	);

	oracleDeployerInstance = await deployer.deploy(OracleDeployer);
	let rec = await oracleDeployerInstance.deploy(WETH);
	oracleContainerInstance = await OracleContainer.at(rec.logs[0].args.addr);
	vhDeployerInstance = await deployer.deploy(VaultHealthDeployer);
	rec = await vhDeployerInstance.deploy(oracleContainerInstance.address);
	vhInstance = await VaultHealth.at(rec.logs[0].args.addr);	
	rec = await nsfvfDeployerInstance.deploy(vhInstance.address);
	nsfvfInstance = await NSFVaultFactory.at(rec.logs[0].args.addr);
	fcpDelegate1Instance = await deployer.deploy(FCPDelegate1);
	fcpDelployerInstance = await deployer.deploy(FixCapitalPoolDeployer, fcpDelegate1Instance.address);
	quickDepositorDeployerInstance = await deployer.deploy(QuickDepositorDeployer);
	swapRouterDelegateInstance = await deployer.deploy(SwapRouterDelegate);
	swapRouterDeployerInstance = await deployer.deploy(SwapRouterDeployer, swapRouterDelegateInstance.address);
	ngbwDelegate1Instance = await deployer.deploy(NGBwrapperDelegate1);
	ngbwDelegate2Instance = await deployer.deploy(NGBwrapperDelegate2);
	ngbwDelegate3Instance = await deployer.deploy(NGBwrapperDelegate3);
	NGBwrapperDeployerInstance = await deployer.deploy(
		NGBwrapperDeployer,
		infoOracle.address,
		ngbwDelegate1Instance.address,
		ngbwDelegate2Instance.address,
		ngbwDelegate3Instance.address
	);
	EiInstance = await deployer.deploy(Ei);
	await deployer.link(Ei, BigMath);
	bigMathInstance = await deployer.deploy(BigMath);
	await deployer.link(BigMath, [ZCBammDeployer, YTammDeployer, YTammDelegate]);
	ZCBammDeployerInstance = await deployer.deploy(ZCBammDeployer);
	YTammDelegateInstance = await deployer.deploy(YTammDelegate);
	YTammDeployerInstance = await deployer.deploy(YTammDeployer, YTammDelegateInstance.address);
	orderbookDelegate1Instance = await deployer.deploy(OrderbookDelegate1);
	orderbookDelegate2Instance = await deployer.deploy(OrderbookDelegate2);
	orderbookDelegate3Instance = await deployer.deploy(OrderbookDelegate3);
	orderbookDeployerInstance = await deployer.deploy(
		OrderbookDeployer,
		infoOracle.address,
		orderbookDelegate1Instance.address,
		orderbookDelegate2Instance.address,
		orderbookDelegate3Instance.address
	);
	organizerInstance = await deployer.deploy(
		organizer,
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
	console.log("Orderbook Deposit Complete");
};
