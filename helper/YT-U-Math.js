let Ei = require('./ei.js');

function impliedK(U, Y, L, r, APYo) {
	/*
		U = K + (L* (r) * ln(APYo) * Ei(-L*(r)*ln(APYo)/Y) + Y*(APYo**(-L*r/Y) -1))

		K = U - (L* (r) * ln(APYo) * Ei(-L*(r)*ln(APYo)/Y) + Y*(APYo**(-L*r/Y) -1))
	*/
	return U - (L* (r) * Math.log(APYo) * Ei.eval(-L*(r)*Math.log(APYo)/Y) + Y*(Math.pow(APYo,-L*r/Y) -1));
}

function KminusU(Y, L, r, APYo) {
	return - (L* (r) * Math.log(APYo) * Ei.eval(-L*(r)*Math.log(APYo)/Y) + Y*(Math.pow(APYo,-L*r/Y) -1));
}

function Uout(Y, L, r, APYo, Yin) {
	return KminusU(Y+Yin, L, r, APYo) - KminusU(Y, L, r, APYo);
}

function Uin(Y, L, r, APYo, Yout) {
	return KminusU(Y, L, r, APYo) - KminusU(Y-Yout, L, r, APYo);
}


module.exports = {
	Uout,
	Uin
}