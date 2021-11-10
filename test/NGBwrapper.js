const dummyAToken = artifacts.require('dummyAToken');
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapper = artifacts.require('NGBwrapper');
const InfoOracle = artifacts.require('InfoOracle');

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const _10To18 = (new BN('10')).pow(new BN('18'));

let helper = require('../helper/helper.js');

const secondsPerYear = 31556926;
const ErrorRange = Math.pow(10,-9);
const annualFee = 0.001;
const annualRetention = 1 - annualFee;

const SBPSretained = 999_000;

const _1Month = 31*24*60*60;

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

contract('NGBwrapper', async function(accounts){
	it('before each', async () => {
		dummyATokenInstance = await dummyAToken.new("DMY");
		rewardsAsset = await dummyAToken.new("RWD");
		owner = accounts[4];
		infoOracleInstance = await InfoOracle.new(owner, true);
		ngbwDelegate1Instance = await NGBwrapperDelegate1.new();
		ngbwDelegate2Instance = await NGBwrapperDelegate2.new();
		ngbwDelegate3Instance = await NGBwrapperDelegate3.new();
		NGBwrapperInstance = await NGBwrapper.new(
			dummyATokenInstance.address,
			infoOracleInstance.address,
			ngbwDelegate1Instance.address,
			ngbwDelegate2Instance.address,
			ngbwDelegate3Instance.address,
			SBPSretained
		);
		inflation = await dummyATokenInstance.inflation();
		treasuryAddress = owner;
		await NGBwrapperInstance.transferOwnership(treasuryAddress);
		await dummyATokenInstance.mintTo(accounts[0], _10To18.mul(new BN(100)));
		assert.equal(await NGBwrapperInstance.underlyingAssetAddress(), dummyATokenInstance.address, 'correct address for aToken');
		assert.equal((await NGBwrapperInstance.totalSupply()).toString(), "0", "correct total supply");
	});

	it('executes 1st deposit', async () => {
		amount = _10To18.toString();
		await dummyATokenInstance.approve(NGBwrapperInstance.address, amount);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], amount);
		totalSupply = await NGBwrapperInstance.totalSupply();
		assert.equal(totalSupply.toString(), amount, "correct total supply after 1st deposit");
		assert.equal((await NGBwrapperInstance.balanceOf(accounts[0])).toString(), amount, "correct balance of account 0 after 1st deposit");
		assert.equal((await NGBwrapperInstance.prevRatio()).toString(), _10To18.toString(), "correct value of prevRatio");
	});

	it('executes standard deposits', async () => {
		await helper.advanceTime(_1Month);
		inflation = inflation.mul(new BN(2));
		await dummyATokenInstance.setInflation(inflation.toString());
		await dummyATokenInstance.approve(NGBwrapperInstance.address, amount);
		let lastHarvest = (await NGBwrapperInstance.lastHarvest()).toNumber();
		let rec = await NGBwrapperInstance.depositUnitAmount(accounts[1], amount);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let yearsElapsed = (timestamp-lastHarvest)/secondsPerYear;
		let pctRetained = Math.pow(annualRetention, yearsElapsed);
		let supplyInflation = 1/pctRetained;
		expectedBalanceIncrease = (new BN(amount)).div(new BN(2));
		prevTotalSupply = totalSupply;
		totalSupply = await NGBwrapperInstance.totalSupply();
		let actual = totalSupply.toString();
		let expected = parseInt(prevTotalSupply.add(expectedBalanceIncrease).toString())*supplyInflation;
		assert.isBelow(AmountError(actual, expected), ErrorRange, "total supply after standard deposit is within acceptable range of error");
		actual = (await NGBwrapperInstance.balanceOf(accounts[1])).toString();
		expected = parseInt((new BN(amount)).div(new BN(2)).toString())*supplyInflation;
		assert.isBelow(AmountError(actual, expected), ErrorRange, "balance of account 1 within acceptable range of error");
	});

	it('executes withdrawWrappedToken', async () => {
		await helper.advanceTime(_1Month);
		inflation = inflation.mul(new BN(3));
		await dummyATokenInstance.setInflation(inflation.toString());
		toWithdraw = (new BN(amount)).div(new BN(2));
		let lastHarvest = (await NGBwrapperInstance.lastHarvest()).toNumber();
		let rec = await NGBwrapperInstance.withdrawWrappedAmount(accounts[1], toWithdraw.toString(), true);
		let timestamp = (await web3.eth.getBlock(rec.receipt.blockNumber)).timestamp;
		let yearsElapsed = (timestamp-lastHarvest)/secondsPerYear;
		let pctRetained = Math.pow(annualRetention, yearsElapsed);
		let supplyInflation = 1/pctRetained;
		prevTotalSupply = totalSupply;
		totalSupply = await NGBwrapperInstance.totalSupply();
		wrappedBalanceAct0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		let expected = parseInt(prevTotalSupply.toString())*supplyInflation - parseInt(toWithdraw.toString());
		let actual = totalSupply.toString();
		assert.isBelow(AmountError(actual, expected), ErrorRange, "total supply after withdrawWrappedToken() in range of acceptable error");
		assert.equal(wrappedBalanceAct0.toString(), (new BN(amount)).sub(toWithdraw).toString(), "correct balance wrapped tokens for account 0");
		let contractBalance = await dummyATokenInstance.balanceOf(NGBwrapperInstance.address);
		expected = toWithdraw.mul(contractBalance).div(totalSupply).toString();
		actual = (await dummyATokenInstance.balanceOf(accounts[1])).toString();
		assert.isBelow(AmountError(expected, actual), ErrorRange, "correct aToken balance for account");
	});

	it('executes withdrawAToken', async () => {
		await helper.advanceTime(_1Month);
		toWithdraw = new BN(amount);
		let rec = await NGBwrapperInstance.withdrawUnitAmount(accounts[2], toWithdraw.toString(), true);
		let prevRatio = await NGBwrapperInstance.prevRatio();
		expectedWrappedTokenDecrease = toWithdraw.mul(_10To18);
		expectedWrappedTokenDecrease = expectedWrappedTokenDecrease.div(prevRatio).add(new BN(expectedWrappedTokenDecrease.mod(prevRatio).toString() == "0" ? 0 : 1));
		prevTotalSupply = totalSupply;
		totalSupply = await NGBwrapperInstance.totalSupply();
		prevWrappedBalanceAct0 = wrappedBalanceAct0;
		wrappedBalanceAct0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		let actual = totalSupply.toString();
		let expected = prevTotalSupply.sub(expectedWrappedTokenDecrease).toString();
		assert.equal(actual, expected, "correct total supply after withdrawAToken() call");
		assert.equal(wrappedBalanceAct0.toString(), prevWrappedBalanceAct0.sub(expectedWrappedTokenDecrease).toString(), "correct balance wrapped token account 0");
		aTknBalAct2 = await dummyATokenInstance.balanceOf(accounts[2]);
		//inflation is 6*10**18 thus we can expect the range abs of the error in the balance of account[2] to be less than 6
		assert.equal(aTknBalAct2.sub(toWithdraw).abs().cmp(new BN(6)) == -1, true, "balance is within acceptable range of error")
	});

	it('Starts with no reward assets', async () => {
		assert.equal((await NGBwrapperInstance.numRewardsAssets()).toString(), "0");
	});

	it('Add reward asset', async () => {
		await NGBwrapperInstance.addRewardAsset(rewardsAsset.address, {from: owner});
		assert.equal((await NGBwrapperInstance.numRewardsAssets()).toString(), "1");
		assert.equal(await NGBwrapperInstance.rewardsAssets(0), rewardsAsset.address);
		assert.equal(await NGBwrapperInstance.immutableRewardsAssets(0), rewardsAsset.address);
		assert.equal((await NGBwrapperInstance.prevContractBalance(0)).toString(), "0");
		assert.equal((await NGBwrapperInstance.totalRewardsPerWasset(0)).toString(), "0");
	});

	it('Cannot add same reward asset again', async () => {
		let caught = false;
		try {
			await NGBwrapperInstance.addRewardAsset(rewardsAsset.address, {from: owner});
		} catch (err) {
			caught = true;
		}
		if (!caught) {
			assert.fail('Managed to add same reward asset twice');
		}
	});

	it('delist and relist reward assets', async () => {
		let mintAmt = _10To18.div(new BN(872).add(new BN(4392)));
		let newCBal = mintAmt.add(await rewardsAsset.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset.mintTo(NGBwrapperInstance.address, newCBal);

		await NGBwrapperInstance.forceRewardsCollection(); //from accounts[0]
		let prevTRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		let prevTRPWuponActivation = await NGBwrapperInstance.totalRewardsPerWassetUponActivation(0);
		assert.equal(prevTRPWuponActivation.toString(), "0");
		assert.notEqual(prevTRPWuponActivation.toString(), prevTRPW.toString());
		await NGBwrapperInstance.deactivateRewardAsset(0, {from: owner});
		let mutableRewardsAsset0 = await NGBwrapperInstance.rewardsAssets(0);
		assert.equal(mutableRewardsAsset0, nullAddress);
		await NGBwrapperInstance.reactivateRewardAsset(0, {from: owner});
		let TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		TRPWuponActivation = await NGBwrapperInstance.totalRewardsPerWassetUponActivation(0);
		assert.equal(TRPWuponActivation.toString(), TRPW.toString());

		mintAmt = _10To18.div(new BN(3645).add(new BN(6435)));
		newCBal = mintAmt.add(await rewardsAsset.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset.mintTo(NGBwrapperInstance.address, newCBal);
		let ts = await NGBwrapperInstance.totalSupply();
		let bal0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		let prevRewardsBal0 = await rewardsAsset.balanceOf(accounts[0]);
		await NGBwrapperInstance.forceRewardsCollection(); //from accounts[0]
		let rewardsBal0 = await rewardsAsset.balanceOf(accounts[0]);
		let rewardsChange0 = rewardsBal0.sub(prevRewardsBal0);
		let expectedRewardsChange = mintAmt.mul(bal0).div(ts);
		TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		TRPWuponActivation = await NGBwrapperInstance.totalRewardsPerWassetUponActivation(0);
		assert.equal(rewardsChange0.toString(), expectedRewardsChange.toString());
		assert.equal(TRPW.cmp(TRPWuponActivation), 1);
	});

	it('correct reward asset dividends, on transfer', async () => {
		let bal0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		let bal2 = await NGBwrapperInstance.balanceOf(accounts[2]);
		let ts = await NGBwrapperInstance.totalSupply();
		await rewardsAsset.mintTo(accounts[0], "0"); //set balance to 0
		await rewardsAsset.mintTo(accounts[2], "0"); //set balance to 0

		let mintAmt = _10To18.div(new BN(757).add(new BN(23478)));
		let newCBal = mintAmt.add(await rewardsAsset.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset.mintTo(NGBwrapperInstance.address, newCBal);

		let prevContractTRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		let transferAmt = bal0.div(new BN(3));
		await NGBwrapperInstance.transfer(accounts[2], bal0.sub(transferAmt), {from: accounts[0]})

		let rBal0 = await rewardsAsset.balanceOf(accounts[0]);
		let rBal2 = await rewardsAsset.balanceOf(accounts[2]);

		let expectedRBal0 = mintAmt.mul(bal0).div(ts);
		let expectedRBal2 = mintAmt.mul(bal2).div(ts);

		assert.equal(rBal0.toString(), expectedRBal0.toString());
		assert.equal(rBal2.toString(), expectedRBal2.toString());

		let expectedContractBalance = newCBal.sub(rBal0).sub(rBal2);
		let expectedTRPW = mintAmt.mul(_10To18).div(totalSupply).add(prevContractTRPW);
		let prevTRPW0 = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[0]);
		let prevTRPW2 = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[2]);
		let TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		let prevContractBalance = await NGBwrapperInstance.prevContractBalance(0);

		assert.equal(prevContractBalance.toString(), expectedContractBalance.toString());
		assert.equal(TRPW.toString(), expectedTRPW.toString());
		assert.equal(prevTRPW0.toString(), expectedTRPW.toString());
		assert.equal(prevTRPW2.toString(), expectedTRPW.toString());

		tally = rBal0.add(rBal2);
	});

	it('correct reward asset dividends, on withdraws', async () => {
		let bal0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		let bal1 = await NGBwrapperInstance.balanceOf(accounts[1]);
		let bal2 = await NGBwrapperInstance.balanceOf(accounts[2]);
		let bal4 = await NGBwrapperInstance.balanceOf(accounts[4]);
		let prevRBal0 = await rewardsAsset.balanceOf(accounts[0]);
		let prevRBal1 = await rewardsAsset.balanceOf(accounts[1]);
		let prevRBal2 = await rewardsAsset.balanceOf(accounts[2]);
		let prevRBal4 = await rewardsAsset.balanceOf(accounts[4]);
		let ts = await NGBwrapperInstance.totalSupply();
		let mintAmt = _10To18.div(new BN(872).add(new BN(4392)));
		let prevTRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);

		let newCBal = mintAmt.add(await rewardsAsset.balanceOf(NGBwrapperInstance.address));
		let additionalRPW = mintAmt.mul(_10To18).div(ts);
		let expectedTRPW = prevTRPW.add(additionalRPW);

		await rewardsAsset.mintTo(NGBwrapperInstance.address, newCBal);

		let specificPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[0]);
		let rpw = expectedTRPW.sub(BN.max(specificPrevTRPW, TRPWuponActivation));
		await NGBwrapperInstance.withdrawWrappedAmount(accounts[0], bal0, true, {from: accounts[0]});
		let TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		let userPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[0]);
		let rBal0 = await rewardsAsset.balanceOf(accounts[0]);
		let expectedDividend0 = rpw.mul(bal0).div(_10To18);
		let prevContractBalance = newCBal;
		let contractBalance = await NGBwrapperInstance.prevContractBalance(0);
		assert.equal(contractBalance.toString(), prevContractBalance.sub(expectedDividend0).toString());
		assert.equal(TRPW.toString(), expectedTRPW.toString());
		assert.equal(userPrevTRPW.toString(), expectedTRPW.toString());
		assert.equal(rBal0.sub(prevRBal0).toString(), expectedDividend0.toString());

		specificPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[1]);
		rpw = expectedTRPW.sub(BN.max(specificPrevTRPW, TRPWuponActivation));
		await NGBwrapperInstance.withdrawWrappedAmount(accounts[1], bal1, true, {from: accounts[1]});
		TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		userPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[1]);
		let rBal1 = await rewardsAsset.balanceOf(accounts[1]);
		let expectedDividend1 = rpw.mul(bal1).div(_10To18);
		prevContractBalance = contractBalance;
		contractBalance = await NGBwrapperInstance.prevContractBalance(0);
		assert.equal(contractBalance.toString(), prevContractBalance.sub(expectedDividend1).toString());
		assert.equal(TRPW.toString(), expectedTRPW.toString());
		assert.equal(userPrevTRPW.toString(), expectedTRPW.toString());
		assert.equal(rBal1.sub(prevRBal1).toString(), expectedDividend1.toString());

		specificPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[2]);
		rpw = expectedTRPW.sub(BN.max(specificPrevTRPW, TRPWuponActivation));
		await NGBwrapperInstance.withdrawWrappedAmount(accounts[2], bal2, true, {from: accounts[2]});
		TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		userPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[2]);
		let rBal2 = await rewardsAsset.balanceOf(accounts[2]);
		let expectedDividend2 = rpw.mul(bal2).div(_10To18);
		prevContractBalance = contractBalance;
		contractBalance = await NGBwrapperInstance.prevContractBalance(0);
		assert.equal(contractBalance.toString(), prevContractBalance.sub(expectedDividend2).toString());
		assert.equal(TRPW.toString(), expectedTRPW.toString());
		assert.equal(userPrevTRPW.toString(), expectedTRPW.toString());
		assert.equal(rBal2.sub(prevRBal2).toString(), expectedDividend2.toString());

		specificPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[4]);
		rpw = expectedTRPW.sub(BN.max(specificPrevTRPW, TRPWuponActivation));
		await NGBwrapperInstance.withdrawWrappedAmount(accounts[4], bal4, true, {from: accounts[4]});
		TRPW = await NGBwrapperInstance.totalRewardsPerWasset(0);
		userPrevTRPW = await NGBwrapperInstance.prevTotalRewardsPerWasset(0, accounts[4]);
		let rBal4 = await rewardsAsset.balanceOf(accounts[4]);
		let expectedDividend4 = rpw.mul(bal4).div(_10To18);
		prevContractBalance = contractBalance;
		contractBalance = await NGBwrapperInstance.prevContractBalance(0);
		assert.equal(contractBalance.toString(), prevContractBalance.sub(expectedDividend4).toString());
		assert.equal(TRPW.toString(), expectedTRPW.toString());
		assert.equal(userPrevTRPW.toString(), expectedTRPW.toString());
		assert.equal(rBal4.sub(prevRBal4).toString(), expectedDividend4.toString());

		assert.isBelow(contractBalance.toNumber(), 7);
	});
});