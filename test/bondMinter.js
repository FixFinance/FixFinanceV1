const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const aaveWrapper = artifacts.require('aaveWrapper');
const capitalHandler = artifacts.require('capitalHandler');
const yieldTokenDeployer = artifacts.require('yieldTokenDeployer');
const organizer = artifacts.require('organizer');
const BondMinter = artifacts.require('BondMinter');
const IERC20 = artifacts.require("IERC20");

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const _10To18 = (new BN('10')).pow(new BN('18'));

const _8days = 8*24*60*60;

contract('BondMinter', async function(accounts) {

	/* 
		for simplicity of testing in this contract we assume that 1 unit of each asset is equal in vaulue to 1 unit of any other asset
	*/


	it('before each', async () => {
		//borrow asset 0
		asset0 = await dummyAToken.new();
		//supply asset 1
		asset1 = await dummyAToken.new();
		yieldTokenDeployerInstance = await yieldTokenDeployer.new();
		vaultHealthInstance = await dummyVaultHealth.new();
		bondMinterInstance = await BondMinter.new(vaultHealthInstance.address);
		organizerInstance = await organizer.new(yieldTokenDeployerInstance.address, bondMinterInstance.address);

		maturity = ((await web3.eth.getBlock('latest')).timestamp + _8days).toString();

		await organizerInstance.deployATokenWrapper(asset0.address);
		await organizerInstance.deployATokenWrapper(asset1.address);
		await organizerInstance.deployCapitalHandlerInstance(asset0.address, maturity);
		await organizerInstance.deployCapitalHandlerInstance(asset1.address, maturity);

		wAsset0 = await aaveWrapper.at(await organizerInstance.aTokenWrappers(asset0.address));
		wAsset1 = await aaveWrapper.at(await organizerInstance.aTokenWrappers(asset1.address));

		await asset0.approve(wAsset0.address, _10To18.toString());
		await asset1.approve(wAsset1.address, _10To18.toString());

		await wAsset0.firstDeposit(accounts[0], _10To18.toString());
		await wAsset1.firstDeposit(accounts[0], _10To18.toString());

		zcbAsset0 = await capitalHandler.at(await organizerInstance.capitalHandlerMapping(asset0.address, maturity));
		zcbAsset1 = await capitalHandler.at(await organizerInstance.capitalHandlerMapping(asset1.address, maturity));

		await bondMinterInstance.setCapitalHandler(zcbAsset0.address);
		await bondMinterInstance.setCapitalHandler(zcbAsset1.address);

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

	it('assign ratios', async () => {
		//assign ratios in vault

		// asset0 Borrowed * ratio = asset1 Supplied
		// 1.4 * 10**18
		upperRatio = "14" + _10To18.toString().substring(2);
		await vaultHealthInstance.setUpper(wAsset1.address, zcbAsset0.address, upperRatio);

		// 1.2 * 10**18
		lowerRatio = "12" + _10To18.toString().substring(2);
		await vaultHealthInstance.setLower(wAsset1.address, zcbAsset0.address, lowerRatio);
	});

	it('opens vault', async () => {
		//set amount borrowed to 1 over the upper limit
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio)).add(new BN('1')).toString();
		let caught = false;
		try {
			await bondMinterInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail('borrowing must be limited by the upperRatio');

		amountBorrowed = (new BN(amountBorrowed)).sub(new BN('1')).toString();
		var prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);

		await bondMinterInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed);

		assert.equal((await zcbAsset0.balanceOf(accounts[0])).toString(), amountBorrowed, "correct amount of zcb credited to vault owner");
		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.sub(_10To18), "correct amount of wAsset1 supplied");


		vaults = await bondMinterInstance.allVaults(accounts[0]);
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
		await bondMinterInstance.deposit(accounts[0], 0, _10To18.toString());
		currentSupplied = new BN((await bondMinterInstance.vaults(accounts[0], 0)).amountSupplied);

		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.sub(_10To18).toString(), "correct amount of wAsset1 supplied");
		assert.equal(currentSupplied.sub(_10To18).toString(), prevSupplied.toString(), "correct increase in supplied asset in vault");
	});

	it('removes from vault', async () => {
		var toRemove = currentSupplied.sub(prevSupplied);
		var prevBalanceW1 = await wAsset1.balanceOf(accounts[0]);
		prevSupplied = currentSupplied;

		let caught = false;
		try {
			await bondMinterInstance.remove(0, toRemove.add(new BN('1')).toString(), accounts[0]);
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("collateral removal must be limited by the upperRatio");


		await bondMinterInstance.remove(0, toRemove.toString(), accounts[0]);

		currentSupplied = new BN((await bondMinterInstance.vaults(accounts[0], 0)).amountSupplied);
		assert.equal((await wAsset1.balanceOf(accounts[0])).toString(), prevBalanceW1.add(toRemove), "correct amount of wAsset1 supplied");
		assert.equal(prevSupplied.sub(currentSupplied).toString(), toRemove.toString(), "correct increase in supplied asset in vault");
	});


	it('repays vault', async () => {
		toRepay = _10To18.div(new BN('2'));

		var prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		var prevBorrowed = new BN(vault.amountBorrowed);
		await bondMinterInstance.repay(accounts[0], 0, toRepay.toString());

		var currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		var currentBorrowed = new BN((await bondMinterInstance.vaults(accounts[0], 0)).amountBorrowed);
		assert.equal(prevBalanceZCB.sub(currentBalanceZCB).toString(), toRepay.toString(), "correct amount repaid");
		assert.equal(prevBorrowed.sub(currentBorrowed).toString(), toRepay.toString(), "correct amount repaid");
	});

	it('borrows from vault', async () => {
		toBorrow = toRepay;
		var prevBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		var prevBorrowed = new BN((await bondMinterInstance.vaults(accounts[0], 0)).amountBorrowed);
		await bondMinterInstance.borrow(0, toBorrow.toString(), accounts[0]);

		var currentBalanceZCB = await zcbAsset0.balanceOf(accounts[0]);
		currentBorrowed = new BN((await bondMinterInstance.vaults(accounts[0], 0)).amountBorrowed);
		assert.equal(currentBalanceZCB.sub(prevBalanceZCB).toString(), toBorrow.toString(), "correct amount repaid");
		assert.equal(currentBorrowed.sub(prevBorrowed).toString(), toBorrow.toString(), "correct amount repaid");
	});

	it('send undercollateralised vaults to liquidation', async () => {
		/*
			increase collateralisation ratio limits such that the open vault will be sent to liquidation
		*/
		// 1.8 * 10**18
		upperRatio = "18" + _10To18.toString().substring(2);
		await vaultHealthInstance.setUpper(wAsset1.address, zcbAsset0.address, upperRatio);

		let caught = false;
		try {
			await bondMinterInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, currentBorrowed.toString(), currentSupplied.toString());
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidations should be dependant on lower ratio not upper ratio");

		// 1.6 * 10**18
		lowerRatio = "16" + _10To18.toString().substring(2);
		await vaultHealthInstance.setLower(wAsset1.address, zcbAsset0.address, lowerRatio);

		bid = currentBorrowed.sub(new BN("1"));

		caught = false;
		try {
			await bondMinterInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, bid.toString(), currentSupplied.toString());
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("liquidation was triggered despite vault health being above lower limit");

		bid = bid.add(new BN("1"));
		rec = await bondMinterInstance.auctionLiquidation(accounts[0], 0, zcbAsset0.address, wAsset1.address, bid.toString(), currentSupplied.toString());

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		assert.equal((await bondMinterInstance.liquidationsLength()).toString(), "1", "correct length of liquidations array");

		liquidation = await bondMinterInstance.Liquidations(0);

		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountSupplied.toString(), currentSupplied.toString(), "correct value of liquidation.amountSupplied");
		assert.equal(liquidation.bidder, accounts[0], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toString(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await bondMinterInstance.vaults(accounts[0], 0);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});

	it('bid on liquidation auctions', async () => {
		/*
			bid with account 1
		*/
		bid = bid.add(new BN('10'));
		
		rec = await bondMinterInstance.bidOnLiquidation(0, bid.toString(), {from: accounts[1]});

		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		liquidation = await bondMinterInstance.Liquidations(0);

		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountSupplied.toString(), currentSupplied.toString(), "correct value of liquidation.amountSupplied");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toString(), timestamp, "correct value of liqudiation.bidTimestamp");
	});

	it('claim liquidation auction rewards', async () => {
		//go 30 minuites into the future to claim liquidation
		await helper.advanceTime(30*60 + 1);

		let prevBalW1 = await wAsset1.balanceOf(accounts[1]);

		await bondMinterInstance.claimLiquidation(0, {from: accounts[1]});

		let newBalW1 = await wAsset1.balanceOf(accounts[1]);

		assert.equal(newBalW1.sub(prevBalW1).toString(), liquidation.amountSupplied);
	});

	it('liquidates vaults due to time', async () => {
		/*
			first open vaults
		*/
		amountBorrowed = _10To18.mul(_10To18).div(new BN(upperRatio)).toString();
		await bondMinterInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed);
		await bondMinterInstance.openVault(wAsset1.address, zcbAsset0.address, _10To18.toString(), amountBorrowed);

		bid = amountBorrowed;

		let caught = false;
		try {
			await bondMinterInstance.auctionLiquidation(accounts[0], 1, zcbAsset0.address, wAsset1.address, amountBorrowed.toString(), _10To18.toString(), {from: accounts[1]});
		} catch (err) {
			caught = true;
		}
		if (!caught) assert.fail("vault was liquidated while above lower and upper health limit and before time liquidation period");


		/*
			advance 1 day to move into 7 day from maturity window
			this allows us to liquidate vaults on the premise of low time to maturity
		*/
		await helper.advanceTime(86401)

		rec = await bondMinterInstance.auctionLiquidation(accounts[0], 1, zcbAsset0.address, wAsset1.address, amountBorrowed.toString(), _10To18.toString(), {from: accounts[1]});
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;

		assert.equal((await bondMinterInstance.liquidationsLength()).toString(), "2", "correct length of liquidations array");

		liquidation = await bondMinterInstance.Liquidations(1);

		assert.equal(liquidation.assetBorrowed, zcbAsset0.address, "correct value of liquidation.assetBorrowed");
		assert.equal(liquidation.assetSupplied, wAsset1.address, "correct value of liquidation.assetSupplied");
		assert.equal(liquidation.amountSupplied.toString(), currentSupplied.toString(), "correct value of liquidation.amountSupplied");
		assert.equal(liquidation.bidder, accounts[1], "correct value of liqudiation.bidder");
		assert.equal(liquidation.bidAmount.toString(), bid.toString(), "correct value of liquidation.bidAmount");
		assert.equal(liquidation.bidTimestamp.toString(), timestamp, "correct value of liqudiation.bidTimestamp");

		vault = await bondMinterInstance.vaults(accounts[0], 1);

		assert.equal(vault.assetBorrowed, nullAddress, "assetBorrowed is null");
		assert.equal(vault.assetSupplied, nullAddress, "assetSupplied is null");
		assert.equal(vault.amountBorrowed.toString(), "0", "amountBorrowed is null");
		assert.equal(vault.amountSupplied.toString(), "0", "amountSupplied is null");
	});


});