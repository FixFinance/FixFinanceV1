const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const fixCapitalPool = artifacts.require('FixCapitalPool');
const IYieldToken = artifacts.require("IYieldToken");
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapperDeployer = artifacts.require('NGBwrapperDeployer');
const OrderbookDelegate1 = artifacts.require("OrderbookDelegate1");
const OrderbookDelegate2 = artifacts.require("OrderbookDelegate2");
const OrderbookDelegate3 = artifacts.require("OrderbookDelegate3");
const OrderbookDeployer = artifacts.require("OrderbookDeployer");
const OrderbookExchange = artifacts.require("OrderbookExchange");
const QuickDepositorDeployer = artifacts.require('QuickDepositorDeployer');
const organizer = artifacts.require('Organizer');
const DBSFVaultFactoryDelegate1 = artifacts.require("DBSFVaultFactoryDelegate1");
const DBSFVaultFactoryDelegate2 = artifacts.require("DBSFVaultFactoryDelegate2");
const DBSFVaultFactoryDelegate3 = artifacts.require("DBSFVaultFactoryDelegate3");
const DBSFVaultFactoryDelegate4 = artifacts.require("DBSFVaultFactoryDelegate4");
const DBSFVaultFactoryDelegate5 = artifacts.require("DBSFVaultFactoryDelegate5");
const DBSFVaultFactory = artifacts.require('DBSFVaultFactory');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const InfoOracle = artifacts.require("InfoOracle");

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const _10 = new BN(10);
const _10To18 = _10.pow(new BN('18'));
const NO_STABILITY_FEE = (new BN(2)).pow(new BN(32));

const _8days = 8*24*60*60;

const secondsPerYear = 31556926;
const AcceptableMarginOfError = Math.pow(10, -8);

const TOTAL_BASIS_POINTS = 10000;

function AmountError(actual, expected) {
	actual = parseInt(actual);
	expected = parseInt(expected);
	if (actual === expected) {
		return 0;
	}
	else if (actual === 0 || expected === 0) {
		return 1.0;
	}
	return Math.abs(actual-expected)/expected;
}

function basisPointsToABDKString(bips) {
	return (new BN(bips)).mul((new BN(2)).pow(new BN(64))).div(_10.pow(new BN(4))).toString();
}

const ABDK_1 = basisPointsToABDKString(TOTAL_BASIS_POINTS);

const NON_CHANGE_MULTIPLIERS = [TOTAL_BASIS_POINTS, ABDK_1, ABDK_1];

const rebate_bips = 120;

const AUCTION_COOLDOWN = 10 * 60;

