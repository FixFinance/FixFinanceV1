
function impliedK(reserve0, reserve1, r, feeConstant) {
	let exp = 1.0 - r*feeConstant;
	return Math.pow(reserve0, exp) + Math.pow(reserve1, exp);
}

function reserveChange(reserve0, reserve1, r, feeConstant, reserve0Change) {
	let k = impliedK(reserve0, reserve1, r, feeConstant);
	let newReserve0 = reserve0 + reserve0Change;
	let exp = 1.0 - r*feeConstant;
	/*
		K = newReserve0**exp + newReserve1**exp
		K - newReserve0**exp == newReserve1**exp
		newReserve1 == (K - newReserve0**exp)**(1/exp)
	*/
	let newReserve1 = Math.pow(k - Math.pow(newReserve0, exp), 1/exp);
	let reserve1Change = newReserve1 - reserve1;
	return reserve1Change;
}


module.exports = {
	reserveChange
}