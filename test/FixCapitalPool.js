const dummyAToken = artifacts.require('dummyAToken');
const NGBwrapperDelegate1 = artifacts.require('NGBwrapperDelegate1');
const NGBwrapperDelegate2 = artifacts.require('NGBwrapperDelegate2');
const NGBwrapperDelegate3 = artifacts.require('NGBwrapperDelegate3');
const NGBwrapper = artifacts.require('NGBwrapper');
const FCPDelegate1 = artifacts.require('FCPDelegate1');
const fixCapitalPool = artifacts.require('FixCapitalPool');
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const InfoOracle = artifacts.require('InfoOracle');
const IERC20 = artifacts.require("IERC20");

const helper = require("../helper/helper.js");

const nullAddress = "0x0000000000000000000000000000000000000000";
const BN = web3.utils.BN;
const _10To18 = (new BN('10')).pow(new BN('18'));

const SBPSretained = 999_000;

contract('FixCapitalPool', async function(accounts){
	it('before each', async () => {
		sendTo = accounts[3];
		infoOracleInstance = await InfoOracle.new(0, sendTo);
		dummyATokenInstance = await dummyAToken.new("aCOIN");
		rewardsAsset0 = await dummyAToken.new("RWD0");
		rewardsAsset1 = await dummyAToken.new("RWD1");
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
		zcbYtDeployerInstance = await zcbYtDeployer.new();
		timeNow = (await web3.eth.getBlock('latest')).timestamp;
		fcpDelegate1Instance = await FCPDelegate1.new();
		fixCapitalPoolInstance = await fixCapitalPool.new(NGBwrapperInstance.address, timeNow+86400, zcbYtDeployerInstance.address, infoOracleInstance.address, fcpDelegate1Instance.address);
		inflation = await dummyATokenInstance.inflation();
		yieldTokenInstance = await IERC20.at(await fixCapitalPoolInstance.yieldTokenAddress());
		zcbInstance = await IERC20.at(await fixCapitalPoolInstance.zeroCouponBondAddress());
		await NGBwrapperInstance.addRewardAsset(rewardsAsset0.address);
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, _10To18);
		//wrap aTokens
		amount = '100000';
		await dummyATokenInstance.approve(NGBwrapperInstance.address, amount);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], amount);
	});

	it('deposits funds', async () => {
		await NGBwrapperInstance.approve(fixCapitalPoolInstance.address, amount);
		await fixCapitalPoolInstance.depositWrappedToken(accounts[0], amount);
		assert.equal((await fixCapitalPoolInstance.balanceYield(accounts[0])).toString(), amount, "correct balance yield for account 1");
	});

	it('has correct bond sending limits', async () => {
		amountPlusOne = '100001';
		caught = false;
		await zcbInstance.transfer(accounts[1], amountPlusOne).catch(() => {
			caught = true;
		}).then(() => {
			assert.equal(caught, true, "cannot send more bonds than one has collateral for");
		});
		await zcbInstance.transfer(accounts[1], amount);
		assert.equal((await fixCapitalPoolInstance.balanceBonds(accounts[0])).toString(), '-'+amount, "correct bond balance for account 0");
		assert.equal((await fixCapitalPoolInstance.balanceBonds(accounts[1])).toString(), amount, "correct bond balance for account 1");
		assert.equal((await zcbInstance.balanceOf(accounts[0])).toString(), '0', "correct val returned by minimumATokensAtMaturity()");
		assert.equal((await zcbInstance.balanceOf(accounts[1])).toString(), amount, "correct val returned by minimumATokensAtMaturity()");
		assert.equal((await fixCapitalPoolInstance.wrappedTokenFree(accounts[0])).toString(), '0', 'correct val returned by wrappedTokenFree()');
		assert.equal((await fixCapitalPoolInstance.wrappedTokenFree(accounts[1])).toString(), '0', 'correct val returned by wrappedTokenFree()');
	});

	it('gives yield to yield holder', async () => {
		//increase value of wrapped token by 2x
		//adjust for 10 bip deduction from fixCapitalPool
		adjustedInflation = inflation.add(inflation.mul(new BN(4)).div(new BN(5)));
		let yieldGenerated = (new BN(amount)).mul(adjustedInflation).div(_10To18).sub(new BN(amount)).toString();
		let expectedWrappedFree = (new BN(yieldGenerated)).mul(_10To18).div(adjustedInflation);
		inflation = inflation.mul(new BN(2));
		await dummyATokenInstance.setInflation(inflation.toString());
		assert.equal((await fixCapitalPoolInstance.balanceBonds(accounts[0])).toString(), '-'+amount, "correct bond balance for account 0");
		assert.equal((await zcbInstance.balanceOf(accounts[0])).toString(), yieldGenerated, "correct val returned by minimumATokensAtMaturity()");
		assert.equal((await fixCapitalPoolInstance.wrappedTokenFree(accounts[0])).toString(), expectedWrappedFree, 'correct val returned by wrappedTokenFree()');
	});

	it('withdraws funds unwrap:false', async () => {
		toWithdraw = (parseInt(amount)/8)+"";
		prevBalanceYield = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		await fixCapitalPoolInstance.withdraw(accounts[1], toWithdraw, false);
		assert.equal((await NGBwrapperInstance.balanceOf(accounts[1])).toString(), toWithdraw, "corect balance wrapped token for account 1");
		assert.equal((await fixCapitalPoolInstance.balanceYield(accounts[0])).toString(), prevBalanceYield.sub(new BN(toWithdraw)).toString(), "correct balance yield for account 0");
	});

	it('transfers yield', async () => {
		toTransferYield = (parseInt(amount)/8)+"";
		toTransferATkn = adjustedInflation.mul(new BN(toTransferYield)).div(_10To18).toString();
		prevBalanceBond = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		prevBalanceYield = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		prevBalanceOf = await zcbInstance.balanceOf(accounts[0]);
		await yieldTokenInstance.transfer(accounts[2], toTransferYield);
		let expectedBondChange = toTransferATkn;
		let expectedYieldChange = toTransferYield;
		let expectedBalance0 = prevBalanceOf.toString();
		assert.equal((await fixCapitalPoolInstance.balanceBonds(accounts[0])).sub(prevBalanceBond).toString(), expectedBondChange, "correct balance bonds account 0");
		assert.equal(prevBalanceYield.sub(await fixCapitalPoolInstance.balanceYield(accounts[0])).toString(), expectedYieldChange, "correct balance yield account 0")
		assert.equal((await zcbInstance.balanceOf(accounts[0])).toString(), expectedBalance0, "correct minimum aTkn balance at maturity account 0");
		assert.equal((await fixCapitalPoolInstance.balanceBonds(accounts[2])).toString(), "-"+toTransferATkn, "correct balance bonds account 2");
		assert.equal((await fixCapitalPoolInstance.balanceYield(accounts[2])).toString(), toTransferYield, "correct balance yield account 2");
		assert.equal((await zcbInstance.balanceOf(accounts[2])).toString(), "0", "correct minimum aTkn balance at maturity account 2");
	});

	it('withdraws funds unwrap:true', async () => {
		toWithdraw = (parseInt(amount)/8)+"";
		prevBalanceYield = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		await fixCapitalPoolInstance.withdraw(accounts[1], toWithdraw, true);
		expectedAToken = inflation.mul(new BN(toWithdraw)).div(_10To18);
		assert.equal((await dummyATokenInstance.balanceOf(accounts[1])).toString(), expectedAToken, "corect balance wrapped token for account 1");
		assert.equal((await fixCapitalPoolInstance.balanceYield(accounts[0])).toString(), prevBalanceYield.sub(new BN(toWithdraw)).toString(), "correct balance yield for account 0");		
		//because neglidgeble time has elapsed the actual fee in the wrapper contract is -
		//thus the ratio of wrapped to unwrapped asset is == inflation
		adjustedInflation = inflation;
	});

	it('cannot transfer too much yield', async () => {
		maxTransfer = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		caught = false;
		await yieldTokenInstance.transfer(accounts[1], maxTransfer.add(new BN("1")).toString()).catch(() => {
			caught = true;
		}).then(() => {
			assert.equal(caught, true, "cannot transfer more yield than the max amount of wrapped token free");
		});
		//transfer max amount
		await yieldTokenInstance.transfer(accounts[1], maxTransfer.toString());
		await yieldTokenInstance.transfer(accounts[0], maxTransfer.toString(), {from: accounts[1]});
	});

	it('FCP direct double claim, prior to payout phase from, transferPosition()', async () => {
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('3487'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedRewardsChange0 = rewardsAmt.mul(prevYield0).div(tsWrapper);
		let expectedRewardsChange1 = rewardsAmt.mul(prevYield1).div(tsWrapper);

		let amtYield = 1;
		let amtBond = 2;
		let rec = await fixCapitalPoolInstance.transferPosition(accounts[1], amtYield, amtBond);

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
	});

	it('FCP direct double claim, prior to payout phase from, transferPositionFrom()', async () => {
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('23874'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedRewardsChange0 = rewardsAmt.mul(prevYield0).div(tsWrapper);
		let expectedRewardsChange1 = rewardsAmt.mul(prevYield1).div(tsWrapper);

		let amtYield = 0;
		let amtBond = 2;
		await zcbInstance.approve(accounts[1], amtBond);
		let rec = await fixCapitalPoolInstance.transferPositionFrom(accounts[0], accounts[1], amtYield, amtBond, {from: accounts[1]});

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
	});

	it('FCP direct double claim, prior to payout phase from, transferZCB()', async () => {
		//before payout phase transferZCB should not claim sub account rewards
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);

		let rewardsAmt = _10To18.div(new BN('12342'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let amtZCB = 2;
		await zcbInstance.approve(accounts[1], amtZCB);
		let rec = await fixCapitalPoolInstance.transferZCB(accounts[0], accounts[1], amtZCB, {from: accounts[1]});

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		assert.equal(changeRewards0.toString(), "0", "transferZCB ought not claim sub account rewards before payout phase");
		assert.equal(changeRewards1.toString(), "0", "transferZCB ought not claim sub account rewards before payout phase");
	});

	it('FCP direct double claim, prior to payout phase from, transferYT()', async () => {
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('93274'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedRewardsChange0 = rewardsAmt.mul(prevYield0).div(tsWrapper);
		let expectedRewardsChange1 = rewardsAmt.mul(prevYield1).div(tsWrapper);

		let amtYT = 2;
		let rec = await fixCapitalPoolInstance.transferYT(accounts[0], accounts[1], amtYT);

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		assert.equal(await NGBwrapperInstance.hasClaimedAllYTRewards(fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address), false);
		assert.equal(await NGBwrapperInstance.hasClaimedAllYTRewards(fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address), false);
	});

	it('enters payout phase', async () => {
		assert.equal(await fixCapitalPoolInstance.inPayoutPhase(), false, "payout phase has not been entered yet");

		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		priorRewardsAmt = _10To18.div(new BN('28735'));
		let newCBal = priorRewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		await NGBwrapperInstance.addRewardAsset(rewardsAsset1.address);
		await rewardsAsset1.mintTo(NGBwrapperInstance.address, _10To18);
		await NGBwrapperInstance.forceRewardsCollection({from: accounts[5]}); //from account with no balance
		let expectedTRPWatMaturity = (await NGBwrapperInstance.totalRewardsPerWasset(1)).toString();
		assert.notEqual(expectedTRPWatMaturity, "0", "TRPW must be non 0");

		caught = false;
		await fixCapitalPoolInstance.enterPayoutPhase().catch(() => {
			caught = true;
		}).then(() => {
			assert.equal(caught, true, "cannot enter payout phase before maturity");
		});
		await helper.advanceTime(86400);
		await fixCapitalPoolInstance.enterPayoutPhase();
		assert.equal(await fixCapitalPoolInstance.inPayoutPhase(), true, "payout phase has been entered");
		caught = false;
		await fixCapitalPoolInstance.enterPayoutPhase().catch(() => {
			caught = true;
		}).then(() => {
			assert.equal(caught, true, "cannot enter payout phase after it has already been entered");
		});

		let TRPWatMaturity = (await fixCapitalPoolInstance.TotalRewardsPerWassetAtMaturity(1)).toString();
		assert.equal(TRPWatMaturity, expectedTRPWatMaturity, "correct TRPW at maturity for reward asset");
		maturityConversionRate = await fixCapitalPoolInstance.maturityConversionRate();
	});

	it('FCP direct double claim, in payout phase from, transferPositionFrom()', async () => {
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let prevBond0 = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevBond1 = await fixCapitalPoolInstance.balanceBonds(accounts[1]);
		let wrappedClaim0 = prevBond0.mul(_10To18).div(maturityConversionRate).add(prevYield0);
		let wrappedClaim1 = prevBond1.mul(_10To18).div(maturityConversionRate).add(prevYield1);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('23874'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedNewRewards0 = rewardsAmt.mul(wrappedClaim0).div(tsWrapper);
		let expectedNewRewards1 = rewardsAmt.mul(wrappedClaim1).div(tsWrapper);
		let expectedPriorRewards0 = priorRewardsAmt.mul(prevYield0).div(tsWrapper);
		let expectedPriorRewards1 = priorRewardsAmt.mul(prevYield1).div(tsWrapper);
		let expectedRewardsChange0 = expectedNewRewards0.add(expectedPriorRewards0);
		let expectedRewardsChange1 = expectedNewRewards1.add(expectedPriorRewards1);

		let amtYield = 0;
		let amtBond = 2;
		await zcbInstance.approve(accounts[1], amtBond);
		let rec = await fixCapitalPoolInstance.transferPositionFrom(accounts[0], accounts[1], amtYield, amtBond, {from: accounts[1]});

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(3)), -1, "error is within two units");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(3)), -1, "error is within two units");
		assert.equal(await NGBwrapperInstance.hasClaimedAllYTRewards(fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address), true);
		assert.equal(await NGBwrapperInstance.hasClaimedAllYTRewards(fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address), true);
	});

	it('FCP direct double claim, in payout phase from, transferPosition()', async () => {
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let prevBond0 = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevBond1 = await fixCapitalPoolInstance.balanceBonds(accounts[1]);
		let wrappedClaim0 = prevBond0.mul(_10To18).div(maturityConversionRate).add(prevYield0);
		let wrappedClaim1 = prevBond1.mul(_10To18).div(maturityConversionRate).add(prevYield1);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('98723'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedRewardsChange0 = rewardsAmt.mul(wrappedClaim0).div(tsWrapper);
		let expectedRewardsChange1 = rewardsAmt.mul(wrappedClaim1).div(tsWrapper);

		let amtYield = 1;
		let amtBond = 2;
		let rec = await fixCapitalPoolInstance.transferPosition(accounts[1], amtYield, amtBond);

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
	});

	it('FCP direct double claim, in payout phase from, transferZCB()', async () => {
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let prevBond0 = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevBond1 = await fixCapitalPoolInstance.balanceBonds(accounts[1]);
		let wrappedClaim0 = prevBond0.mul(_10To18).div(maturityConversionRate).add(prevYield0);
		let wrappedClaim1 = prevBond1.mul(_10To18).div(maturityConversionRate).add(prevYield1);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('34533'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedRewardsChange0 = rewardsAmt.mul(wrappedClaim0).div(tsWrapper);
		let expectedRewardsChange1 = rewardsAmt.mul(wrappedClaim1).div(tsWrapper);

		let amtZCB = 200;
		let rec = await fixCapitalPoolInstance.transferZCB(accounts[0], accounts[1], amtZCB);

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
	});

	it('FCP direct double claim, in payout phase from, transferYT()', async () => {
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[0], fixCapitalPoolInstance.address);
		await NGBwrapperInstance.forceClaimSubAccountRewards(true, fixCapitalPoolInstance.address, accounts[1], fixCapitalPoolInstance.address, {from: accounts[1]});
		let prevRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let prevRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let prevYield0 = await fixCapitalPoolInstance.balanceYield(accounts[0]);
		let prevYield1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let prevBond0 = await fixCapitalPoolInstance.balanceBonds(accounts[0]);
		let prevBond1 = await fixCapitalPoolInstance.balanceBonds(accounts[1]);
		let wrappedClaim0 = prevBond0.mul(_10To18).div(maturityConversionRate).add(prevYield0);
		let wrappedClaim1 = prevBond1.mul(_10To18).div(maturityConversionRate).add(prevYield1);
		let tsWrapper = await NGBwrapperInstance.totalSupply();

		let rewardsAmt = _10To18.div(new BN('43287'));
		let newCBal = rewardsAmt.add(await rewardsAsset0.balanceOf(NGBwrapperInstance.address));
		await rewardsAsset0.mintTo(NGBwrapperInstance.address, newCBal);

		let expectedRewardsChange0 = rewardsAmt.mul(wrappedClaim0).div(tsWrapper);
		let expectedRewardsChange1 = rewardsAmt.mul(wrappedClaim1).div(tsWrapper);

		let amtYT = 2;
		let rec = await fixCapitalPoolInstance.transferYT(accounts[0], accounts[1], amtYT);

		let newRewardsBal0 = await rewardsAsset0.balanceOf(accounts[0]);
		let newRewardsBal1 = await rewardsAsset0.balanceOf(accounts[1]);
		let changeRewards0 = newRewardsBal0.sub(prevRewardsBal0);
		let changeRewards1 = newRewardsBal1.sub(prevRewardsBal1);

		let err = expectedRewardsChange0.sub(changeRewards0);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
		err = expectedRewardsChange1.sub(changeRewards1);
		assert.equal(err.cmp(new BN(-1)), 1, "actual rewards is not greater than the expected");
		assert.equal(err.cmp(new BN(2)), -1, "error is within one unit");
	});

	it('does not reward bond sellers with yield after payout', async () => {
		minATknAtMaturity = await zcbInstance.balanceOf(accounts[0]);
		postMaturityInflation = _10To18.mul(new BN(2));
		inflation = inflation.mul(postMaturityInflation).div(_10To18);
		await dummyATokenInstance.setInflation(inflation.toString());
		assert.equal((await zcbInstance.balanceOf(accounts[0])).toString(), minATknAtMaturity,
			"yield holders not rewarded by yield generated on lent out funds after maturity");
	});

	it('ZCB holders capture yield generated after maturity', async () => {
		let yieldBalAct1 = await fixCapitalPoolInstance.balanceYield(accounts[1]);
		let bondBalAct1 = await fixCapitalPoolInstance.balanceBonds(accounts[1]);
		let prevATknBal2 = await dummyATokenInstance.balanceOf(accounts[2]);
		/*
			On call to withdraw harvestToTreasury() is called, because neglidgeble time has
			passed no funds will go to the treasury. thus we do not need to adjust post
			maturity inflation in our calculations below
		*/
		let expectedWrappedOut = yieldBalAct1.add(bondBalAct1.mul(_10To18).div(maturityConversionRate));
		let expectedUnderlyingOut = expectedWrappedOut.mul(inflation).div(_10To18);
		let expectedPayout = expectedUnderlyingOut;
		await fixCapitalPoolInstance.claimBondPayout(accounts[2], true, {from: accounts[1]});

		let aTknBal2 = await dummyATokenInstance.balanceOf(accounts[2]);
		assert.equal((await fixCapitalPoolInstance.balanceBonds(accounts[1])).toString(), '0', "balance bond set to 0");
		assert.equal((await fixCapitalPoolInstance.balanceYield(accounts[1])).toString(), '0', "balance yield set to 0");
		assert.equal(aTknBal2.sub(prevATknBal2).toString(), expectedPayout.toString(), "correct payout of long bond tokens");
	});

	it('contract can repay all obligations', async () => {
		for (let i = 0; i < accounts.length; i++) {
			await fixCapitalPoolInstance.claimBondPayout(nullAddress, i%2==0, {from: accounts[i]});
		}
	});

});
