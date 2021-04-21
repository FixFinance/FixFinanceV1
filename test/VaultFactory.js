const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const capitalHandler = artifacts.require('CapitalHandler');
const IYieldToken = artifacts.require("IYieldToken");
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const organizer = artifacts.require('organizer');
const VaultFactoryDelegate = artifacts.require("VaultFactoryDelegate");
const VaultFactoryDelegate2 = artifacts.require("VaultFactoryDelegate2");
const VaultFactory = artifacts.require('VaultFactory');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const CapitalHandlerDeployer = artifacts.require('CapitalHandlerDeployer');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const AmmInfoOracle = artifacts.require("AmmInfoOracle");

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const _10 = new BN(10)
const _10To18 = _10.pow(new BN('18'));

const _8days = 8*24*60*60;

const TOTAL_BASIS_POINTS = 10000;

function basisPointsToABDKString(bips) {
	return (new BN(bips)).mul((new BN(2)).pow(new BN(64))).div(_10.pow(new BN(4))).toString();
}

const ABDK_1 = basisPointsToABDKString(TOTAL_BASIS_POINTS);

const rebate_bips = 120;

contract('VaultFactory', async function(accounts) {

	/* 
		for simplicity of testing in this contract we assume that 1 unit of each asset is equal in vaulue to 1 unit of any other asset
	*/
	it('before each', async () => {
		//borrow asset 0
		asset0 = await dummyAToken.new("aCOIN");
		//supply asset 1
		asset1 = await dummyAToken.new("aTOKEN");
		zcbYtDeployerInstance = await zcbYtDeployer.new();
		vaultHealthInstance = await dummyVaultHealth.new();
		vaultFactoryDelegateInstance = await VaultFactoryDelegate.new();
		vaultFactoryDelegate2Instance = await VaultFactoryDelegate2.new();
		vaultFactoryInstance = await VaultFactory.new(
			vaultHealthInstance.address,
			vaultFactoryDelegateInstance.address,
			vaultFactoryDelegate2Instance.address
		);
		EiInstance = await Ei.new();
		await BigMath.link("Ei", EiInstance.address);
		BigMathInstance = await BigMath.new();
		await ZCBammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDeployer.link("BigMath", BigMathInstance.address);
		await YTammDelegate.link("BigMath", BigMathInstance.address);
		ZCBammDeployerInstance = await ZCBammDeployer.new();
		YTammDelegateInstance = await YTammDelegate.new();
		YTammDeployerInstance = await YTammDeployer.new(YTammDelegateInstance.address);
		capitalHandlerDeployerInstance = await CapitalHandlerDeployer.new();
		ammInfoOracleInstance = await AmmInfoOracle.new("0", nullAddress);
		organizerInstance = await organizer.new(
			zcbYtDeployerInstance.address,
			capitalHandlerDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			nullAddress,
			ammInfoOracleInstance.address,
			accounts[0]
		);

		maturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

		let reca = await organizerInstance.deployAssetWrapper(asset0.address);
		let recb = await organizerInstance.deployAssetWrapper(asset1.address);

		wAsset0 = await NGBwrapper.at(reca.receipt.logs[0].args.wrapperAddress);
		wAsset1 = await NGBwrapper.at(recb.receipt.logs[0].args.wrapperAddress);

		let rec0 = await organizerInstance.deployCapitalHandlerInstance(wAsset0.address, maturity);
		let rec1 = await organizerInstance.deployCapitalHandlerInstance(wAsset1.address, maturity);

		await asset0.approve(wAsset0.address, _10To18.toString());
		await asset1.approve(wAsset1.address, _10To18.toString());

		await wAsset0.depositUnitAmount(accounts[0], _10To18.toString());
		await wAsset1.depositUnitAmount(accounts[0], _10To18.toString());

		ch0 = await capitalHandler.at(rec0.receipt.logs[0].args.addr);
		ch1 = await capitalHandler.at(rec1.receipt.logs[0].args.addr);

		zcbAsset0 = await IERC20.at(await ch0.zeroCouponBondAddress());
		zcbAsset1 = await IERC20.at(await ch1.zeroCouponBondAddress());

		ytAsset0 = await IYieldToken.at(await ch0.yieldTokenAddress());
		ytAsset1 = await IYieldToken.at(await ch1.yieldTokenAddress());

		await ch0.setVaultFactoryAddress(vaultFactoryInstance.address);
		await ch1.setVaultFactoryAddress(vaultFactoryInstance.address);

		await vaultFactoryInstance.whitelistWrapper(wAsset1.address);
		await vaultFactoryInstance.setLiquidationRebate(rebate_bips);

		//mint assets to account 0
		await asset1.mintTo(accounts[0], _10To18.mul(new BN("10")).toString());
		await asset1.approve(wAsset1.address, _10To18.mul(new BN("10")).toString());
		await wAsset1.depositUnitAmount(accounts[0], _10To18.mul(new BN("10")).toString());
		await wAsset1.approve(vaultFactoryInstance.address, _10To18.mul(new BN("10")).toString());
		await wAsset1.approve(ch1.address, _10To18.mul(new BN("10")).toString());
		await ch1.depositWrappedToken(accounts[0], _10To18.mul(new BN("10")).toString());
		await zcbAsset1.approve(vaultFactoryInstance.address, _10To18.mul(new BN("10")).toString());

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To18.mul(new BN("10")).toString());
		await asset0.approve(wAsset0.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await wAsset0.depositUnitAmount(accounts[1], _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await wAsset0.approve(ch0.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await ch0.depositWrappedToken(accounts[1], _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
	});

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
		await ch1.withdrawAll(accounts[0], false);
		if (!caught) assert.fail('only whitelisted assets may be supplied');
	});

	it('opens vault', async () => {
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio)).toString();
		let caught = false;
		maxShortInterest0 = "0";
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
		var prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);

		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		assert.equal((await zcbAsset0.balanceOf(accounts[0])).toString(), amountBorrowed, "correct amount of zcb credited to vault owner");
		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.sub(_10To18), "correct amount of wAsset1 supplied");


		vaults = await vaultFactoryInstance.allVaults(accounts[0]);
		assert.equal(vaults.length, 1, "correct amount of vaults");
		vault = vaults[0];

		assert.equal(vault.assetSupplied, wAsset1.address, "correct address for assetSupplied in vault");
		assert.equal(vault.assetBorrowed, zcbAsset0.address, "correct address for assetBorrowed in vault");
		assert.equal(vault.amountSupplied.toString(), _10To18.toString(), "correct vaule of amountSupplied in vault");
		assert.equal(vault.amountBorrowed.toString(), amountBorrowed, "correct vaule of amountBorrowed in vault");
	});

	it('deposits into vault', async () => {
		var prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		prevSupplied = new BN(vaults[0].amountSupplied);
		await vaultFactoryInstance.deposit(accounts[0], 0, _10To18.toString());
		currentSupplied = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountSupplied);

		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.sub(_10To18).toString(), "correct amount of wAsset1 supplied");
		assert.equal(currentSupplied.sub(_10To18).toString(), prevSupplied.toString(), "correct increase in supplied asset in vault");
	});

	it('removes from vault', async () => {
		var toRemove = currentSupplied.sub(prevSupplied);
		var prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		prevSupplied = currentSupplied;

		await vaultHealthInstance.setToReturn(false);
		let caught = false;
		try {
			await vaultFactoryInstance.remove(0, toRemove.toString(), accounts[0], TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("call to remove() should fail when vaultWithstandsChange() returns false");

		await vaultHealthInstance.setToReturn(true);

		await vaultFactoryInstance.remove(0, toRemove.toString(), accounts[0], TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		currentSupplied = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountSupplied);
		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.add(toRemove), "correct amount of wAsset1 supplied");
		assert.equal(prevSupplied.sub(currentSupplied).toString(), toRemove.toString(), "correct increase in supplied asset in vault");
	});


	it('repays vault', async () => {
		toRepay = _10To18.div(new BN('2'));

		var prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		var prevBorrowed = new BN(vault.amountBorrowed);
		await vaultFactoryInstance.repay(accounts[0], 0, toRepay.toString());

		var currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		var currentBorrowed = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountBorrowed);
		assert.equal(prevBalanceZCB.sub(currentBalanceZCB).toString(), toRepay.toString(), "correct amount repaid");
		assert.equal(prevBorrowed.sub(currentBorrowed).toString(), toRepay.toString(), "correct amount repaid");
	});

	it('borrows from vault', async () => {
		toBorrow = toRepay;
		var prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		var prevBorrowed = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountBorrowed);
		await vaultFactoryInstance.borrow(0, toBorrow.toString(), accounts[0], TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		var currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		currentBorrowed = new BN((await vaultFactoryInstance.vaults(accounts[0], 0)).amountBorrowed);
		assert.equal(currentBalanceZCB.sub(prevBalanceZCB).toString(), toBorrow.toString(), "correct amount repaid");
		assert.equal(currentBorrowed.sub(prevBorrowed).toString(), toBorrow.toString(), "correct amount repaid");
	});

	it('send undercollateralised vaults to liquidation', async () => {
		/*
			increase collateralisation ratio limits such that the open vault will be sent to liquidation
		*/
		upperRatio = currentSupplied.mul(_10To18).div(currentBorrowed);
		await vaultHealthInstance.setUpper(asset1.address, zcbAsset0.address, upperRatio);

		let surplus = new BN("10000");
		bid = currentSupplied.sub(surplus);

		caught = false;
		try {
			await vaultFactoryInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, bid.toString(), currentBorrowed.toString(), {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation was triggered despite vault health being above upper limit");

		upperRatio = "16" + _10To18.toString().substring(2);
		await vaultHealthInstance.setUpper(asset1.address, zcbAsset0.address, upperRatio);

		let prevRevenue = await vaultFactoryInstance.revenue(wAsset1.address);
		
		let rec = await vaultFactoryInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, bid.toString(), currentBorrowed.toString(), {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let currentRevenue = await vaultFactoryInstance.revenue(wAsset1.address);

		let rebate = surplus.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasury = surplus.sub(rebate);
		assert.equal(currentRevenue.sub(prevRevenue).toString(), toTreasury.toString(), "correct amount of revenue");

		assert.equal((await vaultFactoryInstance.liquidationsLength()).toString(), "1", "correct length of liquidations array");

		liquidation = await vaultFactoryInstance.Liquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountBorrowed.toString(), currentBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await vaultFactoryInstance.vaults(accounts[0], 0);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('bid on liquidation auctions', async () => {
		/*
			bid with account 1
		*/
		let surplus = new BN("10");
		bid = bid.sub(surplus);
		
		let prevRevenue = await vaultFactoryInstance.revenue(wAsset1.address);

		let rec = await vaultFactoryInstance.bidOnLiquidation(0, bid.toString(), liquidation.amountBorrowed, {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let currentRevenue = await vaultFactoryInstance.revenue(wAsset1.address);

		let rebate = surplus.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasury = surplus.sub(rebate);
		assert.equal(currentRevenue.sub(prevRevenue).toString(), toTreasury.toString(), "correct amount of revenue");

		liquidation = await vaultFactoryInstance.Liquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountBorrowed.toString(), currentBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");
	});

	it('claim liquidation auction rewards', async () => {
		//go 10 minuites into the future to claim liquidation
		await helper.advanceTime(10*60 + 1);

		let prevBalW1 = await wAsset1.balanceOf(accounts[1]);

		await vaultFactoryInstance.claimLiquidation(0, accounts[1], {from: accounts[1]});

		let newBalW1 = await wAsset1.balanceOf(accounts[1]);

		assert.equal(newBalW1.sub(prevBalW1).toString(), liquidation.bidAmount.toString(), "correct payout after winning liquidation");
	});

	it('instant liquidations upon dropping below lowerCollateralLimit', async () => {
		/*
			first open vaults
		*/
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio)).sub(new BN(1)).toString();
		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		lowerRatio =  _10To18.mul(_10To18).div(new BN(amountBorrowed)).add(new BN(10000)).toString();
		await vaultHealthInstance.setLower(asset1.address, zcbAsset0.address, lowerRatio);

		vaultIndex = (await vaultFactoryInstance.vaultsLength(accounts[0])).toNumber() - 2;

		await vaultFactoryInstance.instantLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, amountBorrowed.toString(), _10To18.toString(), accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('partial vault liquidations Specific In', async () => {
		vaultIndex++;

		await vaultFactoryInstance.partialLiquidationSpecificIn(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address,
			(new BN(amountBorrowed)).div(new BN(2)).toString(), _10To18.div(new BN(3)).toString(), accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		assert.equal(vault.assetBorrowed, zcbAsset0.address, "assetBorrowed is correct");
		assert.equal(vault.assetSupplied, wAsset1.address, "assetSupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), (new BN(amountBorrowed)).div(new BN(2)).add(new BN(1)).toString(), "amountBorrowed is correct");
		assert.equal(vault.amountSupplied.toString(), _10To18.div(new BN(2)).add(new BN(1)).toString(), "amountSupplied is correct");
	});

	it('partial vault liquidation Specific Out', async () => {
		await vaultFactoryInstance.partialLiquidationSpecificOut(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address,
			vault.amountSupplied.toString(), vault.amountBorrowed.toString(), accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.vaults(accounts[0], vaultIndex);

		assert.equal(vault.assetBorrowed, zcbAsset0.address, "assetBorrowed is correct");
		assert.equal(vault.assetSupplied, wAsset1.address, "assetSupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is correct");
	});

	it('liquidates vaults due to time', async () => {
		let amountSupplied = _10To18;

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

		let rec = await vaultFactoryInstance.auctionLiquidation(accounts[0], vaultIndex, zcbAsset0.address, wAsset1.address, bid, amountBorrowed, {from: accounts[1]});
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		assert.equal((await vaultFactoryInstance.liquidationsLength()).toString(), "2", "correct length of liquidations array");

		liquidation = await vaultFactoryInstance.Liquidations(1);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountBorrowed.toString(), amountBorrowed.toString(), "correct value of liquidation.amountBorrowed");
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
		vaultIndex++;
		let caught = false;

		//change lower ratio so that vault is safe
		lowerRatio =  _10To18.mul(_10To18).div(new BN(amountBorrowed)).toString();
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
		let revenue = await vaultFactoryInstance.revenue(zcbAsset0.address);

		let prevBalance = await zcbAsset0.balanceOf(accounts[0]);

		await vaultFactoryInstance.claimRevenue(zcbAsset0.address);

		let newRevenue = await vaultFactoryInstance.revenue(zcbAsset0.address);

		let newBalance = await zcbAsset0.balanceOf(accounts[0]);

		assert.equal(newRevenue.toString(), "0", "revenue storage value reduced to 0 after all is withdrawn");
		assert.equal(newBalance.sub(prevBalance).toString(), revenue.toString(), "correct amount paid to contract owner");
	});



	/*
		-------------------------------------------------Y-T---V-a-u-l-t-s-----------------------------------------------------
	*/


	it('before YT testing', async () => {
		maturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

		let rec0 = await organizerInstance.deployCapitalHandlerInstance(wAsset0.address, maturity);
		let rec1 = await organizerInstance.deployCapitalHandlerInstance(wAsset1.address, maturity);

		//reset chs, zcbAssets, ytAssets with new assets that are yet to reach maturity
		ch0 = await capitalHandler.at(rec0.receipt.logs[0].args.addr);
		ch1 = await capitalHandler.at(rec1.receipt.logs[0].args.addr);

		zcbAsset0 = await IERC20.at(await ch0.zeroCouponBondAddress());
		zcbAsset1 = await IERC20.at(await ch1.zeroCouponBondAddress());

		ytAsset0 = await IYieldToken.at(await ch0.yieldTokenAddress());
		ytAsset1 = await IYieldToken.at(await ch1.yieldTokenAddress());

		await ch0.setVaultFactoryAddress(vaultFactoryInstance.address);
		await ch1.setVaultFactoryAddress(vaultFactoryInstance.address);

		//mint assets to account 0
		await asset1.mintTo(accounts[0], _10To18.mul(new BN("10")).toString());
		await asset1.approve(wAsset1.address, _10To18.mul(new BN("10")).toString());
		await wAsset1.depositUnitAmount(accounts[0], _10To18.mul(new BN("10")).toString());
		await wAsset1.approve(vaultFactoryInstance.address, _10To18.mul(new BN("10")).toString());
		await wAsset1.approve(ch1.address, _10To18.mul(new BN("10")).toString());
		await ch1.depositWrappedToken(accounts[0], _10To18.mul(new BN("10")).toString());
		await zcbAsset1.approve(vaultFactoryInstance.address, _10To18.mul(new BN("10")).toString());

		//mint assets to account 1
		await asset0.mintTo(accounts[1], _10To18.mul(new BN("10")).toString());
		await asset0.approve(wAsset0.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await wAsset0.depositUnitAmount(accounts[1], _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await wAsset0.approve(ch0.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await ch0.depositWrappedToken(accounts[1], _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
		await zcbAsset0.approve(vaultFactoryInstance.address, _10To18.mul(new BN("10")).toString(), {from: accounts[1]});
	});



	it('cannot open YT vault without whitelisting supplied asset', async () => {
		//mint ZCB to accounts[0]
		let toMint = _10To18.mul(new BN(10));
		await asset1.mintTo(accounts[0], toMint);
		await asset1.approve(wAsset1.address, toMint);
		await wAsset1.depositUnitAmount(accounts[0], toMint);
		let wBalance = await wAsset1.balanceOf(accounts[0]);
		await wAsset1.approve(ch1.address, wBalance);
		await ch1.depositWrappedToken(accounts[0], wBalance);
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
		await vaultFactoryInstance.whitelistCapitalHandler(ch1.address);
	});

	it('opens YT vault', async () => {
		let caught = false;
		maxShortInterest0 = "0";
		await vaultHealthInstance.setMaximumShortInterest(asset0.address, maxShortInterest0);
		//we are usign a dummy vault health contract, we need to set the value which it will return on vaultWithstandsChange() call
		await vaultHealthInstance.setToReturn(true);
		try {
			await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
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
			await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('open vault fails when vaultWithstandsChange() returns false');

		await vaultHealthInstance.setToReturn(true);
		caught = false;
		try {
			await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS-1, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful priceChange parameter must be >= TOTAL_BASIS_POINTS');

		caught = false;
		try {
			const over1ABDK = (new BN(ABDK_1)).add(new BN(1));
			await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, over1ABDK, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful suppliedRateChange parameter must be <= ABDK_1');

		caught = false;
		try {
			const over1ABDK = (new BN(ABDK_1)).add(new BN(1));
			await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, over1ABDK);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('for call to openVault(), remove(), or borrow() to be sucessful borrowedRateChange parameter must be <= ABDK_1');

		var prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		var prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		var prevYield1 = await ch1.balanceYield(accounts[0]);

		await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		assert.equal((await zcbAsset0.balanceOf(accounts[0])).toString(), prevBalanceZCB0.add(amountBorrowed).toString(), "correct amount of zcb credited to vault owner");
		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.sub(adjYieldSupplied).sub(bondSupplied).toString(), "correct amount of ZCB 1 supplied");
		assert.equal((await ch1.balanceYield(accounts[0])).toString(), prevYield1.sub(yieldSupplied).toString(), "correct new value of balanceYield");

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal(vault.CHsupplied, ch1.address, "correct address for assetSupplied in vault");
		assert.equal(vault.CHborrowed, ch0.address, "correct address for assetBorrowed in vault");
		assert.equal(vault.yieldSupplied.toString(), yieldSupplied.toString(), "correct vaule of yieldSupplied in vault");
		assert.equal(vault.bondSupplied.toString(), bondSupplied.toString(), "correct vaule of bondSupplied in vault");
		assert.equal(vault.amountBorrowed.toString(), amountBorrowed, "correct vaule of amountBorrowed in vault");
	});

	it('deposits into YT vault', async () => {
		var prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		var prevYield1 = await ch1.balanceYield(accounts[0]);
		prevVaultState = vault;
		let toSupplyYield = _10To18;
		let adjSuppliedYield = await wAsset1.WrappedAmtToUnitAmt_RoundDown(toSupplyYield);
		let toSupplyBond = _10To18.neg();
		await vaultFactoryInstance.YTdeposit(accounts[0], 0, toSupplyYield, toSupplyBond);
		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.sub(adjSuppliedYield).sub(toSupplyBond), "correct amount of ZCB supplied");
		assert.equal((await ch1.balanceYield(accounts[0])).toString(), prevYield1.sub(toSupplyYield).toString(), "correct amount of yield supplied");
	});

	it('removes from YT vault', async () => {
		var toRemove = currentSupplied.sub(prevSupplied);
		var prevBalanceZCB1 = await zcbAsset1.balanceOf(accounts[0]);
		var prevYield1 = await ch1.balanceYield(accounts[0]);
		prevVaultState = vault;
		let amountYield = _10To18;
		let adjAmountYield = await wAsset1.WrappedAmtToUnitAmt_RoundDown(amountYield);
		let amountBond = _10To18.neg();

		await vaultHealthInstance.setToReturn(false);
		let caught = false;
		try {
			await vaultFactoryInstance.YTremove(0, amountYield, amountBond, accounts[0], TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("call to remove() should fail when vaultWithstandsChange() returns false");

		await vaultHealthInstance.setToReturn(true);

		await vaultFactoryInstance.YTremove(0, amountYield, amountBond, accounts[0], TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal((await zcbAsset1.balanceOf(accounts[0])).toString(), prevBalanceZCB1.add(adjAmountYield).add(amountBond), "correct amount of ZCB received");
		assert.equal(prevVaultState.yieldSupplied.sub(vault.yieldSupplied).toString(), amountYield.toString(), "correct amount of yield removed from vault");
	});


	it('repays YT vault', async () => {
		toRepay = vault.amountBorrowed.div(new BN('2'));

		prevVaultState = vault;
		var prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		await vaultFactoryInstance.YTrepay(accounts[0], 0, toRepay);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);
		var currentBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		assert.equal(prevBalanceZCB0.sub(currentBalanceZCB0).toString(), toRepay.toString(), "correct amount ZCB transferedFrom sender");
		assert.equal(prevVaultState.amountBorrowed.sub(vault.amountBorrowed).toString(), toRepay.toString(), "correct amount repaid");
	});

	it('borrows from YT vault', async () => {
		toBorrow = toRepay;

		prevVaultState = vault;
		var prevBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);
		await vaultFactoryInstance.YTborrow(0, toBorrow, accounts[0], TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);
		var currentBalanceZCB0 = await zcbAsset0.balanceOf(accounts[0]);

		assert.equal(currentBalanceZCB0.sub(prevBalanceZCB0).toString(), toBorrow.toString(), "correct amount of borrowed asset transfered to _to");
		assert.equal(vault.amountBorrowed.sub(prevVaultState.amountBorrowed).toString(), toBorrow.toString(), "correct amount borrowed");
	});

	it('send undercollateralised YT vaults to liquidation', async () => {
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
			await vaultFactoryInstance.auctionYTLiquidation(accounts[0], 0, ch0.address, ch1.address, bid, minBondRatio, vault.amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation was triggered despite vault health being above upper limit");

		await vaultHealthInstance.setToReturn(false);

		let prevRevenue = await vaultFactoryInstance.YTrevenue(ch1.address);

		let rec = await vaultFactoryInstance.auctionYTLiquidation(accounts[0], 0, ch0.address, ch1.address, bid, minBondRatio, vault.amountBorrowed, {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let currentRevenue = await vaultFactoryInstance.YTrevenue(ch1.address);

		let rebateYield = surplusYield.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryYield = surplusYield.sub(rebateYield);

		let rebateBond = surplusBond.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryBond = surplusBond.sub(rebateBond).sub(new BN(1));

		assert.equal(currentRevenue.yield.sub(prevRevenue.yield).toString(), toTreasuryYield.toString(), "correct amount of yield revenue");
		assert.equal(currentRevenue.bond.sub(prevRevenue.bond).toString(), toTreasuryBond.toString(), "correct amount of bond revenue");

		assert.equal((await vaultFactoryInstance.YTLiquidationsLength()).toString(), "1", "correct length of liquidations array");

		liquidation = await vaultFactoryInstance.YTLiquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.CHborrowed, ch0.address, "correct value of liquidation.CHborrowed");
		assert.equal(liquidation.CHsupplied, ch1.address, "correct value of liquidation.CHsupplied");
		assert.equal(liquidation.amountBorrowed.toString(), vault.amountBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bondRatio.toString(), actualBondRatio.toString(), "correct value of liquidation.bondRatio");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 0);

		assert.equal(vault.CHborrowed, nullAddress, "CHborrowed is null");
		assert.equal(vault.CHsupplied, nullAddress, "CHsupplied is null");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is null");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
	});


	it('bid on YT liquidation auctions', async () => {
		/*
			bid with account 1
		*/
		let surplusYield = new BN("10");
		bid = bid.sub(surplusYield);
		bondCorrespondingToPrevBid = liquidation.bondRatio.mul(liquidation.bidAmount).div(_10To18);
		bondCorrespondingToBid = liquidation.bondRatio.mul(bid).div(_10To18).add(new BN(1));
		let surplusBond = bondCorrespondingToPrevBid.sub(bondCorrespondingToBid);

		let prevRevenue = await vaultFactoryInstance.YTrevenue(ch1.address);

		let rec = await vaultFactoryInstance.bidOnYTLiquidation(0, bid.toString(), liquidation.amountBorrowed, {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		let currentRevenue = await vaultFactoryInstance.YTrevenue(ch1.address);

		let rebateYield = surplusYield.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryYield = surplusYield.sub(rebateYield);

		let rebateBond = surplusBond.mul(new BN(rebate_bips)).div(new BN(TOTAL_BASIS_POINTS));
		let toTreasuryBond = surplusBond.sub(rebateBond);

		assert.equal(currentRevenue.yield.sub(prevRevenue.yield).toString(), toTreasuryYield.toString(), "correct amount of yield revenue");
		assert.equal(currentRevenue.bond.sub(prevRevenue.bond).toString(), toTreasuryBond.toString(), "correct amount of bond revenue");

		let prevBorrowed = liquidation.amountBorrowed;

		liquidation = await vaultFactoryInstance.YTLiquidations(0);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.CHborrowed, ch0.address, "correct value of liquidation.CHborrowed");
		assert.equal(liquidation.CHsupplied, ch1.address, "correct value of liquidation.CHsupplied");
		assert.equal(liquidation.amountBorrowed.toString(), prevBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bondRatio.toString(), actualBondRatio.toString(), "correct value of liquidation.bondRatio");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toNumber(), timestamp, "correct value of liqudiation.bidTimestamp");
	});


	it('claim YT liquidation auction rewards', async () => {
		//go 10 minuites into the future to claim liquidation
		await helper.advanceTime(10*60 + 1);

		let prevBalYield = await ch1.balanceYield(accounts[1]);
		let prevBalBonds = await ch1.balanceBonds(accounts[1]);

		await vaultFactoryInstance.claimYTLiquidation(0, accounts[1], {from: accounts[1]});

		let newBalYield = await ch1.balanceYield(accounts[1]);
		let newBalBonds = await ch1.balanceBonds(accounts[1]);

		let expectedBondChange = liquidation.bondRatio.sub(new BN(1)).mul(liquidation.bidAmount).div(_10To18);
		assert.equal(newBalYield.sub(prevBalYield).toString(), liquidation.bidAmount.toString(), "correct payout yield after winning YTLiquidation auction");
		assert.equal(newBalBonds.sub(prevBalBonds).toString(), expectedBondChange.toString(), "correct payout bond after winning YTLiquidation auction");
	});

	it('instant YT liquidations upon dropping below lowerCollateralLimit', async () => {
		/*
			first open vaults
		*/
		await vaultHealthInstance.setToReturn(true);
		yieldSupplied = _10To18;
		bondSupplied = _10To18.neg();
		amountBorrowed = _10To18;
		await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		minBondRatio = bondSupplied.mul(_10To18).div(yieldSupplied).sub(new BN(10));
		vaultIndex = (await vaultFactoryInstance.YTvaultsLength(accounts[0])).toNumber() - 2;
		let caught = false;
		try {
			await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, ch0.address, ch1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});
		}
		catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation tx should revert if vault is in good health");

		await vaultHealthInstance.setToReturn(false);
		await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, ch0.address, ch1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.CHborrowed, nullAddress, "CHborrowed is null");
		assert.equal(vault.CHsupplied, nullAddress, "CHsupplied is null");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is null");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
	});


	it('partial vault YT liquidations Specific In', async () => {
		vaultIndex++;
		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		let amtIn = vault.amountBorrowed.div(new BN(2));
		let expectedYieldOut = vault.yieldSupplied.mul(amtIn).div(vault.amountBorrowed);
		let expectedBondOut = vault.bondSupplied.mul(amtIn).div(vault.amountBorrowed);
		let minYieldOut = expectedYieldOut.sub(new BN(1));
		await vaultFactoryInstance.partialYTLiquidationSpecificIn(accounts[0], vaultIndex, ch0.address, ch1.address,
			amtIn, minYieldOut, minBondRatio, accounts[1], {from: accounts[1]});

		prevVaultState = vault;
		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.CHborrowed, ch0.address, "CHborrowed is correct");
		assert.equal(vault.CHsupplied, ch1.address, "CHsupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), prevVaultState.amountBorrowed.sub(amtIn).toString(), "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), prevVaultState.yieldSupplied.sub(expectedYieldOut).toString(), "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), prevVaultState.bondSupplied.sub(expectedBondOut).toString(), "bondSupplied is correct");
	});

	it('partial vault YT liquidation Specific Out', async () => {
		await vaultFactoryInstance.partialYTLiquidationSpecificOut(accounts[0], vaultIndex, ch0.address, ch1.address,
			vault.yieldSupplied, minBondRatio, vault.amountBorrowed, accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.CHborrowed, ch0.address, "CHborrowed is correct");
		assert.equal(vault.CHsupplied, ch1.address, "CHsupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is correct");
	});

	it('liquidates vaults due to time', async () => {
		//process.exit();
		let amountSupplied = _10To18;

		await vaultHealthInstance.setToReturn(true);
		await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);
		await vaultFactoryInstance.openYTVault(ch1.address, ch0.address, yieldSupplied, bondSupplied, amountBorrowed, TOTAL_BASIS_POINTS, ABDK_1, ABDK_1);

		vaultIndex = (await vaultFactoryInstance.YTvaultsLength(accounts[0])).toNumber() - 2;

		bid = amountSupplied;

		let caught = false;
		//test for when vaults are in good health
		await vaultHealthInstance.setToReturn(true);
		try {
			await vaultFactoryInstance.auctionYTLiquidation(accounts[0], vaultIndex, ch0.address, ch1.address, bid, minBondRatio, amountBorrowed, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was liquidated while above upper health limit before time liquidation period");


		/*
			advance 1 day to move into 7 day from maturity window
			this allows us to liquidate vaults on the premise of low time to maturity
		*/
		await helper.advanceTime(86401)

		let rec = await vaultFactoryInstance.auctionYTLiquidation(accounts[0], vaultIndex, ch0.address, ch1.address, bid, minBondRatio, amountBorrowed, {from: accounts[1]});
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		assert.equal((await vaultFactoryInstance.YTLiquidationsLength()).toString(), "2", "correct length of liquidations array");

		let expectedBondRatio = bondSupplied.mul(_10To18).div(yieldSupplied).add(new BN(1));

		liquidation = await vaultFactoryInstance.YTLiquidations(1);

		assert.equal(liquidation.vaultOwner, accounts[0], "correct value of liquidation.vaultOwner");
		assert.equal(liquidation.CHborrowed, ch0.address, "correct value of liquidation.CHborrowed");
		assert.equal(liquidation.CHsupplied, ch1.address, "correct value of liquidation.CHsupplied");
		assert.equal(liquidation.amountBorrowed.toString(), amountBorrowed.toString(), "correct value of liquidation.amountBorrowed");
		assert.equal(liquidation.bondRatio.toString(), expectedBondRatio.toString(), "correct value of liquidation.bondRatio")
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toString(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await vaultFactoryInstance.YTvaults(accounts[0], 1);

		assert.equal(vault.CHborrowed, nullAddress, "CHborrowed is null");
		assert.equal(vault.CHsupplied, nullAddress, "CHsupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is correct");
	});

	it('instant vault YT liquidations due to time to maturity', async () => {
		vaultIndex++;
		let caught = false;

		try {
			await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, ch0.address, ch1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was subject to instant liquidation with more than 1 day to maturity");

		/*
			first advance 6 days into future so that instant liquidations are allowed because of 1 day to maturity rule
		*/
		let _6days = _8days*3/4;
		await helper.advanceTime(_6days);

		await vaultFactoryInstance.instantYTLiquidation(accounts[0], vaultIndex, ch0.address, ch1.address, amountBorrowed, yieldSupplied, minBondRatio, accounts[1], {from: accounts[1]});

		vault = await vaultFactoryInstance.YTvaults(accounts[0], vaultIndex);

		assert.equal(vault.CHborrowed, nullAddress, "CHborrowed is correct");
		assert.equal(vault.CHsupplied, nullAddress, "CHsupplied is correct");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is correct");
		assert.equal(vault.yieldSupplied.toString(), "0", "yieldSupplied is correct");
		assert.equal(vault.bondSupplied.toString(), "0", "bondSupplied is correct");
	});


	it('contract owner withdraws YT revenue', async () => {
		let revenue = await vaultFactoryInstance.YTrevenue(ch1.address);

		let caught = false;
		let bondIn = "2";
		try {
			await vaultFactoryInstance.claimYTRevenue(ch1.address, bondIn, {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("only contract owner should be able to claim revenue");

		let prevBalanceYield = await ch1.balanceYield(accounts[0]);
		let prevBalanceBond = await ch1.balanceBonds(accounts[0]);

		await vaultFactoryInstance.claimYTRevenue(ch1.address, bondIn);

		let newRevenue = await vaultFactoryInstance.YTrevenue(ch1.address);

		let newBalanceYield = await ch1.balanceYield(accounts[0]);
		let newBalanceBond = await ch1.balanceBonds(accounts[0]);

		assert.equal(newRevenue.yield.toString(), "0", "revenue yield value reduced to 0 after all is withdrawn");
		assert.equal(newRevenue.bond.toString(), "0", "revenue bond value reduced to 0 after all is withdrawn");
		assert.equal(newBalanceYield.sub(prevBalanceYield).toString(), revenue.yield.toString(), "correct amount yield paid to contract owner");
		assert.equal(newBalanceBond.sub(prevBalanceBond).toString(), revenue.bond.toString(), "correct amount bond paid to contract owner");
	});

});