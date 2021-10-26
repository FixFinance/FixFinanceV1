const NGBwrapper = artifacts.require('NGBwrapper');
//const FCPDelegate1 = artifacts.require('FCPDelegate1');
//const FCPDelegate2 = artifacts.require('FCPDelegate2');
const FixCapitalPool = artifacts.require('FixCapitalPool');
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const dummyAToken = artifacts.require('dummyAToken');
const organizer = artifacts.require('Organizer');
//const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
//const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
//const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
//const NGBwrapperDeployer = artifacts.require('NGBwrapperDeployer');
//const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
//const OracleContainer = artifacts.require('OracleContainer');
//const OracleDeployer = artifacts.require('OracleDeployer');
//const VaultHealth = artifacts.require("VaultHealth");
//const VaultHealthDeployer = artifacts.require("VaultHealthDeployer");
//NSFVaultFactory
/*
const NSFVaultFactoryDelegate1 = artifacts.require("NSFVaultFactoryDelegate1");
const NSFVaultFactoryDelegate2 = artifacts.require("NSFVaultFactoryDelegate2");
const NSFVaultFactoryDelegate3 = artifacts.require("NSFVaultFactoryDelegate3");
const NSFVaultFactoryDelegate4 = artifacts.require("NSFVaultFactoryDelegate4");
const NSFVaultFactoryDelegate5 = artifacts.require("NSFVaultFactoryDelegate5");
*/
const NSFVFDeployer = artifacts.require("NSFVaultFactoryDeployer");
const NSFVaultFactory = artifacts.require("NSFVaultFactory");
/*
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
*/
const OrderbookDeployer = artifacts.require("OrderbookDeployer");
const OrderbookExchange = artifacts.require("OrderbookExchange");
//const ZCBammDeployer = artifacts.require('ZCBammDeployer');
//const YTammDelegate = artifacts.require('YTammDelegate');
//const YTammDeployer = artifacts.require('YTammDeployer');
const QuickDepositorDeployer = artifacts.require('QuickDepositorDeployer');
//const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
//const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');

const InfoOracle = artifacts.require("InfoOracle");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");

const nullAddress = "0x0000000000000000000000000000000000000000";

const WETH = nullAddress;

const BN = web3.utils.BN;

const _10To18 = (new BN(10)).pow(new BN(18));

