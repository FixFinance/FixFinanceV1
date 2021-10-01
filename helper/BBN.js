const _Mul = (BN, _10to18) => {
	return (num0, num1) => num0.mul(num1).div(_10to18);
}

const _Div = (BN, _10to18) => {
	return (numerator, denominator) => numerator.mul(_10to18).div(denominator);
}

const _Pow = (BN, _10to18) => {
	const _1 = new BN("1");
	return (num, exponent) => num.pow(exponent).div(_10to18.pow(exponent.sub(_1)));
}

const _ApproxNthRoot = (BN, _10to18, Pow) => {
	return (num, N) => {
		const _1 = new BN("1");
		const _2 = new BN("2");
		if (num.lte(_10to18)) {
			throw new Error("BN tools: ApproxRootNthRoot() num must be > 1");
		}
		if (N.eq(_1)) {
			return num;
		}
		let diff = num.sub(_10to18);
		let approx = _10to18;
		let divisor = new BN("4");
		let topSatisfies = () => Pow(approx.add(_1), N).gt(num);
		let bottomSatisfies = () => Pow(approx, N).lte(num);
		let approxIsBest = () => topSatisfies() && bottomSatisfies();
		while (!approxIsBest()) {
			let shift = diff.div(divisor);
			shift = shift.lt(_1) ? _1 : shift;
			if (!topSatisfies()) {
				approx = approx.add(shift);
			}
			else if (!bottomSatisfies()) {
				approx = approx.sub(shift);
			}
			divisor = divisor.mul(_2);
		}
		return approx;
	}
}

const getFunctionality = (BN) => {
	const _10to18 = (new BN(10)).pow(new BN(18));
	let Mul = _Mul(BN, _10to18);
	let Div = _Div(BN, _10to18);
	let Pow = _Pow(BN, _10to18);
	let ApproxNthRoot = _ApproxNthRoot(BN, _10to18, Pow);
	return {
		Mul,
		Div,
		Pow,
		ApproxNthRoot
	};
}

module.exports = {
	getFunctionality
}