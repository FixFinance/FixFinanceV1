let Ei = require('./ei.js');

function impliedK(U, Y, L, r, w, f, APYo) {
	/*
		U = (c+Y)*(APYo+1)**(-S*r/(Y+c)) + S*t*ln(APYo+1)*Ei(-S*t*ln(APYo+1)/(Y+c)) - Y + K

		K = U - (c+Y)*(APYo+1)**(-S*r/(Y+c)) - S*t*ln(APYo+1)*Ei(-S*t*ln(APYo+1)/(Y+c)) + Y
	*/
	let c = L*w;
	let S = L+c;
	let P = f*S;
	return U - (c+Y)*Math.pow(APYo, -P*r/(Y+c)) - P*r*Math.log(APYo)*Ei.eval(-P*r*Math.log(APYo)/(Y+c)) + Y
}

function KminusU(Y, L, r, w, f, APYo) {
	let c = L*w;
	let S = L+c;
	let P = f*S;
	return - (c+Y)*Math.pow(APYo, -P*r/(Y+c)) - P*r*Math.log(APYo)*Ei.eval(-P*r*Math.log(APYo)/(Y+c)) + Y;
}

function Uout(Y, L, r, w, f, APYo, Yin) {
	return KminusU(Y+Yin, L, r, w, f, APYo) - KminusU(Y, L, r, w, f, APYo);
}

function Uin(Y, L, r, w, f, APYo, Yout) {
	return KminusU(Y, L, r, w, f, APYo) - KminusU(Y-Yout, L, r, w, f, APYo);
}


module.exports = {
	Uout,
	Uin
}