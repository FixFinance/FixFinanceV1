const aToken = artifacts.require("dummyAToken");
const aaveWrapper = artifacts.require("aaveWrapper");
const BigMath = artifacts.require("BigMath");
const capitalHandler = artifacts.require("capitalHandler");
const yieldToken = artifacts.require("yieldToken");
const yieldTokenDeployer = artifacts.require("yieldTokenDeployer");
const ZCBamm = artifacts.require("ZCBamm");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";

contract('ZCBamm', async function(accounts){
	it('before each', async () => {
		aTokenInstance = await aToken.new();
		aaveWrapperInstance = await aaveWrapper.new(aTokenInstance.address);
		BigMathInstance = await BigMath.new();
		yieldTokenDeployerInstance = await yieldTokenDeployer.new();
		//maturity is 11 days out
		maturity = (await web3.eth.getBlock('latest')).timestamp + 11*24*60*60;
		capitalHandlerInstance = await capitalHandler.new(aaveWrapperInstance.address, maturity, yieldTokenDeployerInstance.address, nullAddress);
		yieldTokenInstance = await yieldToken.at(await capitalHandlerInstance.yieldTokenAddress());
		await ZCBamm.link("BigMath", BigMathInstance.address);
		amm = await ZCBamm.new(capitalHandlerInstance.address);

		//mint funds to accounts[0]
		balance = (new BN("10")).pow(new BN("18"));
		await aTokenInstance.approve(aaveWrapperInstance.address, balance);
		await aaveWrapperInstance.firstDeposit(accounts[0], balance);
		await aaveWrapperInstance.approve(capitalHandlerInstance.address, balance);
		await capitalHandlerInstance.depositWrappedToken(accounts[0], balance);
		await capitalHandlerInstance.approve(amm.address, balance);
		await yieldTokenInstance.approve(amm.address, balance);
	});

/*
	it('make first deposit in amm', async () => {

	});
*/

});
