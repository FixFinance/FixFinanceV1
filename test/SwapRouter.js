const dummyAToken = artifacts.require('dummyAToken');
const dummyVaultHealth = artifacts.require('DummyVaultHealth');
const NGBwrapper = artifacts.require('NGBwrapper');
const FixCapitalPool = artifacts.require('FixCapitalPool');
const YieldToken = artifacts.require('YieldToken');
const zcbYtDeployer = artifacts.require('ZCB_YT_Deployer');
const organizer = artifacts.require('organizer');
const IERC20 = artifacts.require("IERC20");
const BigMath = artifacts.require("BigMath");
const Ei = artifacts.require("Ei");
const FixCapitalPoolDeployer = artifacts.require('FixCapitalPoolDeployer');
const ZCBamm = artifacts.require('ZCBamm');
const YTamm = artifacts.require('YTamm');
const ZCBammDeployer = artifacts.require('ZCBammDeployer');
const YTammDelegate = artifacts.require('YTammDelegate');
const YTammDeployer = artifacts.require('YTammDeployer');
const SwapRouter = artifacts.require("SwapRouter");
const SwapRouterDeployer = artifacts.require("SwapRouterDeployer");
const SwapRouterDelegate = artifacts.require('SwapRouterDelegate');
const InfoOracle = artifacts.require("InfoOracle");

const helper = require("../helper/helper.js");

const BN = web3.utils.BN;
const nullAddress = "0x0000000000000000000000000000000000000000";
const _10To18BN = (new BN("10")).pow(new BN("18"));
const secondsPerYear = 31556926;
const _0BalanceString = "0";
const roundingBuffer = new BN(0x10);
const LENGTH_RATE_SERIES = 31;

const BipsToTreasury = "100"; //1% in basis point format
const SlippageConstant = "0";
const ZCBammFeeConstant = _10To18BN;
const YTammFeeConstant = _10To18BN;

