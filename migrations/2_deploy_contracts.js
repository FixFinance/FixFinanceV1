const aaveWrapper = artifacts.require('AaveWrapper');
const capitalHandler = artifacts.require('CapitalHandler');
const dummyAToken = artifacts.require('dummyAToken');
const organizer = artifacts.require('organizer');
const yieldTokenDeployer = artifacts.require('YieldTokenDeployer');
const BondMinterDelegate = artifacts.require("BondMinterDelegate");
const BondMinter = artifacts.require("BondMinter");
const CapitalHandlerDeployer = artifacts.require('CapitalHandlerDeployer');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
const SwapRouterDeployer = artifacts.require('SwapRouterDeployer');
const AmmInfoOracle = artifacts.require("AmmInfoOracle");
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
	await organizerInstance.deployCapitalHandlerInstance(kovanAEthAddress, start2021);
	await organizerInstance.deployCapitalHandlerInstance(kovanAEthAddress, start2022);
	await organizerInstance.deployCapitalHandlerInstance(kovanAEthAddress, start2026);

	capitalHandlers = await organizerInstance.allCapitalHandlerInstances();

	for (let i = 0; i < capitalHandlers.length; i++) {
		await factory.createPair(kovanAEthAddress, capitalHandlers[i]);
	}
	*/
	accounts = await web3.eth.getAccounts();
	dummyATokenInstance = await deployer.deploy(dummyAToken, "aETH");
	dummyATokenInstance = await deployer.deploy(dummyAToken, "aUSDC");
	yieldTokenDeployerInstance = await deployer.deploy(yieldTokenDeployer);
	bondMinterDelegateInstance = await deployer.deploy(BondMinterDelegate);
	bondMinterInstance = await deployer.deploy(BondMinter, nullAddress, bondMinterDelegateInstance.address);
	capitalHandlerDeployerInstance = await deployer.deploy(CapitalHandlerDeployer);
	swapRouterDelegateInstance = await deployer.deploy(SwapRouterDelegate);
	swapRouterDeployerInstance = await deployer.deploy(SwapRouterDeployer, swapRouterDelegateInstance.address);
	ammInfoOracle = await deployer.deploy(AmmInfoOracle, "0", nullAddress);
	EiInstance = await deployer.deploy(Ei);
	await deployer.link(Ei, BigMath);
	bigMathInstance = await deployer.deploy(BigMath);
	await deployer.link(BigMath, [ZCBammDeployer, YTammDeployer, YTammDelegate]);
	ZCBammDeployerInstance = await deployer.deploy(ZCBammDeployer);
	YTammDelegateInstance = await deployer.deploy(YTammDelegate);
	YTammDeployerInstance = await deployer.deploy(YTammDeployer, YTammDelegateInstance.address);
	organizerInstance = await deployer.deploy(
		organizer,
		yieldTokenDeployerInstance.address,
		capitalHandlerDeployerInstance.address,
		ZCBammDeployerInstance.address,
		YTammDeployerInstance.address,
		swapRouterDeployerInstance.address,
		ammInfoOracle.address,
		accounts[0]
	);
	await organizerInstance.DeploySwapRouter();
	let rec = await organizerInstance.deployAssetWrapper(dummyATokenInstance.address);
	wAsset = await aaveWrapper.at(rec.receipt.logs[0].args.wrapperAddress);
	await organizerInstance.deployCapitalHandlerInstance(wAsset.address, start2026);
};
