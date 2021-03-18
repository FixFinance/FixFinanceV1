const dummyAToken = artifacts.require('dummyAToken');
const NGBwrapper = artifacts.require('NGBwrapper');
const capitalHandler = artifacts.require('CapitalHandler');
const BN = web3.utils.BN;
const _10To18 = (new BN('10')).pow(new BN('18'));

let helper = require('../helper/helper.js');

const ErrorRange = Math.pow(10,-7);
const TreasuryErrorRange = Math.pow(10, -5);

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
		NGBwrapperInstance = await NGBwrapper.new(dummyATokenInstance.address);
		inflation = await dummyATokenInstance.inflation();
		treasuryAddress = await NGBwrapperInstance.treasuryAddress();
		assert.equal(await NGBwrapperInstance.underlyingAssetAddress(), dummyATokenInstance.address, 'correct address for aToken');
		assert.equal((await NGBwrapperInstance.totalSupply()).toString(), "0", "correct total supply");
	});

	it('executes 1st deposit', async () => {
		amount = _10To18.div(new BN(100)).toString();
		await dummyATokenInstance.approve(NGBwrapperInstance.address, amount);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], amount);
		totalSupply = await NGBwrapperInstance.totalSupply();
		assert.equal(totalSupply.toString(), amount, "correct total supply after 1st deposit");
		assert.equal((await NGBwrapperInstance.balanceOf(accounts[0])).toString(), amount, "correct balance of account 0 after 1st deposit");
		assert.equal((await NGBwrapperInstance.prevRatio()).toString(), _10To18.toString(), "correct value of prevRatio");
	});

	it('executes standard deposits', async () => {
		inflation = inflation.mul(new BN(2));
		await dummyATokenInstance.setInflation(inflation.toString());
		await dummyATokenInstance.approve(NGBwrapperInstance.address, amount);
		await NGBwrapperInstance.depositUnitAmount(accounts[1], amount);
		expectedBalanceIncrease = (new BN(amount)).div(new BN(2));
		prevTotalSupply = totalSupply;
		totalSupply = await NGBwrapperInstance.totalSupply();
		assert.equal(totalSupply.toString(), prevTotalSupply.add(expectedBalanceIncrease).toString(), "correct total supply after standard deposit");
		assert.equal((await NGBwrapperInstance.balanceOf(accounts[1])).toString(), (new BN(amount)).div(new BN(2)).toString(), "correct balance account 1");
	});

	it('executes withdrawWrappedToken', async () => {
		inflation = inflation.mul(new BN(3));
		await dummyATokenInstance.setInflation(inflation.toString());
		toWithdraw = (new BN(amount)).div(new BN(2));
		await NGBwrapperInstance.withdrawWrappedAmount(accounts[1], toWithdraw.toString());
		prevTotalSupply = totalSupply;
		totalSupply = await NGBwrapperInstance.totalSupply();
		wrappedBalanceAct0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		assert.equal(totalSupply.toString(), prevTotalSupply.sub(toWithdraw).toString(), "correct total supply after withdrawWrappedToken() call");
		assert.equal(wrappedBalanceAct0.toString(), (new BN(amount)).sub(toWithdraw).toString(), "correct balance wrapped tokens for account 0");
		let expected = inflation.mul(toWithdraw).div(_10To18).toString();
		let actual = (await dummyATokenInstance.balanceOf(accounts[1])).toString();
		assert.isBelow(AmountError(expected, actual), ErrorRange, "correct aToken balance for account");
	});

	it('executes withdrawAToken', async () => {
		toWithdraw = new BN(amount);
		await NGBwrapperInstance.withdrawUnitAmount(accounts[2], toWithdraw.toString());
		expectedWrappedTokenDecrease = toWithdraw.mul(_10To18);
		expectedWrappedTokenDecrease = expectedWrappedTokenDecrease.div(inflation).add(new BN(expectedWrappedTokenDecrease.mod(inflation).toString() == "0" ? 0 : 1));
		prevTotalSupply = totalSupply;
		totalSupply = await NGBwrapperInstance.totalSupply();
		prevWrappedBalanceAct0 = wrappedBalanceAct0;
		wrappedBalanceAct0 = await NGBwrapperInstance.balanceOf(accounts[0]);
		assert.equal(totalSupply.toString(), prevTotalSupply.sub(expectedWrappedTokenDecrease).toString(), "correct total supply after withdrawAToken() call");
		assert.equal(wrappedBalanceAct0.toString(), prevWrappedBalanceAct0.sub(expectedWrappedTokenDecrease).toString(), "correct balance wrapped token account 0");
		aTknBalAct2 = await dummyATokenInstance.balanceOf(accounts[2]);
		//inflation is 6*10**18 thus we can expect the range abs of the error in the balance of account[2] to be less than 6
		assert.equal(aTknBalAct2.sub(toWithdraw).abs().cmp(new BN(6)) == -1, true, "balance is within acceptable range of error")
	});
});