contract('SwapRouter', async function(accounts) {

	it('before each', async () => {
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
		fixCapitalPoolDeployerInstance = await FixCapitalPoolDeployer.new();
		swapRouterDelegateInstance = await SwapRouterDelegate.new();
		swapRouterDeployerInstance = await SwapRouterDeployer.new(swapRouterDelegateInstance.address);
		infoOracleInstance = await InfoOracle.new(
			BipsToTreasury,
			nullAddress
		);
		organizerInstance = await organizer.new(
			zcbYtDeployerInstance.address,
			fixCapitalPoolDeployerInstance.address,
			ZCBammDeployerInstance.address,
			YTammDeployerInstance.address,
			swapRouterDeployerInstance.address,
			infoOracleInstance.address
		);
		await organizerInstance.DeploySwapRouter();
		router = await SwapRouter.at(await organizerInstance.SwapRouterAddress());

		let timestamp = (await web3.eth.getBlock('latest')).timestamp;
		//maturity is 110 days out
		maturity = timestamp + 110*24*60*60;

		aTokenInstance = await dummyAToken.new("aCOIN");
		let rec = await organizerInstance.deployAssetWrapper(aTokenInstance.address);
		NGBwrapperInstance = await NGBwrapper.at(rec.receipt.logs[0].args.wrapperAddress);
		rec = await organizerInstance.deployFixCapitalPoolInstance(NGBwrapperInstance.address, maturity);
		fixCapitalPoolInstance = await FixCapitalPool.at(rec.receipt.logs[0].args.addr);

		await infoOracleInstance.setSlippageConstant(fixCapitalPoolInstance.address, SlippageConstant);
		await infoOracleInstance.setFeeConstants(fixCapitalPoolInstance.address, ZCBammFeeConstant, YTammFeeConstant);

		zcbInstance = await IERC20.at(await fixCapitalPoolInstance.zeroCouponBondAddress());
		yieldTokenInstance = await YieldToken.at(await fixCapitalPoolInstance.yieldTokenAddress());
		await organizerInstance.deployZCBamm(fixCapitalPoolInstance.address);
		amm0 = await ZCBamm.at(await organizerInstance.ZCBamms(fixCapitalPoolInstance.address));

		//simulate generation of 100% returns in money market
		await aTokenInstance.setInflation("2"+_10To18BN.toString().substring(1));

		//mint funds to accounts[0]
		balance = _10To18BN;
		await aTokenInstance.approve(NGBwrapperInstance.address, balance);
		await NGBwrapperInstance.depositUnitAmount(accounts[0], balance);
		await NGBwrapperInstance.approve(fixCapitalPoolInstance.address, balance);
		await fixCapitalPoolInstance.depositWrappedToken(accounts[0], balance);
		await zcbInstance.approve(amm0.address, balance);
		await yieldTokenInstance.approve(amm0.address, balance);

		/*
			make first deposit in amm0
		*/
		Uin = balance.div(new BN("10"));
		ZCBin = balance.div(new BN("10"));
		rec = await amm0.firstMint(Uin, ZCBin);
		/*
			set rate in amm0
		*/
		for (let i = 0; i < LENGTH_RATE_SERIES; i++) {
			await amm0.forceRateDataUpdate();
			//advance 2 minuites
			helper.advanceTime(121);
		}
		let OracleRateString = (await amm0.getImpliedRateData())._impliedRates[0].toString();
		await amm0.setOracleRate(OracleRateString);


		await organizerInstance.deployYTamm(fixCapitalPoolInstance.address);
		amm1 = await YTamm.at(await organizerInstance.YTamms(fixCapitalPoolInstance.address));
		//router = await SwapRouter.at(await organizerInstance.SwapRouterAddress());

		await zcbInstance.approve(amm1.address, balance);
		await yieldTokenInstance.approve(amm1.address, balance);
		/*
			now we mint liquidity tokens and then burn to hold rate constant in amm0 and build up to have 3 rate data points
		*/
		let results = await amm0.getReserves();
		Ureserves = results._Ureserves.toString();
		ZCBreserves = results._ZCBreserves.toString();
		OracleRate = parseInt((await amm0.getRateFromOracle()).toString()) * Math.pow(2, -64);
		APYo = parseInt((await amm0.getAPYFromOracle()).toString()) * Math.pow(2, -64);

		let toMint = balance.div((new BN("1000")));
		await amm1.firstMint(toMint);
	});


	it('ATknToZCB()', async () => {
		helper.advanceTime(100);
		balanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);

		let amt = "100000";
		let minZCB = "100001";
		let toApprove = roundingBuffer.add(new BN(amt));
		await aTokenInstance.approve(router.address, toApprove);
		await router.UnitToZCB(fixCapitalPoolInstance.address, amt, minZCB);

		newBalanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		newBalanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		assert.equal(balanceATkn.sub(newBalanceATkn).toString(), toApprove, "correct amount of aTkn in");
		assert.equal(balanceYT.toString(), newBalanceYT.toString(), "YT balance not affected");
		if (newBalanceZCB.sub(balanceZCB).cmp(new BN(minZCB)) == -1) {
			assert.fail("new balance of ZCB must be greater than prev balance by at least _minZCBout");
		}
	});

	it('ATknToYT()', async () => {
		helper.advanceTime(100);
		balanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);

		let amtYT = "100000";
		let maxATkn = "100000";
		//let maxATkn = "99999";
		await aTokenInstance.approve(router.address, maxATkn);
		await router.UnitToYT(fixCapitalPoolInstance.address, amtYT, maxATkn);

		newBalanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		newBalanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		assert.equal(newBalanceZCB.toString(), balanceZCB.toString(), "ZCB balance did not change");
		if (newBalanceYT.sub(balanceYT).cmp(new BN(amtYT)) === -1) {
			assert.fail("balance of YT is expected to increase by at least _amount");
		}
		if (balanceATkn.sub(newBalanceATkn).cmp(new BN(maxATkn)) == 1) {
			assert.fail("new balance of ATkn must not decrease by more than _maxATkn");
		}
	});

	it('SwapZCBtoYT()', async () => {
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "90000";
		let maxZCBin = "1000000";
		await zcbInstance.approve(router.address, maxZCBin);
		await router.SwapZCBtoYT(fixCapitalPoolInstance.address, amtYT, maxZCBin);

		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		if (newBalanceYT.sub(balanceYT).cmp(new BN(amtYT)) === -1)  {
			assert.fail("the amount of YT gained ought to be greater than or equal to _amountYT");
		}
		if (balanceZCB.sub(newBalanceZCB).cmp(new BN(maxZCBin)) === 1) {
			assert.fail("the amount of ZCB in ought to have been less than or equal to _maxZCBin")
		}
	});

	it('SwapYTtoZCB()', async () => {
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "900000";
		let minZCBout = "10";
		await yieldTokenInstance.approve_2(router.address, amtYT, true);
		await router.SwapYTtoZCB(fixCapitalPoolInstance.address, amtYT, minZCBout);

		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		if (balanceYT.sub(newBalanceYT).cmp(new BN(amtYT)) === 1)  {
			assert.fail("the amount of YT in ought to be less than or equal to _amountYT");
		}
		if (newBalanceZCB.sub(balanceZCB).cmp(new BN(minZCBout)) === -1) {
			assert.fail("the amount of ZCB out ought to have been greater than or equal to _minZCBout");
		}
	});

	it('SwapZCBtoYT_ZCBamm()', async () => {
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "90000";
		let maxZCBin = "1000000";
		await zcbInstance.approve(router.address, maxZCBin);
		await router.SwapZCBtoYT_ZCBamm(fixCapitalPoolInstance.address, amtYT, maxZCBin);

		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		if (newBalanceYT.sub(balanceYT).cmp(new BN(amtYT)) === -1)  {
			assert.fail("the amount of YT gained ought to be greater than or equal to _amountYT");
		}
		if (balanceZCB.sub(newBalanceZCB).cmp(new BN(maxZCBin)) === 1) {
			assert.fail("the amount of ZCB in ought to have been less than or equal to _maxZCBin")
		}
	});

	it('SwapYTtoZCB_ZCBamm()', async () => {
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "900000";
		let minZCBout = "10";

		await yieldTokenInstance.approve_2(router.address, amtYT, true);
		let approveAmount = (new BN(amtYT)).add(new BN(1)).toString();
		await router.SwapYTtoZCB_ZCBamm(fixCapitalPoolInstance.address, amtYT, minZCBout);

		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		if (balanceYT.sub(newBalanceYT).cmp(new BN(approveAmount)) === 1)  {
			assert.fail("the amount of YT in ought to be less than or equal to _amountYT");
		}
		if (newBalanceZCB.sub(balanceZCB).cmp(new BN(minZCBout)) === -1) {
			assert.fail("the amount of ZCB out ought to have been greater than or equal to _minZCBout");
		}
	});

	it('SwapUtoYT_ZCBamm()', async () => {
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "90000";
		let Uin = "40000";
		await yieldTokenInstance.approve_2(router.address, Uin, true);
		await zcbInstance.approve(router.address, Uin);
		await router.SwapUtoYT_ZCBamm(fixCapitalPoolInstance.address, amtYT, Uin);

		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		/*
			assert( balanceYTIncrease >= amtYT - Uin - 1)
		*/
		if (newBalanceYT.sub(balanceYT).add(new BN(Uin)).add(new BN(1)).cmp(new BN(amtYT)) === -1)  {
			assert.fail("the amount of YT gained ought to be greater than or equal to _amountYT - Uin");
		}
		if (balanceZCB.sub(newBalanceZCB).cmp(new BN(Uin)) === 1) {
			assert.fail("the amount of ZCB in ought to have been less than or equal to Uin");
		}
	});

	it('SwapYTtoU_ZCBamm()', async () => {
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "900000";
		let minUout = "10000";

		await yieldTokenInstance.approve_2(router.address, amtYT, true);
		await router.SwapYTtoU_ZCBamm(fixCapitalPoolInstance.address, amtYT, minUout);

		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		/*
			assert( balanceDecrease <= amtYT - minUout + 1)
		*/
		if (balanceYT.sub(newBalanceYT).add(new BN(minUout)).sub(new BN(1)).cmp(new BN(amtYT)) === 1)  {
			assert.fail("the amount of YT in ought to be less than or equal to _amountYT");
		}
		if (newBalanceZCB.sub(balanceZCB).cmp(new BN(minUout)) === -1) {
			assert.fail("the amount of ZCB out ought to have been greater than or equal to _minZCBout");
		}
	});

	it('LiquidateSpecificToUnderlying(): more YT in', async () => {
		balanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "100006";
		let amtZCB = "90000";
		let minUtotal = "90001";
		await zcbInstance.approve(router.address, amtZCB);
		await yieldTokenInstance.approve_2(router.address, amtYT, true);
		await router.LiquidateSpecificToUnderlying(fixCapitalPoolInstance.address, amtZCB, amtYT, minUtotal, true);

		newBalanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		if (balanceYT.sub(newBalanceYT).toString() !== amtYT) {
			let acceptedAmtYT = "100005";
			assert.equal(balanceYT.sub(newBalanceYT).toString(), acceptedAmtYT, "YT balance is in correct range");
		}
		assert.equal(balanceZCB.sub(newBalanceZCB).toString(), amtZCB, "ZCB balance is correct");
		if (newBalanceATkn.sub(balanceATkn).cmp(new BN(minUtotal)) < 1) {
			assert.fail("an amount of aTkn greater than or equal to _minUtotal ought to have been paid out by router");
		}
	});

	it('LiquidateSpecificToUnderlying(): more ZCB in', async () => {
		balanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);

		let amtYT = "90000";
		let amtZCB = "100006";
		let minUtotal = "90001";
		await zcbInstance.approve(router.address, amtZCB);
		await yieldTokenInstance.approve_2(router.address, amtYT, true);
		await router.LiquidateSpecificToUnderlying(fixCapitalPoolInstance.address, amtZCB, amtYT, minUtotal, true);

		newBalanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		newBalanceYT = await yieldTokenInstance.balanceOf_2(accounts[0], false);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		if (balanceYT.sub(newBalanceYT).toString() !== amtYT) {
			let acceptedAmtYT = "89999";
			if (balanceYT.sub(newBalanceYT).toString() !== acceptedAmtYT) {
				acceptedAmtYT = "89998";
				assert.equal(balanceYT.sub(newBalanceYT).toString(), acceptedAmtYT, "YT balance is in correct range");
			}
		}
		if (balanceZCB.sub(newBalanceZCB).toString() !== amtZCB) {
			let amtZCBAccepted = "100005";
			assert.equal(balanceZCB.sub(newBalanceZCB).toString(), amtZCBAccepted, "ZCB balance is correct");
		}
		if (newBalanceATkn.sub(balanceATkn).cmp(new BN(minUtotal)) < 1) {
			assert.fail("an amount of aTkn greater than or equal to _minUtotal ought to have been paid out by router");
		}
	});

	it('LiquidateAllToUnderlying()', async () => {
		balanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		balanceZCB = await zcbInstance.balanceOf(accounts[0]);
		balanceYT = await yieldTokenInstance.balanceOf(accounts[0]);

		let minUtotal = "2";
		await zcbInstance.approve(router.address, balanceZCB);
		await yieldTokenInstance.approve(router.address, balanceYT);
		await router.LiquidateAllToUnderlying(fixCapitalPoolInstance.address, minUtotal, true);

		newBalanceATkn = await aTokenInstance.balanceOf(accounts[0]);
		newBalanceYT = await yieldTokenInstance.balanceOf(accounts[0]);
		newBalanceZCB = await zcbInstance.balanceOf(accounts[0]);

		assert.equal(newBalanceYT.toString(), _0BalanceString, "YT balance is 0");
		assert.equal(newBalanceZCB.toString(), _0BalanceString, "ZCB balance is 0");
		if (newBalanceATkn.sub(balanceATkn).cmp(new BN(minUtotal)) < 1) {
			assert.fail("an amount of aTkn greater than or equal to _minUtotal ought to have been paid out by router");
		}
	});
});