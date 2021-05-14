const NGBwrapper = artifacts.require('NGBwrapper');
const capitalHandler = artifacts.require('FixCapitalPool');
const dummyAToken = artifacts.require('dummyAToken');
const organizer = artifacts.require('organizer');
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const NSFVaultFactoryDelegate1 = artifacts.require("NSFVaultFactoryDelegate1");
const NSFVaultFactoryDelegate2 = artifacts.require("NSFVaultFactoryDelegate2");
const NSFVaultFactory = artifacts.require("NSFVaultFactory");
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
const InfoOracle = artifacts.require("InfoOracle");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");

const UniswapV2FactoryAddress = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";

const kovanAEthAddress = "0xD483B49F2d55D2c53D32bE6efF735cB001880F79";

const nullAddress = "0x0000000000000000000000000000000000000000";


const start2021 = "1609459200";
const start2022 = "1640995200";
const start2026 = "1767225600";

const BN = web3.utils.BN;

const _10to18 = (new BN(10)).pow(new BN(18));

module.exports = async function(deployer) {
	/*
	factory = await UniswapV2Factory.at(UniswapV2FactoryAddress);

	organizerInstance = await deployer.deploy(organizer);

	await organizerInstance.deployATokenWrapper(kovanAEthAddress);
	await organizerInstance.deployFixCapitalPoolInstance(kovanAEthAddress, start2021);
	await organizerInstance.deployFixCapitalPoolInstance(kovanAEthAddress, start2022);
	await organizerInstance.deployFixCapitalPoolInstance(kovanAEthAddress, start2026);

	capitalHandlers = await organizerInstance.allFixCapitalPoolInstances();

	for (let i = 0; i < capitalHandlers.length; i++) {
		await factory.createPair(kovanAEthAddress, capitalHandlers[i]);
	}
	*/
	accounts = await web3.eth.getAccounts();
	dummyATokenInstance = await deployer.deploy(dummyAToken, "aETH");
	dummyATokenInstance = await deployer.deploy(dummyAToken, "aUSDC");
	zcbYtDeployerInstance = await deployer.deploy(zcbYtDeployer);
	nsfVaultFactoryDelegate1Instance = await deployer.deploy(NSFVaultFactoryDelegate1);
	nsfVaultFactoryDelegate2Instance = await deployer.deploy(NSFVaultFactoryDelegate2);
	vaultFactoryInstance = await deployer.deploy(
		NSFVaultFactory,
		nullAddress,
		accounts[0],
		nsfVaultFactoryDelegate1Instance.address,
		nsfVaultFactoryDelegate2Instance.address
	);
	capitalHandlerDeployerInstance = await deployer.deploy(FixCapitalPoolDeployer);
	swapRouterDelegateInstance = await deployer.deploy(SwapRouterDelegate);
	swapRouterDeployerInstance = await deployer.deploy(SwapRouterDeployer, swapRouterDelegateInstance.address);
	infoOracle = await deployer.deploy(InfoOracle, "0", nullAddress);
	EiInstance = await deployer.deploy(Ei);
	await deployer.link(Ei, BigMath);
	bigMathInstance = await deployer.deploy(BigMath);
	await deployer.link(BigMath, [ZCBammDeployer, YTammDeployer, YTammDelegate]);
	ZCBammDeployerInstance = await deployer.deploy(ZCBammDeployer);
	YTammDelegateInstance = await deployer.deploy(YTammDelegate);
	YTammDeployerInstance = await deployer.deploy(YTammDeployer, YTammDelegateInstance.address);
	organizerInstance = await deployer.deploy(
		organizer,
		zcbYtDeployerInstance.address,
		capitalHandlerDeployerInstance.address,
		ZCBammDeployerInstance.address,
		YTammDeployerInstance.address,
		swapRouterDeployerInstance.address,
		infoOracle.address
	);
	await organizerInstance.DeploySwapRouter();
	let rec = await organizerInstance.deployAssetWrapper(dummyATokenInstance.address);
	wAsset = await NGBwrapper.at(rec.receipt.logs[0].args.wrapperAddress);
	await organizerInstance.deployFixCapitalPoolInstance(wAsset.address, start2026);
};
