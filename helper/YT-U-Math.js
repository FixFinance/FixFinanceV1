let Ei = require('./ei.js');

function impliedK(U, Y, L, r, w, APYo) {
	/*
		U = (c+Y)*(APYo+1)**(-S*r/(Y+c)) + S*t*ln(APYo+1)*Ei(-S*t*ln(APYo+1)/(Y+c)) - Y + K

		K = U - (c+Y)*(APYo+1)**(-S*r/(Y+c)) - S*t*ln(APYo+1)*Ei(-S*t*ln(APYo+1)/(Y+c)) + Y
	*/
	let c = L*w;
	let S = L+c;
	return U - (c+Y)*Math.pow(APYo, -S*r/(Y+c)) - S*r*Math.log(APYo)*Ei.eval(-S*r*Math.log(APYo)/(Y+c)) + Y
}

function KminusU(Y, L, r, w, APYo) {
	let c = L*w;
	let S = L+c;
	return - (c+Y)*Math.pow(APYo, -S*r/(Y+c)) - S*r*Math.log(APYo)*Ei.eval(-S*r*Math.log(APYo)/(Y+c)) + Y;
}

function Uout(Y, L, r, w, APYo, Yin) {
	return KminusU(Y+Yin, L, r, w, APYo) - KminusU(Y, L, r, w, APYo);
}

function Uin(Y, L, r, w, APYo, Yout) {
	return KminusU(Y, L, r, w, APYo) - KminusU(Y-Yout, L, r, w, APYo);
}


module.exports = {
	Uout,
	Uin
}