contract('DBSFVaultFactory', async function(accounts) {
	/*
		for simplicity of testing in this contract we assume that 1 unit of each asset is equal in vaulue to 1 unit of any other asset
	*/
	it('before each', async () => {
		//borrow asset 0
		asset0 = await dummyAToken.new("aCOIN");
		//supply asset 1
		asset1 = await dummyAToken.new("aTOKEN");
		rewardsAsset = await dummyAToken.new("RWD");
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
		treasuryAccount = accounts[5];
		infoOracleInstance = await InfoOracle.new("0", treasuryAccount, true);
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
			nullAddress,
			infoOracleInstance.address
		);
		dbsfVaultFactoryDelegate1Instance = await DBSFVaultFactoryDelegate1.new();
		dbsfVaultFactoryDelegate2Instance = await DBSFVaultFactoryDelegate2.new();
		dbsfVaultFactoryDelegate3Instance = await DBSFVaultFactoryDelegate3.new();
		dbsfVaultFactoryDelegate4Instance = await DBSFVaultFactoryDelegate4.new();
		dbsfVaultFactoryDelegate5Instance = await DBSFVaultFactoryDelegate5.new();
		vaultFactoryInstance = await DBSFVaultFactory.new(
			vaultHealthInstance.address,
			infoOracleInstance.address,
			dbsfVaultFactoryDelegate1Instance.address,
			dbsfVaultFactoryDelegate2Instance.address,
			dbsfVaultFactoryDelegate3Instance.address,
			dbsfVaultFactoryDelegate4Instance.address,
			dbsfVaultFactoryDelegate5Instance.address,
		);

		maturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

		let reca = await organizerInstance.deployNGBWrapper(asset0.address);
		let recb = await organizerInstance.deployNGBWrapper(asset1.address);

		wAsset0 = await NGBwrapper.at(reca.receipt.logs[0].args.wrapperAddress);
		wAsset1 = await NGBwrapper.at(recb.receipt.logs[0].args.wrapperAddress);

		let rec0 = await organizerInstance.deployFixCapitalPoolInstance(wAsset0.address, maturity);
		let rec1 = await organizerInstance.deployFixCapitalPoolInstance(wAsset1.address, maturity);

		await asset0.approve(wAsset0.address, _10To18.toString());
		await asset1.approve(wAsset1.address, _10To18.toString());

		await wAsset0.depositUnitAmount(accounts[0], _10To18.toString());
		await wAsset1.depositUnitAmount(accounts[0], _10To18.toString());

		fcp0 = await fixCapitalPool.at(rec0.receipt.logs[0].args.FCPaddress);
		fcp1 = await fixCapitalPool.at(rec1.receipt.logs[0].args.FCPaddress);

		zcbAsset0 = await IERC20.at(await fcp0.zeroCouponBondAddress());
		zcbAsset1 = await IERC20.at(await fcp1.zeroCouponBondAddress());

		ytAsset0 = await IYieldToken.at(await fcp0.yieldTokenAddress());
		ytAsset1 = await IYieldToken.at(await fcp1.yieldTokenAddress());

		await fcp0.setVaultFactoryAddress(vaultFactoryInstance.address);
		await fcp1.setVaultFactoryAddress(vaultFactoryInstance.address);

		await vaultFactoryInstance.registerAsDistributionAccount(wAsset1.address);
		await infoOracleInstance.whitelistWrapper(vaultFactoryInstance.address, wAsset1.address);
		await vaultFactoryInstance.setLiquidationRebate(rebate_bips);

		stabilityFee0 = 1.05;
		stabilityFee0BN = (new BN(21)).mul(NO_STABILITY_FEE).div(new BN(20));
		await infoOracleInstance.setStabilityFeeAPR(vaultFactoryInstance.address, wAsset0.address, stabilityFee0BN);

		let _10To19 = _10To18.mul(new BN(10));

		//mint assets to account 0
		await asset1.mintTo(accounts[0], _10To19);
		await asset1.approve(wAsset1.address, _10To19);
		await wAsset1.depositUnitAmount(accounts[0], _10To19);
		await wAsset1.approve(vaultFactoryInstance.address, _10To19);
		await wAsset1.approve(fcp1.address, _10To19);
		await fcp1.depositWrappedToken(accounts[0], _10To19);
		await zcbAsset1.approve(vaultFactoryInstance.address, _10To19);

		await asset0.mintTo(accounts[0], _10To19);
		await asset0.approve(wAsset0.address, _10To19);
		await wAsset0.depositUnitAmount(accounts[0], _10To19);
		await wAsset0.approve(fcp0.address, _10To19);
		await fcp0.depositWrappedToken(accounts[0], _10To19);
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To19);

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To19);
		await asset0.approve(wAsset0.address, _10To19, {from: accounts[1]});
		await wAsset0.depositUnitAmount(accounts[1], _10To19, {from: accounts[1]});
		await wAsset0.approve(fcp0.address, _10To19, {from: accounts[1]});
		await fcp0.depositWrappedToken(accounts[1], _10To19, {from: accounts[1]});
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To19, {from: accounts[1]});

		await wAsset1.addRewardAsset(rewardsAsset.address);
	});

	function rand(min, max) {
		return Math.floor(Math.random() * (max - min)) + min + 1;
	}

	async function addRewards() {
		let amtToMint = _10To18.div(new BN(rand(1, 10000)));
		let currentBal = await rewardsAsset.balanceOf(wAsset1.address);
		let newBal = currentBal.add(amtToMint);
		await rewardsAsset.mintTo(wAsset1.address, newBal);
	}

	it('assign ratios', async () => {
		//assign ratios in vault

		// asset0 Borrowed * ratio = asset1 Supplied
		// 1.4 * 10**18
		upperRatio = "14" + _10To18.toString().substring(2);
		await vaultHealthInstance.setUpper(asset1.address, zcbAsset0.address, upperRatio);

		// 1.1 * 10**18
		lowerRatio = "11" + _10To18.toString().substring(2);
		await vaultHealthInstance.setLower(asset1.address, zcbAsset0.address, lowerRatio);
	});

	it('cannot open vault without whitelisting supplied asset', async () => {
		let caught = false;
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio)).toString();
		await vaultHealthInstance.setToReturn(true);
		maxShortInterest0 = _10To18.mul(_10To18).toString();
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);
		try {
			await vaultFactoryInstance.openVault(zcbAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		await fcp1.withdrawAll(accounts[0], false);
		if (!caught) assert.fail('only whitelisted assets may be supplied');
	});

	it('opens vault', async () => {
		await addRewards();
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio)).toString();
		let caught = false;
		maxShortInterest0 = "0";
		let prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);
		//we are usign a dummy vault health contract, we need to set the value which it will return on vaultWithstandsChange() call
		await vaultHealthInstance.setToReturn(true);
		try {
			await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('borrowing must be limited by the short interest cap');

		//set max short interest super high so that we will not need to worry about it later in our tests
		maxShortInterest0 = _10To18.mul(_10To18).toString();
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);

		await vaultHealthInstance.setToReturn(false);
		caught = false;
		try {
			await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('open vault fails when vaultWithstandsChange() returns false');

		await vaultHealthInstance.setToReturn(true);
		caught = false;
		try {
			await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS-1, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful priceChange parameter must be >= TOTAL_BASIS_POINTS');

		caught = false;
		try {
			const sub1ABDK = (new BN(ABDK_1)).sub(new BN(1));
			await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, sub1ABDK, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful suppliedRateChange parameter must be >= ABDK_1');

		caught = false;
		try {
			const over1ABDK = (new BN(ABDK_1)).add(new BN(1));
			await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, over1ABDK);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful borrowedRateChange parameter must be <= ABDK_1');

		amountBorrowed = (new BN(amountBorrowed)).sub(new BN('1')).toString();
		let prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);

		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		assert.equal((await zcbAsset0.balanceOf(accounts[0])).sub(prevBalanceZCB0).toString(), amountBorrowed, "correct amount of zcb credited to vault owner");
		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.sub(_10To18), "correct amount of wAsset1 supplied");


		vaults = await vaultFactoryInstance.allVaults(accounts[0]);
		assert.equal(vaults.length, 1, "correct amount of vaults");
		vault = vaults[0];
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);

		assert.equal(vault.assetSupplied, wAsset1.address, "correct address for assetSupplied in vault");
		assert.equal(vault.assetBorrowed, zcbAsset0.address, "correct address for assetBorrowed in vault");
		assert.equal(vault.amountSupplied.toString(), _10To18.toString(), "correct vaule of amountSupplied in vault");
		assert.equal(vault.amountBorrowed.toString(), amountBorrowed, "correct vaule of amountBorrowed in vault");
		assert.equal(subAcctPosW1A0.yield.toString(), vault.amountSupplied.toString(), "correct yield value in sub account position");
		assert.equal(subAcctPosW1A0.bond.toString(), "0", "correct bond value in sub account position");
	});

	it('deposits into vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		prevSupplied = new BN(vault.amountSupplied);

		let toSupply = _10To18;
		let expectedNewSupplied = prevSupplied.add(toSupply);
		let expectedNewBalance = prevBalanceW1.sub(toSupply);

		await vaultFactoryInstance.adjustVault(
			accounts[0],
			0,
			vault.assetSupplied,
			vault.assetBorrowed,
			expectedNewSupplied,
			vault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		vault = await vaultFactoryInstance.vaults(accounts[0], 0);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYield = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), expectedNewBalance.toString(), "correct amount of wAsset1 supplied");
		assert.equal(vault.amountSupplied.toString(), expectedNewSupplied.toString(), "correct increase in supplied asset in vault");

		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.sub(_10To18).toString(), "correct amount of wAsset1 supplied");
		assert.equal(vault.amountSupplied.sub(_10To18).toString(), prevSupplied.toString(), "correct increase in supplied asset in vault");

		assert.equal(changeYield.toString(), toSupply.toString(), "correct yield value in sub account position");
		assert.equal(subAcctPosW1A0.bond.toString(), "0", "correct bond value in sub account position");
	});

	it('removes from vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let toRemove = _10To18;
		let prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		let prevVault = vault;

		let newSupplied = prevVault.amountSupplied.sub(toRemove);

		await vaultHealthInstance.setToReturn(false);
		let caught = false;
		try {
			await vaultFactoryInstance.adjustVault(
				accounts[0],
				0,
				vault.assetSupplied,
				vault.assetBorrowed,
				newSupplied,
				vault.amountBorrowed,
				NON_CHANGE_MULTIPLIERS,
				[],
				accounts[0]
			);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("call to remove() should fail when vaultWithstandsChange() returns false");

		await vaultHealthInstance.setToReturn(true);

		await vaultFactoryInstance.adjustVault(
			accounts[0],
			0,
			vault.assetSupplied,
			vault.assetBorrowed,
			newSupplied,
			vault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		vault = await vaultFactoryInstance.vaults(accounts[0], 0);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYield = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		currentSupplied = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountSupplied);
		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.add(toRemove).toString(), "correct amount of wAsset1 supplied");
		assert.equal(prevVault.amountSupplied.sub(vault.amountSupplied).toString(), toRemove.toString(), "correct increase in supplied asset in vault");

		assert.equal(changeYield.toString(), toRemove.neg().toString(), "correct yield value in sub account position");
		assert.equal(subAcctPosW1A0.bond.toString(), "0", "correct bond value in sub account position");
	});


	it('repays vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		toRepay = _10To18.div(new BN('2'));
		let prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let newDebt = vault.amountBorrowed.sub(toRepay);
		let prevVault = vault;

		let rec = await vaultFactoryInstance.adjustVault(
			accounts[0],
			0,
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			newDebt,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		vault = await vaultFactoryInstance.vaults(accounts[0], 0);
		let currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let secondsOpen = timestamp - prevVault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedRepayment = multiplier * parseInt(toRepay.toString());
		let expectedDebt = multiplier * parseInt(newDebt.toString());

		let actualRepayment = parseInt(prevBalanceZCB.sub(currentBalanceZCB).toString());
		let actualDebt = parseInt(vault.amountBorrowed.toString());
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYield = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.isBelow(AmountError(actualRepayment, expectedRepayment), AcceptableMarginOfError, "repayment amount within error range");
		assert.isBelow(AmountError(actualDebt, expectedDebt), AcceptableMarginOfError, "vault.amountBorrowed is within error range");

		assert.equal(changeYield.toString(), "0");
		assert.equal(subAcctPosW1A0.bond.toString(), "0");
	});

	it('borrows from vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		toBorrow = toRepay;
		let prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let prevBorrowed = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountBorrowed);
		let newDebt = vault.amountBorrowed.add(toBorrow);
		let prevVault = vault;

		let rec = await vaultFactoryInstance.adjustVault(
			accounts[0],
			0,
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			newDebt,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		vault = await vaultFactoryInstance.vaults(accounts[0], 0);
		let currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let secondsOpen = timestamp - prevVault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedBorrow = multiplier * parseInt(toBorrow.toString());
		let expectedDebt = multiplier * parseInt(newDebt.toString());
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYield = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		let actualBorrow = parseInt(currentBalanceZCB.sub(prevBalanceZCB).toString())
		let actualDebt = parseInt(vault.amountBorrowed.toString());

		assert.isBelow(AmountError(expectedBorrow, actualBorrow), AcceptableMarginOfError, "borrowed amount within error range");
		assert.isBelow(AmountError(expectedDebt, actualDebt), AcceptableMarginOfError, "vault.amountBorrowed is within error range");

		assert.equal(changeYield.toString(), "0");
		assert.equal(subAcctPosW1A0.bond.toString(), "0");
	});

	it('transfer standard vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let prevVault = vault;

		await vaultFactoryInstance.transferVault(0, accounts[2], false);

		let newVaultAcct0Ind0 = await vaultFactoryInstance.vaults(accounts[0], 0);
		let newVaultAcct2 = await vaultFactoryInstance.vaults(accounts[2], 0);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		subAcctPosW1A2 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[2], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(newVaultAcct0Ind0.assetSupplied, nullAddress);
		assert.equal(newVaultAcct0Ind0.assetBorrowed, nullAddress);
		assert.equal(newVaultAcct0Ind0.amountSupplied.toString(), "0");
		assert.equal(newVaultAcct0Ind0.amountBorrowed.toString(), "0");

		assert.equal(newVaultAcct2.assetSupplied, prevVault.assetSupplied);
		assert.equal(newVaultAcct2.assetBorrowed, prevVault.assetBorrowed);
		assert.equal(newVaultAcct2.amountSupplied.toString(), prevVault.amountSupplied.toString());
		assert.equal(newVaultAcct2.amountBorrowed.toString(), prevVault.amountBorrowed.toString());

		assert.equal(changeYieldA0.toString(), prevVault.amountSupplied.neg().toString());
		assert.equal(subAcctPosW1A0.bond.toString(), "0");
		assert.equal(subAcctPosW1A2.yield.toString(), prevVault.amountSupplied.toString());
		assert.equal(subAcctPosW1A2.bond.toString(), "0");

		await vaultFactoryInstance.transferVault(0, accounts[0], false, {from: accounts[2]});

		let newVaultAcct0Ind1 = await vaultFactoryInstance.vaults(accounts[0], 1);
		newVaultAcct2 = await vaultFactoryInstance.vaults(accounts[2], 0);
		prevSubAcctPosW1A0 = subAcctPosW1A0;
		let prevSubAcctPosW1A2 = subAcctPosW1A2;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		subAcctPosW1A2 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[2], nullAddress);
		changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);
		let changeYieldA2 = subAcctPosW1A2.yield.sub(prevSubAcctPosW1A2.yield);

		assert.equal(newVaultAcct0Ind0.assetSupplied, nullAddress);
		assert.equal(newVaultAcct0Ind0.assetBorrowed, nullAddress);
		assert.equal(newVaultAcct0Ind0.amountSupplied.toString(), "0");
		assert.equal(newVaultAcct0Ind0.amountBorrowed.toString(), "0");

		assert.equal(newVaultAcct2.assetSupplied, nullAddress);
		assert.equal(newVaultAcct2.assetBorrowed, nullAddress);
		assert.equal(newVaultAcct2.amountSupplied.toString(), "0");
		assert.equal(newVaultAcct2.amountBorrowed.toString(), "0");

		assert.equal(newVaultAcct0Ind1.assetSupplied, prevVault.assetSupplied);
		assert.equal(newVaultAcct0Ind1.assetBorrowed, prevVault.assetBorrowed);
		assert.equal(newVaultAcct0Ind1.amountSupplied.toString(), prevVault.amountSupplied.toString());
		assert.equal(newVaultAcct0Ind1.amountBorrowed.toString(), prevVault.amountBorrowed.toString());

		assert.equal(changeYieldA0.toString(), prevVault.amountSupplied.toString());
		assert.equal(subAcctPosW1A0.bond.toString(), "0");
		assert.equal(changeYieldA2.toString(), prevVault.amountSupplied.neg().toString());
		assert.equal(subAcctPosW1A2.bond.toString(), "0");
	});

	it('close vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let prevVault = vault;
		let prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);

		let rec = await vaultFactoryInstance.closeVault(1, accounts[0]);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let secondsOpen = timestamp - prevVault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedRepayment = multiplier * parseInt(prevVault.amountBorrowed.toString());

		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		let currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let currentBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		vault = await vaultFactoryInstance.vaults(accounts[0], 1);

		let decZCBBalance = prevBalanceZCB.sub(currentBalanceZCB);
		let incW1Balance = currentBalanceW1.sub(prevBalanceW1);

		let actualRepayment = parseInt(decZCBBalance);

		assert.equal(vault.assetSupplied, nullAddress, "correct value of vault.assetSupplied");
		assert.equal(vault.assetBorrowed, nullAddress, "correct value of vault.assetBorrowed");
		assert.equal(vault.amountSupplied.toString(), "0", "correct value of vault.amountSupplied");
		assert.equal(vault.amountBorrowed.toString(), "0", "correct value of vault.amountBorrowed");
		assert.equal(incW1Balance.toString(), prevVault.amountSupplied.toString(), "correct change in balance of collateral asset");
		assert.isBelow(AmountError(expectedRepayment, actualRepayment), AcceptableMarginOfError, "zcb0 repayment amount is within error range");
		assert.equal(changeYieldA0.toString(), prevVault.amountSupplied.neg().toString());
		assert.equal(subAcctPosW1A0.bond.toString(), "0");
	});

	it('reopen vault via adjustment', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let prevVault = await vaultFactoryInstance.vaults(accounts[0], 0);
		let prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);

		let assetSupplied = wAsset1.address;
		let assetBorrowed = zcbAsset0.address;
		let amountSupplied = _10To18;
		let amountBorrowed = _10To18.div(new BN(4));

		await vaultFactoryInstance.adjustVault(
			accounts[0],
			0,
			assetSupplied,
			assetBorrowed,
			amountSupplied,
			amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		let currentBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		vault = await vaultFactoryInstance.vaults(accounts[0], 0);

		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		let incZCBBalance = currentBalanceZCB.sub(prevBalanceZCB);
		let decW1Balance = prevBalanceW1.sub(currentBalanceW1);

		assert.equal(vault.assetSupplied, assetSupplied, "correct value of vault.assetSupplied");
		assert.equal(vault.assetBorrowed, assetBorrowed, "correct value of vault.assetBorrowed");
		assert.equal(vault.amountSupplied.toString(), amountSupplied.toString(), "correct value of vault.amountSupplied");
		assert.equal(vault.amountBorrowed.toString(), amountBorrowed.toString(), "correct value of vault.amountBorrowed");
		assert.equal(decW1Balance.toString(), amountSupplied.toString(), "correct change in balance of collateral asset");
		assert.equal(incZCBBalance.toString(), amountBorrowed.toString(), "correct change in balance of debt asset");
		assert.equal(changeYieldA0.toString(), amountSupplied.toString());
		assert.equal(subAcctPosW1A0.bond.toString(), "0");
	});

	it('send undercollateralised vaults to liquidation', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		/*
			increase collateralisation ratio limits such that the open vault will be sent to liquidation
		*/
		upperRatio = vault.amountSupplied.mul(_10To18).div(vault.amountBorrowed).div(new BN(2));
		await vaultHealthInstance.setUpper(asset1.address, zcbAsset0.address, upperRatio);

		let surplus = new BN("10000");
		bid = vault.amountSupplied.sub(surplus);

		caught = false;
		try {
			await vaultFactoryInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, bid.toString(), vault.amountBorrowed.toString(), {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation was triggered despite vault health being above upper limit");

		upperRatio = vault.amountSupplied.mul(_10To18).div(vault.amountBorrowed).div(new BN(9)).mul(new BN(10));
		await vaultHealthInstance.setUpper(asset1.address, zcbAsset0.address, upperRatio);

		let prevRevenue = await vaultFactoryInstance.revenue(wAsset1.address);
		let prevContractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);

		let rec = await vaultFactoryInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, bid.toString(), vault.amountBorrowed.toString(), {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let secondsOpen = timestamp - vault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedActualIn = multiplier * parseInt(vault.amountBorrowed.toString());

		let contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		let currentRevenue = await vaultFactoryInstance.revenue(wAsset1.address);

		let rebate = surplus.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasury = surplus.sub(rebate);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.toString());
		assert.equal(changeYieldA0.toString(), toTreasury.neg().toString(), "correct change yield in sub account position");
		assert.equal(currentRevenue.sub(prevRevenue).toString(), toTreasury.toString(), "correct amount of revenue");

		assert.equal((await vaultFactoryInstance.liquidationsLength()).toString(), "1", "correct length of liquidations array");

		liquidation = await vaultFactoryInstance.Liquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.isBelow(AmountError(expectedActualIn, parseInt(liquidation.amountBorrowed.toString())), AcceptableMarginOfError, "liquidation.amountBorrowed within acceptable margin of error");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");

		prevVault = vault;
		vault = await vaultFactoryInstance.vaults(accounts[0], 0);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('bid on liquidation auctions', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		/*
			bid with account 1
		*/
		let surplus = new BN("10");
		bid = bid.sub(surplus);
		
		let prevRevenue = await vaultFactoryInstance.revenue(wAsset1.address);
		let prevContractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);

		let rec = await vaultFactoryInstance.bidOnLiquidation(0, bid.toString(), liquidation.amountBorrowed, {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		let currentRevenue = await vaultFactoryInstance.revenue(wAsset1.address);

		let rebate = surplus.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasury = surplus.sub(rebate);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.toString());
		assert.equal(changeYieldA0.toString(), toTreasury.neg().toString(), "correct change yield in sub account position");
		assert.equal(currentRevenue.sub(prevRevenue).toString(), toTreasury.toString(), "correct amount of revenue");

		let prevLiq = liquidation;
		liquidation = await vaultFactoryInstance.Liquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountBorrowed.toString(), prevLiq.amountBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");
	});

	it('claim liquidation auction rewards', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		//go 10 minuites into the future to claim liquidation
		await helper.advanceTime(10*60 + 1);

		let prevContractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		let prevBalW1 = await wAsset1.balanceOf(accounts[1]);

		await vaultFactoryInstance.claimLiquidation(0, accounts[1], {from: accounts[1]});

		let contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		let newBalW1 = await wAsset1.balanceOf(accounts[1]);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.sub(liquidation.bidAmount).toString());
		assert.equal(changeYieldA0.toString(), liquidation.bidAmount.neg().toString(), "correct change yield in sub account position");
		assert.equal(newBalW1.sub(prevBalW1).toString(), liquidation.bidAmount.toString(), "correct payout after winning liquidation");
	});

	it('instant liquidations upon dropping below lowerCollateralLimit', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		/*
			first open vaults
		*/
		let toSupply = _10To18
		let prevContractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		amountBorrowed = toSupply.mul(_10To18).div(new BN(upperRatio)).sub(new BN(1));
		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, toSupply, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, toSupply, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		let contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.add(toSupply.mul(new BN(2))).toString());

		lowerRatio =  _10To18.mul(_10To18).div(amountBorrowed).add(new BN(10000)).toString();
		await vaultHealthInstance.setLower(asset1.address, zcbAsset0.address, lowerRatio);

		vaultIndex = (await vaultFactoryInstance.vaultsLength(accounts[0])).toNumber() - 2;

		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);
		assert.equal(changeYieldA0.toString(), toSupply.mul(new BN(2)).toString());

		let prevVault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);
		prevContractBalanceW1 = contractBalanceW1;

		await vaultFactoryInstance.instantLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, amountBorrowed, _10To18.toString(), accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.sub(toSupply).toString());
		assert.equal(changeYieldA0.toString(), prevVault.amountSupplied.neg().toString());
		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('partial vault liquidations Specific In', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		vaultIndex++;

		let prevVault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		let amtIn = amountBorrowed.div(new BN(2))
		let minOut = _10To18.div(new BN(3));
		let prevContractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);

		await vaultFactoryInstance.partialLiquidationSpecificIn(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, amtIn, minOut, accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		let contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		let expectedOut = prevVault.amountSupplied.mul(amtIn).div(prevVault.amountBorrowed);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(changeYieldA0.toString(), expectedOut.neg().toString());
		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.sub(expectedOut).toString());

		assert.equal(vault.assetBorrowed, zcbAsset0.address, "assetBorrowed is correct");
		assert.equal(vault.assetSupplied, wAsset1.address, "assetSupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), prevVault.amountBorrowed.sub(amtIn).toString(), "amountBorrowed is correct");
		assert.equal(vault.amountSupplied.toString(), prevVault.amountSupplied.sub(expectedOut).toString(), "amountSupplied is correct");
	});

	it('partial vault liquidation Specific Out', async () => {
		await addRewards();
		await helper.advanceTime(1000);

		let prevVault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);
		let prevContractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);

		await vaultFactoryInstance.partialLiquidationSpecificOut(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address,
			prevVault.amountSupplied, prevVault.amountBorrowed, accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		let contractBalanceW1 = await wAsset1.balanceOf(vaultFactoryInstance.address);
		let prevSubAcctPosW1A0 = subAcctPosW1A0;
		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let changeYieldA0 = subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield);

		assert.equal(contractBalanceW1.toString(), prevContractBalanceW1.sub(prevVault.amountSupplied).toString());
		assert.equal(changeYieldA0.toString(), prevVault.amountSupplied.neg().toString());
		assert.equal(vault.assetBorrowed, zcbAsset0.address, "assetBorrowed is correct");
		assert.equal(vault.assetSupplied, wAsset1.address, "assetSupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is correct");
	});

	it('liquidates vaults due to time', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let amountSupplied = _10To18;

		upperRatio = amountSupplied.mul(_10To18).div(new BN(amountBorrowed)).div(new BN(2));
		await vaultHealthInstance.setUpper(asset1.address, zcbAsset0.address, upperRatio);

		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, amountSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, amountSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		vaultIndex = (await vaultFactoryInstance.vaultsLength(accounts[0])).toNumber() - 2;

		bid = amountSupplied;

		let caught = false;
		try {
			await vaultFactoryInstance.auctionLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, bid, amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was liquidated while above upper health limit before time liquidation period");


		/*
			advance 1 day to move into 7 day from maturity window
			this allows us to liquidate vaults on the premise of low time to maturity
		*/
		await helper.advanceTime(86401)

		let vaultState = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		let rec = await vaultFactoryInstance.auctionLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, bid, amountBorrowed, {from: accounts[1]});
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let secondsOpen = timestamp - vaultState.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedAmountIn = multiplier * parseInt(amountBorrowed.toString());

		assert.equal((await vaultFactoryInstance.liquidationsLength()).toString(), "2", "correct length of liquidations array");

		liquidation = await vaultFactoryInstance.Liquidations(1);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.isBelow(AmountError(expectedAmountIn, parseInt(liquidation.amountBorrowed.toString())), AcceptableMarginOfError, "liquidation.amountBorrowed is within acceptable margin of error");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toString(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await vaultFactoryInstance.vaults(accounts[0], 1);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('instant vault liquidations due to time to maturity', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		vaultIndex++;
		let caught = false;

		//change lower ratio so that vault is safe
		lowerRatio =  _10To18.mul(_10To18).div(new BN(amountBorrowed)).div(new BN(2)).toString();
		await vaultHealthInstance.setLower(asset1.address, zcbAsset0.address, lowerRatio);

		try {
			await vaultFactoryInstance.instantLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, amountBorrowed.toString(), _10To18.toString(), accounts[1], {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was subject to instant liquidation with more than 1 day to maturity");

		/*
			first advance 6 days into future so that instant liquidations are allowed because of 1 day to maturity rule
		*/
		let _6days = _8days*3/4;
		await helper.advanceTime(_6days);

		await vaultFactoryInstance.instantLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, amountBorrowed.toString(), _10To18.toString(), accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('contract owner withdraws revenue', async () => {
		let revenue = await vaultFactoryInstance.revenue(wAsset1.address);
		let expToTreasury = revenue.div(new BN(2));
		let expToOwner = revenue.sub(expToTreasury);

		let prevBalanceOwner = await wAsset1.balanceOf(accounts[0]);
		let prevBalanceTreasury = await wAsset1.balanceOf(treasuryAccount);

		await vaultFactoryInstance.claimRevenue(wAsset1.address);

		let newRevenue = await vaultFactoryInstance.revenue(wAsset1.address);

		let newBalanceOwner = await wAsset1.balanceOf(accounts[0]);
		let newBalanceTreasury = await wAsset1.balanceOf(treasuryAccount);

		assert.equal(newRevenue.toString(), "0", "revenue storage value reduced to 0 after all is withdrawn");
		assert.equal(newBalanceOwner.sub(prevBalanceOwner).toString(), expToOwner.toString(), "correct amount paid to contract owner");
		assert.equal(newBalanceTreasury.sub(prevBalanceTreasury).toString(), expToTreasury.toString(), "correct amount paid to treasury");
	});

	it('claim rebate', async () => {
		let rebate = await vaultFactoryInstance.liquidationRebates(accounts[0], wAsset1.address);
		let prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		let prevSubAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);

		await vaultFactoryInstance.claimRebate(wAsset1.address);

		subAcctPosW1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], nullAddress);
		let balanceW1 = await wAsset1.balanceOf(accounts[0]);
		assert.equal(balanceW1.sub(prevBalanceW1).toString(), rebate.toString());
		assert.equal(subAcctPosW1A0.yield.sub(prevSubAcctPosW1A0.yield).toString(), rebate.neg().toString());
		assert.equal(subAcctPosW1A0.bond.toString(), prevSubAcctPosW1A0.bond.toString());
	});

	it('can manage all vault and reward obligations', async() => {
		for (let i = 0; i < accounts.length; i++) {
			let vaults = await vaultFactoryInstance.allVaults(accounts[i]);
			for (let j = 0; j < vaults.length; j++) {
				if (vaults[j].amountSupplied.toString() !== "0") {
					await vaultFactoryInstance.closeVault(j, accounts[i], {from: accounts[i]});
				}
			}
		}
		let numLiqs = (await vaultFactoryInstance.liquidationsLength()).toNumber();
		await helper.advanceTime(AUCTION_COOLDOWN+1);
		for (let i = 0; i < numLiqs; i++) {
			let liq = await vaultFactoryInstance.Liquidations(i);
			if (liq.bidAmount.toString() !== "0") {
				await vaultFactoryInstance.claimLiquidation(i, accounts[0], {from: liq.bidder});
			}
		}
		let rewards = await wAsset1.distributionAccountRewards(0, vaultFactoryInstance.address);
		assert.isBelow(rewards.toNumber(), 100);
	});

	/*
		-------------------------------------------------Y-T---V-a-u-l-t-s-----------------------------------------------------
	*/


	it('before YT testing', async () => {
		await addRewards();
		maturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

		let rec0 = await organizerInstance.deployFixCapitalPoolInstance(wAsset0.address, maturity);
		let rec1 = await organizerInstance.deployFixCapitalPoolInstance(wAsset1.address, maturity);

		//reset chs, zcbAssets, ytAssets with new assets that are yet to reach maturity
		fcp0 = await fixCapitalPool.at(rec0.receipt.logs[0].args.FCPaddress);
		fcp1 = await fixCapitalPool.at(rec1.receipt.logs[0].args.FCPaddress);

		zcbAsset0 = await IERC20.at(await fcp0.zeroCouponBondAddress());
		zcbAsset1 = await IERC20.at(await fcp1.zeroCouponBondAddress());

		ytAsset0 = await IYieldToken.at(await fcp0.yieldTokenAddress());
		ytAsset1 = await IYieldToken.at(await fcp1.yieldTokenAddress());

		await fcp0.setVaultFactoryAddress(vaultFactoryInstance.address);
		await fcp1.setVaultFactoryAddress(vaultFactoryInstance.address);

		let _10To19 = _10To18.mul(new BN(10));

		//mint assets to account 0
		await asset1.mintTo(accounts[0], _10To19);
		await asset1.approve(wAsset1.address, _10To19);
		await wAsset1.depositUnitAmount(accounts[0], _10To19);
		await wAsset1.approve(vaultFactoryInstance.address, _10To19);
		await wAsset1.approve(fcp1.address, _10To19);
		await fcp1.depositWrappedToken(accounts[0], _10To19);
		await zcbAsset1.approve(vaultFactoryInstance.address, _10To19);

		await asset0.mintTo(accounts[0], _10To19);
		await asset0.approve(wAsset0.address, _10To19);
		await wAsset0.depositUnitAmount(accounts[0], _10To19);
		await wAsset0.approve(fcp0.address, _10To19);
		await fcp0.depositWrappedToken(accounts[0], _10To19);
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To19);

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To19);
		await asset0.approve(wAsset0.address, _10To19, {from: accounts[1]});
		await wAsset0.depositUnitAmount(accounts[1], _10To19, {from: accounts[1]});
		await wAsset0.approve(fcp0.address, _10To19, {from: accounts[1]});
		await fcp0.depositWrappedToken(accounts[1], _10To19, {from: accounts[1]});
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To19, {from: accounts[1]});
	});

	it('cannot open YT vault without whitelisting supplied asset', async () => {
		await addRewards();
		//mint ZCB to accounts[0]
		let toMint = _10To18.mul(new BN(10));
		await asset1.mintTo(accounts[0], toMint);
		await asset1.approve(wAsset1.address, toMint);
		await wAsset1.depositUnitAmount(accounts[0], toMint);
		let wBalance = await wAsset1.balanceOf(accounts[0]);
		await wAsset1.approve(fcp1.address, wBalance);
		await fcp1.depositWrappedToken(accounts[0], wBalance);
		await zcbAsset1.approve(vaultFactoryInstance.address, toMint);
		await ytAsset1.approve(vaultFactoryInstance.address, toMint);

		let caught = false;

		yieldSupplied = _10To18;
		bondSupplied = _10To18.neg();
		adjYieldSupplied = await wAsset1.WrappedAmtToUnitAmt_RoundDown(yieldSupplied);
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio));
		await vaultHealthInstance.setToReturn(true);
		maxShortInterest0 = _10To18.mul(_10To18).toString();
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);
		try {
			await vaultFactoryInstance.openYTVault(zcbAsset1.address, zcbAsset0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('only whitelisted assets may be supplied');
		await infoOracleInstance.whitelistFixCapitalPool(vaultFactoryInstance.address, fcp1.address);
	});

	it('opens YT vault', async () => {
		await addRewards();
		let prevSubAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let caught = false;
		maxShortInterest0 = "0";
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);
		//we are usign a dummy vault health contract, we need to set the value which it will return on vaultWithstandsChange() call
		await vaultHealthInstance.setToReturn(true);
		try {
			await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('borrowing must be limited by the short interest cap');

		//set max short interest super high so that we will not need to worry about it later in our tests
		maxShortInterest0 = _10To18.mul(_10To18).toString();
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);

		await vaultHealthInstance.setToReturn(false);
		caught = false;
		try {
			await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('open vault fails when vaultWithstandsChange() returns false');

		await vaultHealthInstance.setToReturn(true);
		caught = false;
		try {
			await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS-1, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful priceChange parameter must be >= TOTAL_BASIS_POINTS');

		caught = false;
		try {
			const over1ABDK = (new BN(ABDK_1)).add(new BN(1));
			await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, over1ABDK, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful suppliedRateChange parameter must be <= ABDK_1');

		caught = false;
		try {
			const over1ABDK = (new BN(ABDK_1)).add(new BN(1));
			await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, over1ABDK);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful borrowedRateChange parameter must be <= ABDK_1');

		var prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		var prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		var prevYield1 = await fcp1.balanceYield(accounts[0]);

		await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		assert.equal((await zcbAsset0.balanceOf(accounts[0])).toString(), prevBalanceZCB0.add(amountBorrowed).toString(), "correct amount of zcb credited to vault owner");
		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.sub(adjYieldSupplied).sub(bondSupplied).toString(), "correct amount of ZCB 1 supplied");
		assert.equal((await fcp1.balanceYield(accounts[0])).toString(), prevYield1.sub(yieldSupplied).toString(), "correct new value of balanceYield");

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal(vault.FCPsupplied, fcp1.address, "correct address for assetSupplied in vault");
		assert.equal(vault.FCPborrowed, fcp0.address, "correct address for assetBorrowed in vault");
		assert.equal(vault.yieldSupplied.toString(), yieldSupplied.toString(), "correct vaule of yieldSupplied in vault");
		assert.equal(vault.bondSupplied.toString(), bondSupplied.toString(), "correct vaule of bondSupplied in vault");
		assert.equal(vault.amountBorrowed.toString(), amountBorrowed, "correct vaule of amountBorrowed in vault");

		assert.equal(changeYieldA0.toString(), yieldSupplied.toString());
		assert.equal(changeBondA0.toString(), bondSupplied.toString());
	});

	it('deposits into YT vault', async () => {
		await addRewards();
		let prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		let prevYield1 = await fcp1.balanceYield(accounts[0]);
		let prevVault = vault;
		let toSupplyYield = _10To18;
		let adjSuppliedYield = await wAsset1.WrappedAmtToUnitAmt_RoundDown(toSupplyYield);
		let toSupplyBond = _10To18.neg();

		let newYield = vault.yieldSupplied.add(toSupplyYield);
		let newBond = vault.bondSupplied.add(toSupplyBond);

		await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			vault.FCPsupplied,
			vault.FCPborrowed,
			newYield,
			newBond,
			vault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.sub(adjSuppliedYield).sub(toSupplyBond), "correct amount of ZCB supplied");
		assert.equal((await fcp1.balanceYield(accounts[0])).toString(), prevYield1.sub(toSupplyYield).toString(), "correct amount of yield supplied");
		assert.equal(vault.yieldSupplied.toString(), newYield.toString(), "correct value of vault.yieldSupplied");
		assert.equal(vault.bondSupplied.toString(), newBond.toString(), "correct value of vault.bondSupplied");

		assert.equal(changeYieldA0.toString(), toSupplyYield.toString());
		assert.equal(changeBondA0.toString(), toSupplyBond.toString());
	});

	it('removes from YT vault', async () => {
		await addRewards();
		let prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		let prevYield1 = await fcp1.balanceYield(accounts[0]);
		let prevVault = vault;
		let amountYield = _10To18;
		let adjAmountYield = await wAsset1.WrappedAmtToUnitAmt_RoundDown(amountYield);
		let amountBond = _10To18.neg();

		let newYield = vault.yieldSupplied.sub(amountYield);
		let newBond = vault.bondSupplied.sub(amountBond);

		await vaultHealthInstance.setToReturn(false);
		let caught = false;
		try {
			await vaultFactoryInstance.adjustYTVault(
				accounts[0],
				0,
				vault.FCPsupplied,
				vault.FCPborrowed,
				newYield,
				newBond,
				vault.amountBorrowed,
				NON_CHANGE_MULTIPLIERS,
				[],
				accounts[0]
			);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("call to remove() should fail when vaultWithstandsChange() returns false");

		await vaultHealthInstance.setToReturn(true);

		await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			vault.FCPsupplied,
			vault.FCPborrowed,
			newYield,
			newBond,
			vault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.add(adjAmountYield).add(amountBond).sub(new BN(1)).toString(), "correct amount of ZCB received");
		assert.equal(prevVault.yieldSupplied.sub(vault.yieldSupplied).toString(), amountYield.toString(), "correct amount of yield removed from vault");
		assert.equal(vault.yieldSupplied.toString(), newYield.toString(), "correct value of vault.yieldSupplied");
		assert.equal(vault.bondSupplied.toString(), newBond.toString(), "correct value of vault.bondSupplied");

		assert.equal(changeYieldA0.toString(), amountYield.neg().toString());
		assert.equal(changeBondA0.toString(), amountBond.neg().toString());
	});

	it('deposits only ZCB into YT vault', async () => {
		await addRewards();
		let prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		let prevYield1 = await fcp1.balanceYield(accounts[0]);
		let prevVault = vault;
		let toSupplyBond = _10To18;

		let newBond = vault.bondSupplied.add(toSupplyBond);

		await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			vault.FCPsupplied,
			vault.FCPborrowed,
			vault.yieldSupplied,
			newBond,
			vault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.sub(toSupplyBond).toString(), "correct amount of ZCB supplied");
		assert.equal((await fcp1.balanceYield(accounts[0])).toString(), prevYield1.toString(), "balance yield remains constant");
		assert.equal(vault.yieldSupplied.toString(), prevVault.yieldSupplied.toString(), "correct value of vault.yieldSupplied");
		assert.equal(vault.bondSupplied.toString(), newBond.toString(), "correct value of vault.bondSupplied");

		assert.equal(subAcctPosF1A0.yield.toString(), prevSubAcctPosF1A0.yield.toString());
		assert.equal(changeBondA0.toString(), toSupplyBond.toString());
	});

	it('removes only ZCB from YT vault', async () => {
		await addRewards();
		let prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		let prevYield1 = await fcp1.balanceYield(accounts[0]);
		let prevVault = vault;
		let amountBond = _10To18;

		let newBond = vault.bondSupplied.sub(amountBond);

		await vaultHealthInstance.setToReturn(false);
		let caught = false;
		try {
			await vaultFactoryInstance.adjustYTVault(
				accounts[0],
				0,
				vault.FCPsupplied,
				vault.FCPborrowed,
				vault.yieldSupplied,
				newBond,
				vault.amountBorrowed,
				NON_CHANGE_MULTIPLIERS,
				[],
				accounts[0]
			);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("call to remove() should fail when vaultWithstandsChange() returns false");

		await vaultHealthInstance.setToReturn(true);

		await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			vault.FCPsupplied,
			vault.FCPborrowed,
			vault.yieldSupplied,
			newBond,
			vault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.add(amountBond), "correct amount of ZCB received");
		assert.equal((await fcp1.balanceYield(accounts[0])).toString(), prevYield1.toString(), "balance yield remains constant");
		assert.equal(vault.yieldSupplied.toString(), prevVault.yieldSupplied.toString(), "yield in vault remains constant");
		assert.equal(vault.bondSupplied.toString(), newBond.toString(), "correct value of vault.bondSupplied");

		assert.equal(subAcctPosF1A0.yield.toString(), prevSubAcctPosF1A0.yield.toString());
		assert.equal(changeBondA0.toString(), amountBond.neg().toString());
	});

	it('repays YT vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		toRepay = vault.amountBorrowed.div(new BN('2'));

		let prevVault = vault;
		var prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		let newDebt = vault.amountBorrowed.sub(toRepay);
		let rec = await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			vault.FCPsupplied,
			vault.FCPborrowed,
			vault.yieldSupplied,
			vault.bondSupplied,
			newDebt,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let secondsOpen = timestamp - vault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedRepayment = multiplier * parseInt(toRepay.toString());
		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);
		let currentBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		let actualRepayment = parseInt(prevBalanceZCB0.sub(currentBalanceZCB0).toString());
		let expectedDebt = multiplier * parseInt(newDebt.toString());
		let actualDebt = parseInt(vault.amountBorrowed.toString());

		assert.isBelow(AmountError(expectedRepayment, actualRepayment), AcceptableMarginOfError, "repayment is within error range");
		assert.isBelow(AmountError(expectedDebt, actualDebt), AcceptableMarginOfError, "actual vault debt error is within acceptable error range");
		assert.equal(vault.timestampOpened.toNumber(), timestamp, "vault.tiemstampOpened updates");

		assert.equal(subAcctPosF1A0.yield.toString(), prevSubAcctPosF1A0.yield.toString());
		assert.equal(subAcctPosF1A0.bond.toString(), prevSubAcctPosF1A0.bond.toString());
	});

	it('borrows from YT vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		toBorrow = toRepay;

		let prevVault = vault;
		var prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		let newDebt = vault.amountBorrowed.add(toBorrow);
		let rec = await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			vault.FCPsupplied,
			vault.FCPborrowed,
			vault.yieldSupplied,
			vault.bondSupplied,
			newDebt,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let secondsOpen = timestamp - vault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedBorrow = multiplier * parseInt(toBorrow.toString());
		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);
		let currentBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		let actualBorrow = parseInt(currentBalanceZCB0.sub(prevBalanceZCB0).toString());
		let expectedDebt = multiplier * parseInt(newDebt.toString());
		let actualDebt = parseInt(vault.amountBorrowed.toString());

		assert.isBelow(AmountError(expectedBorrow, actualBorrow), AcceptableMarginOfError, "received amount is within error range");
		assert.isBelow(AmountError(expectedDebt, actualDebt), AcceptableMarginOfError, "vault.amountBorrowed is within accpetable error range");
		assert.equal(vault.timestampOpened.toNumber(), timestamp, "vault.tiemstampOpened updates");

		assert.equal(subAcctPosF1A0.yield.toString(), prevSubAcctPosF1A0.yield.toString());
		assert.equal(subAcctPosF1A0.bond.toString(), prevSubAcctPosF1A0.bond.toString());
	});

	it('transfer YT vault', async () => {
		await addRewards();
		let prevVault = vault;

		let prevSubAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], prevVault.FCPsupplied);
		let prevSubAcctPosF1A2 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[2], prevVault.FCPsupplied);

		await vaultFactoryInstance.transferVault(0, accounts[2], true);

		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], prevVault.FCPsupplied);
		subAcctPosF1A2 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[2], prevVault.FCPsupplied);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);
		let changeYieldA2 = subAcctPosF1A2.yield.sub(prevSubAcctPosF1A2.yield);
		let changeBondA2 = subAcctPosF1A2.bond.sub(prevSubAcctPosF1A2.bond);

		let newVaultAcct0Ind0 = await vaultFactoryInstance.YTvaults(accounts[0], 0);
		let newVaultAcct2 = await vaultFactoryInstance.YTvaults(accounts[2], 0);

		assert.equal(newVaultAcct0Ind0.FCPsupplied, nullAddress);
		assert.equal(newVaultAcct0Ind0.FCPborrowed, nullAddress);
		assert.equal(newVaultAcct0Ind0.yieldSupplied.toString(), "0");
		assert.equal(newVaultAcct0Ind0.bondSupplied.toString(), "0");
		assert.equal(newVaultAcct0Ind0.amountBorrowed.toString(), "0");

		assert.equal(newVaultAcct2.FCPsupplied, prevVault.FCPsupplied);
		assert.equal(newVaultAcct2.FCPborrowed, prevVault.FCPborrowed);
		assert.equal(newVaultAcct2.yieldSupplied.toString(), prevVault.yieldSupplied.toString());
		assert.equal(newVaultAcct2.bondSupplied.toString(), prevVault.bondSupplied.toString());
		assert.equal(newVaultAcct2.amountBorrowed.toString(), prevVault.amountBorrowed.toString());

		assert.equal(changeYieldA0.toString(), prevVault.yieldSupplied.neg().toString());
		assert.equal(changeBondA0.toString(), prevVault.bondSupplied.neg().toString());
		assert.equal(changeYieldA2.toString(), prevVault.yieldSupplied.toString());
		assert.equal(changeBondA2.toString(), prevVault.bondSupplied.toString());

		await vaultFactoryInstance.transferVault(0, accounts[0], true, {from: accounts[2]});

		prevSubAcctPosF1A0 = subAcctPosF1A0;
		prevSubAcctPosF1A2 = subAcctPosF1A2;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], prevVault.FCPsupplied);
		subAcctPosF1A2 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[2], prevVault.FCPsupplied);
		changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);
		changeYieldA2 = subAcctPosF1A2.yield.sub(prevSubAcctPosF1A2.yield);
		changeBondA2 = subAcctPosF1A2.bond.sub(prevSubAcctPosF1A2.bond);
		let newVaultAcct0Ind1 = await vaultFactoryInstance.YTvaults(accounts[0], 1);
		newVaultAcct2 = await vaultFactoryInstance.YTvaults(accounts[2], 0);

		assert.equal(newVaultAcct0Ind0.FCPsupplied, nullAddress);
		assert.equal(newVaultAcct0Ind0.FCPborrowed, nullAddress);
		assert.equal(newVaultAcct0Ind0.yieldSupplied.toString(), "0");
		assert.equal(newVaultAcct0Ind0.bondSupplied.toString(), "0");
		assert.equal(newVaultAcct0Ind0.amountBorrowed.toString(), "0");

		assert.equal(newVaultAcct2.FCPsupplied, nullAddress);
		assert.equal(newVaultAcct2.FCPborrowed, nullAddress);
		assert.equal(newVaultAcct2.yieldSupplied.toString(), "0");
		assert.equal(newVaultAcct2.bondSupplied.toString(), "0");
		assert.equal(newVaultAcct2.amountBorrowed.toString(), "0");

		assert.equal(newVaultAcct0Ind1.FCPsupplied, prevVault.FCPsupplied);
		assert.equal(newVaultAcct0Ind1.FCPborrowed, prevVault.FCPborrowed);
		assert.equal(newVaultAcct0Ind1.yieldSupplied.toString(), prevVault.yieldSupplied.toString());
		assert.equal(newVaultAcct0Ind1.bondSupplied.toString(), prevVault.bondSupplied.toString());
		assert.equal(newVaultAcct0Ind1.amountBorrowed.toString(), prevVault.amountBorrowed.toString());

		assert.equal(changeYieldA0.toString(), prevVault.yieldSupplied.toString());
		assert.equal(changeBondA0.toString(), prevVault.bondSupplied.toString());
		assert.equal(changeYieldA2.toString(), prevVault.yieldSupplied.neg().toString());
		assert.equal(changeBondA2.toString(), prevVault.bondSupplied.neg().toString());
	});

	it('close YT vault', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		let prevVault = vault;
		oldVault = vault;
		let prevBonds1 = await fcp1.balanceBonds(accounts[0]);
		let prevYield1 = await fcp1.balanceYield(accounts[0]);
		let prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		let rec = await vaultFactoryInstance.closeYTVault(1, accounts[0]);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let newBonds1 = await fcp1.balanceBonds(accounts[0]);
		let newYield1 = await fcp1.balanceYield(accounts[0]);
		let newBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let secondsOpen = timestamp - vault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedRepayment = multiplier * parseInt(oldVault.amountBorrowed.toString());

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 1);

		let changeYield = newYield1.sub(prevYield1);
		let changeBond = newBonds1.sub(prevBonds1);
		let changeDebtAsset = prevBalanceZCB0.sub(newBalanceZCB0);
		let actualRepayment = parseInt(changeDebtAsset.toString());

		assert.equal(vault.FCPsupplied, nullAddress, "correct value of vault.FCPsupplied");
		assert.equal(vault.FCPborrowed, nullAddress, "correct value of vault.FCPborrowed");
		assert.equal(vault.yieldSupplied.toString(), "0", "correct value of vault.yieldSupplied");
		assert.equal(vault.bondSupplied.toString(), "0", "correct value of vault.bondSupplied");
		assert.equal(vault.amountBorrowed.toString(), "0", "correct value of vault.amountBorrowed");
		assert.equal(changeYield.toString(), prevVault.yieldSupplied.toString(), "correct change in balanceYield of collateral FCP");
		assert.equal(changeBond.toString(), prevVault.bondSupplied.toString(), "correct change in balanceBonds of collateral FCP");
		assert.isBelow(AmountError(expectedRepayment, actualRepayment), AcceptableMarginOfError, "repayment is within acceptable margin of error");

		assert.equal(changeYieldA0.toString(), oldVault.yieldSupplied.neg().toString());
		assert.equal(changeBondA0.toString(), oldVault.bondSupplied.neg().toString());
	});

	it('reopen YT vault via adjustment', async () => {
		await addRewards();
		let prevVault = vault;

		let prevBonds1 = await fcp1.balanceBonds(accounts[0]);
		let prevYield1 = await fcp1.balanceYield(accounts[0]);
		let prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		await vaultFactoryInstance.adjustYTVault(
			accounts[0],
			0,
			oldVault.FCPsupplied,
			oldVault.FCPborrowed,
			oldVault.yieldSupplied,
			oldVault.bondSupplied,
			oldVault.amountBorrowed,
			NON_CHANGE_MULTIPLIERS,
			[],
			accounts[0]
		);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let newBonds1 = await fcp1.balanceBonds(accounts[0]);
		let newYield1 = await fcp1.balanceYield(accounts[0]);
		let newBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		let changeYield = prevYield1.sub(newYield1);
		let changeBond = prevBonds1.sub(newBonds1);
		let changeDebtAsset = newBalanceZCB0.sub(prevBalanceZCB0);

		assert.equal(vault.FCPsupplied, oldVault.FCPsupplied, "correct value of vault.FCPsupplied");
		assert.equal(vault.FCPborrowed, oldVault.FCPborrowed, "correct value of vault.FCPborrowed");
		assert.equal(vault.yieldSupplied.toString(), oldVault.yieldSupplied.toString(), "correct value of vault.yieldSupplied");
		assert.equal(vault.bondSupplied.toString(), oldVault.bondSupplied.toString(), "correct value of vault.bondSupplied");
		assert.equal(vault.amountBorrowed.toString(), oldVault.amountBorrowed.toString(), "correct value of vault.amountBorrowed");
		assert.equal(changeYield.toString(), oldVault.yieldSupplied.toString(), "correct change in balanceYield of collateral FCP");
		assert.equal(changeBond.toString(), oldVault.bondSupplied.toString(), "correct change in balanceBonds of collateral FCP");
		assert.equal(changeDebtAsset.toString(), oldVault.amountBorrowed.toString(), "correct change in balance of debt asset");

		assert.equal(changeYieldA0.toString(), oldVault.yieldSupplied.toString());
		assert.equal(changeBondA0.toString(), oldVault.bondSupplied.toString());
	});

	it('send undercollateralised YT vaults to liquidation', async () => {
		await addRewards();
		await helper.advanceTime(1000);
		//tx should revert when vault satisfies limit
		await vaultHealthInstance.setToReturn(true);
		let surplusYield = new BN("10000");
		let amtIn = vault.amountBorrowed;
		bid = vault.yieldSupplied.sub(surplusYield);
		bondCorrespondingToBid = vault.bondSupplied.mul(amtIn).mul(bid).div(vault.amountBorrowed).div(vault.yieldSupplied);
		let minBondRatio = _10To18.mul(vault.bondSupplied).div(vault.yieldSupplied).sub(new BN(10));
		actualBondRatio = _10To18.mul(vault.bondSupplied).div(vault.yieldSupplied).add(new BN(1));
		let surplusBond = vault.bondSupplied.sub(bondCorrespondingToBid);

		caught = false;
		try {
			await vaultFactoryInstance.auctionYTLiquidation(accounts[0], 0, fcp0.address, fcp1.address, bid, minBondRatio, vault.amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation was triggered despite vault health being above upper limit");

		await vaultHealthInstance.setToReturn(false);

		let prevRevenue = await vaultFactoryInstance.YTrevenue(fcp1.address);

		let rec = await vaultFactoryInstance.auctionYTLiquidation(accounts[0], 0, fcp0.address, fcp1.address, bid, minBondRatio, vault.amountBorrowed, {from: accounts[1]});

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let secondsOpen = timestamp - vault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedAmtIn = multiplier * parseInt(vault.amountBorrowed.toString());

		let currentRevenue = await vaultFactoryInstance.YTrevenue(fcp1.address);

		let rebateYield = surplusYield.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryYield = surplusYield.sub(rebateYield);

		let rebateBond = surplusBond.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryBond = surplusBond.sub(rebateBond).sub(new BN(1));

		assert.equal(currentRevenue.yield.sub(prevRevenue.yield).toString(), toTreasuryYield.toString(), "correct amount of yield revenue");
		assert.equal(currentRevenue.bond.sub(prevRevenue.bond).toString(), toTreasuryBond.toString(), "correct amount of bond revenue");

		assert.equal((await vaultFactoryInstance.YTLiquidationsLength()).toString(), "1", "correct length of liquidations array");

		liquidation = await vaultFactoryInstance.YTLiquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.FCPborrowed, fcp0.address, "correct value of liquidation.FCPborrowed");
		assert.equal(liquidation.FCPsupplied, fcp1.address, "correct value of liquidation.FCPsupplied");
		assert.isBelow(AmountError(expectedAmtIn, parseInt(liquidation.amountBorrowed.toString())), AcceptableMarginOfError, "liquidation.amountBorrowed is within acceptable margin of error");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bondRatio.toString(), actualBondRatio.toString(), "correct value of liquidation.bondRatio");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal(vault.FCPborrowed, nullAddress, "FCPborrowed is null");
		assert.equal(vault.FCPsupplied, nullAddress, "FCPsupplied is null");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is null");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");

		assert.equal(changeYieldA0.toString(), toTreasuryYield.neg().toString());
		assert.equal(changeBondA0.toString(), toTreasuryBond.neg().toString());
	});


	it('bid on YT liquidation auctions', async () => {
		await addRewards();
		/*
			bid with account 1
		*/
		let surplusYield = new BN("10");
		bid = bid.sub(surplusYield);
		bondCorrespondingToPrevBid = liquidation.bondRatio.mul(liquidation.bidAmount).div(_10To18);
		bondCorrespondingToBid = liquidation.bondRatio.mul(bid).div(_10To18).add(new BN(1));
		let surplusBond = bondCorrespondingToPrevBid.sub(bondCorrespondingToBid);

		let prevRevenue = await vaultFactoryInstance.YTrevenue(fcp1.address);

		let rec = await vaultFactoryInstance.bidOnYTLiquidation(0, bid.toString(), liquidation.amountBorrowed, {from: accounts[1]});

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let currentRevenue = await vaultFactoryInstance.YTrevenue(fcp1.address);

		let rebateYield = surplusYield.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryYield = surplusYield.sub(rebateYield);

		let rebateBond = surplusBond.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryBond = surplusBond.sub(rebateBond);

		assert.equal(currentRevenue.yield.sub(prevRevenue.yield).toString(), toTreasuryYield.toString(), "correct amount of yield revenue");
		assert.equal(currentRevenue.bond.sub(prevRevenue.bond).toString(), toTreasuryBond.toString(), "correct amount of bond revenue");

		let prevBorrowed = liquidation.amountBorrowed;

		liquidation = await vaultFactoryInstance.YTLiquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.FCPborrowed, fcp0.address, "correct value of liquidation.FCPborrowed");
		assert.equal(liquidation.FCPsupplied, fcp1.address, "correct value of liquidation.FCPsupplied");
		assert.equal(liquidation.amountBorrowed.toString(), prevBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bondRatio.toString(), actualBondRatio.toString(), "correct value of liquidation.bondRatio");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");

		assert.equal(changeYieldA0.toString(), toTreasuryYield.neg().toString());
		assert.equal(changeBondA0.toString(), toTreasuryBond.neg().toString());
	});

	it('claim YT liquidation auction rewards', async () => {
		await addRewards();
		//go 10 minuites into the future to claim liquidation
		await helper.advanceTime(10*60 + 1);

		let prevBalYield = await fcp1.balanceYield(accounts[1]);
		let prevBalBonds = await fcp1.balanceBonds(accounts[1]);

		await vaultFactoryInstance.claimYTLiquidation(0, accounts[1], {from: accounts[1]});

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let newBalYield = await fcp1.balanceYield(accounts[1]);
		let newBalBonds = await fcp1.balanceBonds(accounts[1]);

		let expectedBondChange = liquidation.bondRatio.sub(new BN(1)).mul(liquidation.bidAmount).div(_10To18);
		assert.equal(newBalYield.sub(prevBalYield).toString(), liquidation.bidAmount.toString(), "correct payout yield after winning YTLiquidation auction");
		assert.equal(newBalBonds.sub(prevBalBonds).toString(), expectedBondChange.toString(), "correct payout bond after winning YTLiquidation auction");

		assert.equal(changeYieldA0.toString(), liquidation.bidAmount.neg().toString());
		assert.equal(changeBondA0.toString(), expectedBondChange.neg().toString());
	});

	it('cannot liquidate YTVaults that have been autopaid off', async () => {
		await addRewards();
		let ys = 10000000;
		let debt = 100000;
		let bs = debt - ys;
		maxShortInterest0 = _10To18.mul(_10To18).toString();
		await vaultHealthInstance.setMaximumShortInterest(asset1.address, maxShortInterest0);
		await vaultHealthInstance.setToReturn(true);
		await vaultFactoryInstance.openYTVault(fcp1.address, fcp1.address, ys, bs, debt, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultHealthInstance.setToReturn(false);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		assert.equal(changeYieldA0.toString(), ys.toString());
		assert.equal(changeBondA0.toString(), bs.toString());

		let bid = debt;
		vaultIndex = (await vaultFactoryInstance.YTvaultsLength(accounts[0])).toNumber() - 1;
		sameFCPvaultIndex = vaultIndex;
		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);
		let minBondRatio = _10To18.mul(vault.bondSupplied).div(vault.yieldSupplied).sub(new BN(10));
		let caught = false;
		try {
			await vaultFactoryInstance.auctionYTLiquidation(accounts[0], sameFCPvaultIndex, fcp0.address, fcp0.address, bid, minBondRatio, vault.amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail('cannot liquidate YTvault that can be autopaid');
		}
	});

	it('instant YT liquidations upon dropping below lowerCollateralLimit', async () => {
		await addRewards();
		/*
			first open vaults
		*/
		await vaultHealthInstance.setToReturn(true);
		yieldSupplied = _10To18;
		bondSupplied = _10To18.neg();
		amountBorrowed = _10To18;
		await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		assert.equal(changeYieldA0.toString(), yieldSupplied.mul(new BN(2)).toString());
		assert.equal(changeBondA0.toString(), bondSupplied.mul(new BN(2)).toString());

		minBondRatio = bondSupplied.mul(_10To18).div(yieldSupplied).sub(new BN(10));
		vaultIndex = (await vaultFactoryInstance.YTvaultsLength(accounts[0])).toNumber() - 2;
		await vaultHealthInstance.setToReturn(true);
		let caught = false;
		try {
			await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, fcp0.address, fcp1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});
		}
		catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation tx should revert if vault is in good health");

		await vaultHealthInstance.setToReturn(false);
		await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, fcp0.address, fcp1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});

		prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.FCPborrowed, nullAddress, "FCPborrowed is null");
		assert.equal(vault.FCPsupplied, nullAddress, "FCPsupplied is null");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is null");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");

		assert.equal(changeYieldA0.toString(), yieldSupplied.neg().toString());
		assert.equal(changeBondA0.toString(), bondSupplied.neg().toString());
	});


	it('partial vault YT liquidations Specific In', async () => {
		await addRewards();
		vaultIndex++;
		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		let amtIn = vault.amountBorrowed.div(new BN(2));
		let expectedYieldOut = vault.yieldSupplied.mul(amtIn).div(vault.amountBorrowed);
		let expectedBondOut = vault.bondSupplied.mul(amtIn).div(vault.amountBorrowed);
		let minYieldOut = expectedYieldOut.sub(new BN(1));
		await vaultHealthInstance.setToReturn(false);
		await vaultFactoryInstance.partialYTLiquidationSpecificIn(accounts[0], vaultIndex, fcp0.address, fcp1.address, amtIn, minYieldOut, minBondRatio, accounts[1], {from: accounts[1]});

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let prevVault = vault;
		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.FCPborrowed, fcp0.address, "FCPborrowed is correct");
		assert.equal(vault.FCPsupplied, fcp1.address, "FCPsupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), prevVault.amountBorrowed.sub(amtIn).toString(), "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), prevVault.yieldSupplied.sub(expectedYieldOut).toString(), "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), prevVault.bondSupplied.sub(expectedBondOut).toString(), "bondSupplied is correct");

		assert.equal(changeYieldA0.toString(), expectedYieldOut.neg().toString());
		assert.equal(changeBondA0.toString(), expectedBondOut.neg().toString());
	});

	it('partial vault YT liquidation Specific Out', async () => {
		await addRewards();
		await vaultHealthInstance.setToReturn(false);
		await vaultFactoryInstance.partialYTLiquidationSpecificOut(accounts[0], vaultIndex, fcp0.address, fcp1.address,
			vault.yieldSupplied, minBondRatio, vault.amountBorrowed, accounts[1], {from: accounts[1]});

		let prevSubAcctPosF1A0 = subAcctPosF1A0;
		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let changeYieldA0 = subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield);
		let changeBondA0 = subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond);

		let prevVault = vault;
		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.FCPborrowed, fcp0.address, "FCPborrowed is correct");
		assert.equal(vault.FCPsupplied, fcp1.address, "FCPsupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is correct");

		assert.equal(changeYieldA0.toString(), prevVault.yieldSupplied.neg().toString());
		assert.equal(changeBondA0.toString(), prevVault.bondSupplied.neg().toString());
	});

	it('liquidates YT vaults due to time', async () => {
		await addRewards();
		let amountSupplied = _10To18;

		await vaultHealthInstance.setToReturn(true);
		await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openYTVault(fcp1.address, fcp0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		vaultIndex = (await vaultFactoryInstance.YTvaultsLength(accounts[0])).toNumber() - 2;

		bid = amountSupplied;

		let caught = false;
		//test for when vaults are in good health
		await vaultHealthInstance.setToReturn(true);
		try {
			await vaultFactoryInstance.auctionYTLiquidation(accounts[0], vaultIndex, fcp0.address, fcp1.address, bid, minBondRatio, amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was liquidated while above upper health limit before time liquidation period");


		/*
			advance 1 day to move into 7 day from maturity window
			this allows us to liquidate vaults on the premise of low time to maturity
		*/
		await helper.advanceTime(86401)

		let rec = await vaultFactoryInstance.auctionYTLiquidation(accounts[0], vaultIndex, fcp0.address, fcp1.address, bid, minBondRatio, amountBorrowed, {from: accounts[1]});
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let secondsOpen = timestamp - vault.timestampOpened.toNumber();
		let yearsOpen = secondsOpen / secondsPerYear;
		let multiplier = Math.pow(stabilityFee0, yearsOpen);
		let expectedAmtIn = multiplier * parseInt(amountBorrowed.toString());

		assert.equal((await vaultFactoryInstance.YTLiquidationsLength()).toString(), "2", "correct length of liquidations array");

		let expectedBondRatio = bondSupplied.mul(_10To18).div(yieldSupplied).add(new BN(1));

		liquidation = await vaultFactoryInstance.YTLiquidations(1);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.FCPborrowed, fcp0.address, "correct value of liquidation.FCPborrowed");
		assert.equal(liquidation.FCPsupplied, fcp1.address, "correct value of liquidation.FCPsupplied");
		assert.isBelow(AmountError(expectedAmtIn, parseInt(liquidation.amountBorrowed.toString())), AcceptableMarginOfError, "liquidation.amountBorrowed is within acceptable margin of error");
		assert.equal(liquidation.bondRatio.toString(), expectedBondRatio.toString(), "correct value of liquidation.bondRatio")
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toString(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 3);

		assert.equal(vault.FCPborrowed, nullAddress, "FCPborrowed is null");
		assert.equal(vault.FCPsupplied, nullAddress, "FCPsupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is correct");
	});

	it('cannot liquidate YTVaults (on time) that have been autopaid off', async () => {
		await addRewards();
		await vaultHealthInstance.setToReturn(false);
		vault = await vaultFactoryInstance.YTvaults(accounts[0], sameFCPvaultIndex);
		let minBondRatio = _10To18.mul(vault.bondSupplied).div(vault.yieldSupplied).sub(new BN(10));
		let caught = false;
		try {
			await vaultFactoryInstance.auctionYTLiquidation(accounts[0], sameFCPvaultIndex, fcp0.address, fcp0.address,
				vault.amountBorrowed, minBondRatio, vault.amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail('cannot liquidate YTvault that can be autopaid');
		}
	});

	it('instant vault YT liquidations due to time to maturity', async () => {
		await addRewards();
		vaultIndex++;
		let caught = false;

		await vaultHealthInstance.setToReturn(true);
		try {
			await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, fcp0.address, fcp1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was subject to instant liquidation with more than 1 day to maturity");

		/*
			first advance 6 days into future so that instant liquidations are allowed because of 1 day to maturity rule
		*/
		let _6days = _8days*3/4;
		await helper.advanceTime(_6days);

		await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, fcp0.address, fcp1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.FCPborrowed, nullAddress, "FCPborrowed is correct");
		assert.equal(vault.FCPsupplied, nullAddress, "FCPsupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is correct");
	});

	it('cannot instantly liquidate YTVaults (on time) that have been autopaid off', async () => {
		await addRewards();
		await vaultHealthInstance.setToReturn(false);
		vault = await vaultFactoryInstance.YTvaults(accounts[0], sameFCPvaultIndex);
		let minBondRatio = _10To18.mul(vault.bondSupplied).div(vault.yieldSupplied).sub(new BN(10));
		let caught = false;
		try {
			await vaultFactoryInstance.instantYTLiquidation(accounts[0], sameFCPvaultIndex, fcp0.address, fcp0.address, vault.amountBorrowed, vault.yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail('cannot liquidate YTvault that can be autopaid');
		}
	});

	it('contract owner withdraws YT revenue', async () => {
		await addRewards();
		let revenue = await vaultFactoryInstance.YTrevenue(fcp1.address);

		let caught = false;
		let bondIn = "2";
		try {
			await vaultFactoryInstance.claimYTRevenue(fcp1.address, bondIn, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("only contract owner should be able to claim revenue");

		let expYieldToTreasury = revenue.yield.div(new BN(2));
		let expBondToTreasury = revenue.bond.add(new BN(bondIn)).div(new BN(2));
		let expYieldToOwner = revenue.yield.sub(expYieldToTreasury);
		let expBondToOwner = revenue.bond.add(new BN(bondIn)).sub(expBondToTreasury);

		let prevOwnerBalanceYield = await fcp1.balanceYield(accounts[0]);
		let prevOwnerBalanceBond = await fcp1.balanceBonds(accounts[0]);
		let prevTreasuryBalanceYield = await fcp1.balanceYield(treasuryAccount);
		let prevTreasuryBalanceBond = await fcp1.balanceBonds(treasuryAccount);

		await vaultFactoryInstance.claimYTRevenue(fcp1.address, bondIn);

		let newRevenue = await vaultFactoryInstance.YTrevenue(fcp1.address);

		let newOwnerBalanceYield = await fcp1.balanceYield(accounts[0]);
		let newOwnerBalanceBond = await fcp1.balanceBonds(accounts[0]);
		let newTreasuryBalanceYield = await fcp1.balanceYield(treasuryAccount);
		let newTreasuryBalanceBond = await fcp1.balanceBonds(treasuryAccount);

		assert.equal(newRevenue.yield.toString(), "0", "revenue yield value reduced to 0 after all is withdrawn");
		assert.equal(newRevenue.bond.toString(), "0", "revenue bond value reduced to 0 after all is withdrawn");
		assert.equal(newOwnerBalanceYield.sub(prevOwnerBalanceYield).toString(), expYieldToOwner.toString(), "correct amount yield paid to contract owner");
		assert.equal(newOwnerBalanceBond.sub(prevOwnerBalanceBond.sub(new BN(bondIn))).toString(), expBondToOwner.toString(), "correct amount bond paid to contract owner");
		assert.equal(newTreasuryBalanceYield.sub(prevTreasuryBalanceYield).toString(), expYieldToTreasury.toString(), "correct amount yield paid to treasury");
		assert.equal(newTreasuryBalanceBond.sub(prevTreasuryBalanceBond).toString(), expBondToTreasury.toString(), "correct amount bond paid to treasury");
	});

	it('claim YT vault rebate', async () => {
		let rebate = await vaultFactoryInstance.YTLiquidationRebates(accounts[0], fcp1.address);
		let prevYieldF1 = await fcp1.balanceYield(accounts[0]);
		let prevBondF1 = await fcp1.balanceBonds(accounts[0]);
		let prevSubAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);

		await vaultFactoryInstance.claimYTRebate(fcp1.address);

		subAcctPosF1A0 = await wAsset1.subAccountPositions(vaultFactoryInstance.address, accounts[0], fcp1.address);
		let yieldF1 = await fcp1.balanceYield(accounts[0]);
		let bondF1 = await fcp1.balanceBonds(accounts[0]);
		assert.equal(yieldF1.sub(prevYieldF1).toString(), rebate.yield.toString());
		assert.equal(bondF1.sub(prevBondF1).toString(), rebate.bond.toString());
		assert.equal(subAcctPosF1A0.yield.sub(prevSubAcctPosF1A0.yield).toString(), rebate.yield.neg().toString());
		assert.equal(subAcctPosF1A0.bond.sub(prevSubAcctPosF1A0.bond).toString(), rebate.bond.neg().toString());
	});

	it('can manage all YT vault and reward obligations', async() => {
		for (let i = 0; i < accounts.length; i++) {
			let ytVaultLen = await vaultFactoryInstance.YTvaultsLength(accounts[i]);
			for (let j = 0; j < ytVaultLen; j++) {
				let ytVault = await vaultFactoryInstance.YTvaults(accounts[i], j);
				if (ytVault.yieldSupplied.toString() !== "0" || ytVault.bondSupplied.toString() !== "0") {
					await vaultFactoryInstance.closeVault(j, accounts[i], {from: accounts[i]});
				}
			}
		}
		let numLiqs = (await vaultFactoryInstance.YTLiquidationsLength()).toNumber();
		await helper.advanceTime(AUCTION_COOLDOWN+1);
		for (let i = 0; i < numLiqs; i++) {
			let liq = await vaultFactoryInstance.YTLiquidations(i);
			if (liq.bidAmount.toString() !== "0") {
				await vaultFactoryInstance.claimYTLiquidation(i, accounts[0], {from: liq.bidder});
			}
		}
		let rewards = await wAsset1.distributionAccountRewards(0, vaultFactoryInstance.address);
		assert.isBelow(rewards.toNumber(), 100);
	});

});