module.exports = async function(callback) {

	try {

	accounts = await web3.eth.getAccounts();
	console.log(accounts);
	let promises = accounts.map(acct => web3.eth.getBalance(acct))
	let balances = await Promise.all(promises);
	console.log(balances);
	const treasuryAddress = accounts[0];
	console.log(treasuryAddress);

	console.log("sjekk");
	//zcbYtDeployerInstance = await zcbYtDeployer.new();
	//console.log("zcbYTDeployerAddr addr:",zcbYtDeployerInstance.address);
	//let zcbYtDeployerInstance = await zcbYtDeployer.at("0x0Cb8bC475f8e22167FDde1240647e5E9544544e3");
	let zcbYtDeployerAddr = "0x0Cb8bC475f8e22167FDde1240647e5E9544544e3";


	//infoOracle = await InfoOracle.new("0", treasuryAddress, true);
	//console.log("infoOracle", infoOracle.address);
	//let infoOracle = await InfoOracle.at("0xc9E24654f6FF0aA025C1Ea7489B5F0077cb10272");
	let infoOracleAddr = "0xc9E24654f6FF0aA025C1Ea7489B5F0077cb10272";
	let fcpDeployerAddr = "0xE964Af3E1dF03f90E60C1615E68D6c4e406bb5a3";
	let quickDepositorDeployerAddr = "0xaF4500f80b11Ca6AcB2A753291A59D0011834b62";
	let NGBwrapperDeployerAddr = "0xaf77F4e00d2011E27B4b3Ff65d646358d4c3a96B";
	let swapRouterDeployerAddr = "0x67fd7B3A3Fc1af60638F3D3cd8E93c13CBcC4896";
	let zcbAmmDeployerAddr = "0xa68c8181cA760841Eb5058a6bF6356510A7685d9";
	let ytAmmDeployerAddr = "0x6906A4ea051DE2b64DD0Ef9D9160C11d7B4487e3";
	let orderbookDeployerAddr = "0x50534A423082477C62DC319c0A8Ebc0b85c28CC2";
	let organizerAddr = "0xBDaca21d66773716092c0fc7dA22a6d23C0AeF9f";
/*
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
	console.log("nsfVFDelegate1",nsfVaultFactoryDelegate1Instance.address);
	console.log("nsfVFDelegate2",nsfVaultFactoryDelegate2Instance.address);
	console.log("nsfVFDelegate3",nsfVaultFactoryDelegate3Instance.address);
	console.log("nsfVFDelegate4",nsfVaultFactoryDelegate4Instance.address);
	console.log("nsfVFDelegate5",nsfVaultFactoryDelegate5Instance.address);
	console.log("nsfVFDeployer",nsfvfDeployerInstance.address);
/*
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
*//*
	console.log("-------DIS------");
	let nsfvfDeployerInstance = await NSFVFDeployer.at("0x26b78F2eC329BE48A8b006280A14aDD8e15D2E9b");
	//oracleDeployerInstance = await OracleDeployer.new();
	//console.log("OracleDeployer", oracleDeployerInstance.address);
	console.log("-------OKE------");
	let oracleDeployerInstance = await OracleDeployer.at("0xfC2B980b1Ff0f4Fa8fa33108aC857503b353a36A");
	
	console.log("-------WAT------");
	let rec = await oracleDeployerInstance.deploy(WETH);
	console.log("WETH ORACLE ADDR", rec.logs[0].args.addr);
	oracleContainerInstance = await OracleContainer.at(rec.logs[0].args.addr);

	//vhDeployerInstance = await VaultHealthDeployer.new();
	//console.log("VaultHealthDeployer", vhDeployerInstance.address);
	vhDeployerInstance = await VaultHealthDeployer.at("0xc3deCa0bF056612a3bc7c68798b0F2d23E89c568");

	rec = await vhDeployerInstance.deploy(oracleContainerInstance.address);
	console.log("VaultHealth Addr", rec.logs[0].args.addr);
	vhInstance = await VaultHealth.at(rec.logs[0].args.addr);
	rec = await nsfvfDeployerInstance.deploy(vhInstance.address);
	console.log("NSFVF Addr",rec.logs[0].args.addr);
	nsfvfInstance = await NSFVaultFactory.at(rec.logs[0].args.addr);
	fcpDelegate1Instance = await FCPDelegate1.new();
	fcpDelegate2Instance = await FCPDelegate2.new();
	fcpDelployerInstance = await FixCapitalPoolDeployer.new(fcpDelegate1Instance.address, fcpDelegate2Instance.address);
	console.log("FCP Delegate1", fcpDelegate1Instance.address);
	console.log("FCP Delegate2", fcpDelegate2Instance.address);
	console.log("FCP Deployer", fcpDelployerInstance.address);
	quickDepositorDeployerInstance = await QuickDepositorDeployer.new();
	console.log("Quick Depositor Deployer", quickDepositorDeployerInstance.address);
	swapRouterDelegateInstance = await SwapRouterDelegate.new();
	swapRouterDeployerInstance = await SwapRouterDeployer.new(swapRouterDelegateInstance.address);
	console.log("SwapRouterDelegate", swapRouterDelegateInstance.address);
	console.log("SwapRouterDeployer", swapRouterDeployerInstance.address);
*/
/*
	ngbwDelegate1Instance = await NGBwrapperDelegate1.new();
	console.log("NGBW Delegate1", ngbwDelegate1Instance.address);
	ngbwDelegate2Instance = await NGBwrapperDelegate2.new();
	console.log("NGBW Delegate2", ngbwDelegate2Instance.address);
	ngbwDelegate3Instance = await NGBwrapperDelegate3.new();
	console.log("NGBW Delegate3", ngbwDelegate3Instance.address);
	let a = "0xe7a9f73437CBf8C672E957C943C9a98aD775cCeB";
	let b = "0xC312CaEa2BE145e7B3429DCC4b53A2c451730860";
	let c = "0x159a13d849D60E5142F3270e561857dF1F8b8378";

	NGBwrapperDeployerInstance = await NGBwrapperDeployer.new(
		infoOracleAddr,
		ngbwDelegate1Instance.address,
		ngbwDelegate2Instance.address,
		ngbwDelegate3Instance.address
	);
	console.log("NGBwrapperDeployer", NGBwrapperDeployerInstance.address);


	EiInstance = await Ei.new();
	console.log("EI", EiInstance.address);
	await BigMath.link("Ei", EiInstance.address);
	bigMathInstance = await BigMath.new();
	console.log("BigMath",bigMathInstance.address);
	await ZCBammDeployer.link("BigMath", bigMathInstance.address);
	await YTammDeployer.link("BigMath", bigMathInstance.address);
	await YTammDelegate.link("BigMath", bigMathInstance.address);
	ZCBammDeployerInstance = await ZCBammDeployer.new();
	console.log("ZCBammDeployer", ZCBammDeployerInstance.address);
	YTammDelegateInstance = await YTammDelegate.new();
	YTammDeployerInstance = await YTammDeployer.new(YTammDelegateInstance.address);
	console.log("YTammDelegate", YTammDelegateInstance.address);
	console.log("YTammDeployer", YTammDeployerInstance.address);
	orderbookDelegate1Instance = await OrderbookDelegate1.new();
	console.log("Orderbook Delegate 1", orderbookDelegate1Instance.address);
	orderbookDelegate2Instance = await OrderbookDelegate2.new();
	console.log("Orderbook Delegate 2", orderbookDelegate2Instance.address);
	orderbookDelegate3Instance = await OrderbookDelegate3.new();
	console.log("Orderbook Delegate 3", orderbookDelegate3Instance.address);
	orderbookDeployerInstance = await OrderbookDeployer.new(
		infoOracleAddr,
		orderbookDelegate1Instance.address,
		orderbookDelegate2Instance.address,
		orderbookDelegate3Instance.address
	);
	console.log("OrderbookDeployer", orderbookDeployerInstance.address);


	organizerInstance = await organizer.new(
		NGBwrapperDeployerAddr,
		zcbYtDeployerAddr,
		fcpDeployerAddr,
		zcbAmmDeployerAddr,
		ytAmmDeployerAddr,
		orderbookDeployerAddr,
		quickDepositorDeployerAddr,
		swapRouterDeployerAddr,
		infoOracleAddr
	);
	console.log("Organizer", organizerInstance.address);
*/
	let organizerInstance = await organizer.at(organizerAddr);
	console.log('got instance');
	//await organizerInstance.DeploySwapRouter();
	//console.log("SR deployed");

	let dummyATokenInstance = await dummyAToken.at("0xAb76DBde21202E142B2D63afD03Bb4354146E16e");
	console.log("Dummy a token instance found");
	//rec = await organizerInstance.deployNGBWrapper(dummyATokenInstance.address);
	//console.log("NGBWrapper ADDR", rec.receipt.logs[0].args.wrapperAddress);
	//wAsset = await NGBwrapper.at(rec.receipt.logs[0].args.wrapperAddress);
	let wAsset = await NGBwrapper.at("0xdea59E3Fb8C4b139f3970a1c46D8CaAA22F8d98e");
	//let timestamp = (await web3.eth.getBlock('latest')).timestamp + 100*24*60*60;
	//rec = await organizerInstance.deployFixCapitalPoolInstance(wAsset.address, timestamp);
	//console.log("FCP ADDR", rec.receipt.logs[0].args.FCPaddress);
	//fcpInstance = await FixCapitalPool.at(rec.receipt.logs[0].args.FCPaddress);
	let fcpInstance = await FixCapitalPool.at("0xA9F5eFA4010740a0AA930c2E5b0C0F0209e004C6");
	//rec = await organizerInstance.deployOrderbook(fcpInstance.address);
	//console.log("Orderbook ADDR", rec.receipt.logs[0].args.OrderbookAddress);
	let exchange = await OrderbookExchange.at("0xAdb6f41a2f0865ae97d8e87059F1cCE60B5bB003");
	//let exchange = await OrderbookExchange.at(rec.receipt.logs[0].args.OrderbookAddress);
	console.log("All instances fetched");
/*
	await dummyATokenInstance.approve(wAsset.address, _10To18);
	console.log('halt 1');
	await wAsset.depositUnitAmount(accounts[0], _10To18);
	console.log('halt 2');
	await wAsset.approve(fcpInstance.address, _10To18);
	console.log('halt 3');
	await fcpInstance.depositWrappedToken(accounts[0], _10To18);
	console.log('halt 4');
*/
	await fcpInstance.dualApprove(exchange.address, _10To18, _10To18);
	console.log('halt 5');
	await exchange.deposit(_10To18, 0);
	console.log("First Orderbook Deposit Completed")
	await dummyATokenInstance.mintTo(accounts[1], _10To18, {from: accounts[1]});
	console.log('halt 6');
	await dummyATokenInstance.approve(wAsset.address, _10To18, {from: accounts[1]});
	console.log('halt 7');
	await wAsset.depositUnitAmount(accounts[1], _10To18, {from: accounts[1]});
	console.log('halt 8');
	await wAsset.approve(fcpInstance.address, _10To18, {from: accounts[1]});
	console.log('halt 9');
	await fcpInstance.depositWrappedToken(accounts[1], _10To18, {from: accounts[1]});
	console.log('halt 10');
	await fcpInstance.dualApprove(exchange.address, _10To18, _10To18, {from: accounts[1]});
	console.log('halt 11');
	await exchange.deposit(_10To18, 0, {from: accounts[1]});
	console.log("Second Orderbook Deposit Completed");
//*/
	} catch (err) {console.error(err);}

	callback();
};
