const dummyAToken = artifacts.require('dummyAToken');
const aaveWrapper = artifacts.require('AaveWrapper');
const capitalHandler = artifacts.require('CapitalHandler');
const BN = web3.utils.BN;
const _10To18 = (new BN('10')).pow(new BN('18'));


contract('aaveWrapper', async function(accounts){
	it('before each', async () => {
		dummyATokenInstance = await dummyAToken.new("DMY");
		aaveWrapperInstance = await aaveWrapper.new(dummyATokenInstance.address);
		inflation = await dummyATokenInstance.inflation();
		assert.equal(await aaveWrapperInstance.aToken(), dummyATokenInstance.address, 'correct address for aToken');
		assert.equal((await aaveWrapperInstance.totalSupply()).toString(), "0", "correct total supply");
	});

	it('executes 1st deposit', async () => {
		amount = '10000';
		await dummyATokenInstance.approve(aaveWrapperInstance.address, amount);
		await aaveWrapperInstance.deposit(accounts[0], amount);
		totalSupply = await aaveWrapperInstance.totalSupply();
		assert.equal(totalSupply.toString(), amount, "correct total supply after 1st deposit");
		assert.equal((await aaveWrapperInstance.balanceOf(accounts[0])).toString(), amount, "correct balance of account 0 after 1st deposit");
	});

	it('executes standard deposits', async () => {
		inflation = inflation.mul(new BN(2));
		await dummyATokenInstance.setInflation(inflation.toString());
		await dummyATokenInstance.approve(aaveWrapperInstance.address, amount);
		await aaveWrapperInstance.deposit(accounts[1], amount);
		expectedBalanceIncrease = (new BN(amount)).div(new BN(2));
		prevTotalSupply = totalSupply;
		totalSupply = await aaveWrapperInstance.totalSupply();
		assert.equal(totalSupply.toString(), prevTotalSupply.add(expectedBalanceIncrease).toString(), "correct total supply after standard deposit");
		assert.equal((await aaveWrapperInstance.balanceOf(accounts[1])).toString(), (new BN(amount)).div(new BN(2)).toString(), "correct balance account 1");
	});

	it('executes withdrawWrappedToken', async () => {
		inflation = inflation.mul(new BN(3));
		await dummyATokenInstance.setInflation(inflation.toString());
		toWithdraw = (new BN(amount)).div(new BN(2));
		await aaveWrapperInstance.withdrawWrappedToken(accounts[1], toWithdraw.toString());
		prevTotalSupply = totalSupply;
		totalSupply = await aaveWrapperInstance.totalSupply();
		wrappedBalanceAct0 = await aaveWrapperInstance.balanceOf(accounts[0]);
		assert.equal(totalSupply.toString(), prevTotalSupply.sub(toWithdraw).toString(), "correct total supply after withdrawWrappedToken() call");
		assert.equal(wrappedBalanceAct0.toString(), (new BN(amount)).sub(toWithdraw).toString(), "correct balance wrapped tokens for account 0");
		assert.equal((await dummyATokenInstance.balanceOf(accounts[1])).toString(), inflation.mul(toWithdraw).div(_10To18).toString(), "correct aToken balance for account");
	});

	it('executes withdrawAToken', async () => {
		toWithdraw = new BN(amount);
		await aaveWrapperInstance.withdrawAToken(accounts[2], toWithdraw.toString());
		expectedWrappedTokenDecrease = toWithdraw.mul(_10To18);
		expectedWrappedTokenDecrease = expectedWrappedTokenDecrease.div(inflation).add(new BN(expectedWrappedTokenDecrease.mod(inflation).toString() == "0" ? 0 : 1));
		prevTotalSupply = totalSupply;
		totalSupply = await aaveWrapperInstance.totalSupply();
		prevWrappedBalanceAct0 = wrappedBalanceAct0;
		wrappedBalanceAct0 = await aaveWrapperInstance.balanceOf(accounts[0]);
		assert.equal(totalSupply.toString(), prevTotalSupply.sub(expectedWrappedTokenDecrease).toString(), "correct total supply after withdrawAToken() call");
		assert.equal(wrappedBalanceAct0.toString(), prevWrappedBalanceAct0.sub(expectedWrappedTokenDecrease).toString(), "correct balance wrapped token account 0");
		aTknBalAct2 = await dummyATokenInstance.balanceOf(accounts[2]);
		//inflation is 6*10**18 thus we can expect the range abs of the error in the balance of account[2] to be less than 6
		assert.equal(aTknBalAct2.sub(toWithdraw).abs().cmp(new BN(6)) == -1, true, "balance is within acceptable range of error")
	});
});
