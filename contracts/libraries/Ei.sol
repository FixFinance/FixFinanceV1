pragma solidity >=0.6.0;

import "./SignedSafeMath.sol";
import "./ABDKMath64x64.sol";

library Ei {
	using SignedSafeMath for int256;
	using ABDKMath64x64 for int128;
	int128 private constant epsilon = 2000000000;

	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

	int256 internal constant INFLATOR = 1<<96;

	function addition_series_data(uint8 _index) private pure returns (int256) {
		/*
			because this is a library we cannot use state data, also there is not support for constant arrays in solidity libraries
			thus we must return the correct value using a series of if statements

			addition_series_data_array = [
			int256( 3.532638989211429e21), int256( 8.123575301925086e21),
			int256( 1.914547520851727e22), int256( 4.597351009781708e22),
			int256( 1.1199767955048595e23), int256( 2.7595467055933305e23),
			int256( 6.861762397213119e23), int256( 1.7190984485914473e24),
			int256( 4.334170479517456e24), int256( 1.0986161322763805e25),
			int256( 2.797703108389213e25), int256( 7.1534708728861e25),
			int256( 1.835618393612818e26), int256( 4.7252538897488815e26),
			int256( 1.2198312830141285e27), int256( 3.1570619510569525e27),
			int256( 8.189734001592899e27), int256( 2.128967126497089e28),
			int256( 5.5450007070812015e28), int256( 1.4467672526275159e29),
			int256( 3.780936367779663e29), int256( 9.895777734762272e29),
			int256( 2.5935973811247214e30), int256( 6.806354363991228e30),
			int256( 1.788329890071965e31), int256( 4.704000104541168e31),
			int256( 1.2386324902270515e32), int256( 3.264711636491927e32),
			int256( 8.612886291792749e32), int256( 2.2742106798878982e33),
			int256( 6.00992892534685e33), int256( 1.5894430796449978e34),
			int256( 4.2066807430832585e34), int256( 1.1141313708614602e35),
			int256( 2.9527056022310355e35), int256( 7.830266715673091e35),
			int256( 2.077745864657038e36), int256( 5.516396839118708e36),
			int256( 1.4653938605367742e37), int256( 3.894739269536102e37),
			int256( 1.0356610276733984e38), int256( 2.755261428205564e38),
			int256( 7.333397495026503e38), int256( 1.9527053469860518e39)
			]
		*/
		if (_index < 32) {
			if (_index < 16) {
				if (_index < 8) {
					if (_index < 4) {
						if (_index < 2) {
							if (_index < 1) return int256( 3.532638989211429e21);
							return int256( 8.123575301925086e21);
						}
						if (_index < 3) return int256( 1.914547520851727e22);
						return int256( 4.597351009781708e22);
					}
					if (_index < 6) {
						if (_index < 5) return int256( 1.1199767955048595e23);
						return int256( 2.7595467055933305e23);
					}
					if (_index < 7) return int256( 6.861762397213119e23);
					return int256( 1.7190984485914473e24);
				}
				if (_index < 12) {
					if (_index < 10) {
						if (_index < 9) return int256( 4.334170479517456e24);
						return int256( 1.0986161322763805e25);
					}
					if (_index < 11) return int256( 2.797703108389213e25);
					return int256( 7.1534708728861e25);
				}
				if (_index < 14) {
					if (_index < 13) return int256( 1.835618393612818e26);
					return int256( 4.7252538897488815e26);
				}
				if (_index < 15) return int256( 1.2198312830141285e27);
				return int256( 3.1570619510569525e27);
			}
			if (_index < 24) {
				if (_index < 20) {
					if (_index < 18) {
						if (_index < 17) return int256( 8.189734001592899e27);
						return int256( 2.128967126497089e28);
					}
					if (_index < 19) return int256( 5.5450007070812015e28);
					return int256( 1.4467672526275159e29);
				}
				if (_index < 22) {
					if (_index < 21) return int256( 3.780936367779663e29);
					return int256( 9.895777734762272e29);
				}
				if (_index < 23) return int256( 2.5935973811247214e30);
				return int256( 6.806354363991228e30);
			}
			if (_index < 28) {
				if (_index < 26) {
					if (_index < 25) return int256( 1.788329890071965e31);
					return int256( 4.704000104541168e31);
				}
				if (_index < 27) return int256( 1.2386324902270515e32);
				return int256( 3.264711636491927e32);
			}
			if (_index < 30) {
				if (_index < 29) return int256( 8.612886291792749e32);
				return int256( 2.2742106798878982e33);
			}
			if (_index < 31) return int256( 6.00992892534685e33);
			return int256( 1.5894430796449978e34);
		}
		if (_index < 40) {
			if (_index < 36) {
				if (_index < 34) {
					if (_index < 33) return int256( 4.2066807430832585e34);
					return int256( 1.1141313708614602e35);
				}
				if (_index < 35) return int256( 2.9527056022310355e35);
				return int256( 7.830266715673091e35);
			}
			if (_index < 38) {
				if (_index < 37) return int256( 2.077745864657038e36);
				return int256( 5.516396839118708e36);
			}
			if (_index < 39) return int256( 1.4653938605367742e37);
			return int256( 3.894739269536102e37);
		}
		if (_index < 42) {
			if (_index < 41) return int256( 1.0356610276733984e38);
			return int256( 2.755261428205564e38);
		}
		if (_index < 43) return int256( 7.333397495026503e38);
		return int256( 1.9527053469860518e39);
	}

	function isOutOfBounds(int256 x) private pure returns (bool) {
		/*
		* Minimum value signed 64.64-bit fixed point number may have. 
		*/
		int128 MIN_64x64 = -0x80000000000000000000000000000000;

		/*
		* Maximum value signed 64.64-bit fixed point number may have. 
		*/
		int128 MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

		return x < MIN_64x64 || x > MAX_64x64;
	}

	int128 private constant POWER_SERIES_G = 1.0647749645774669733e19; // 0.5772156649015328606065121

	function Power_Series_Ei(int128 x) private pure returns (int256) { 
		int128 _epsilon = epsilon;  //gas savings
		int128 xn = -x;
		int128 Sn = -x;
		int128 Sm1 = 0;
		int128 hsum = 1<<64; //1.0
		int128 y = 1<<64; //1.0
		// we don't inflate factorial because we need it to fit in the 128 bit limit
		int128 factorial = 1;
		int128 store;

		require(x != 0);

		uint8 i = 0;
		while ( (Sn - Sm1).abs() > _epsilon.mul(Sm1.abs()) && i < 36) {
			y += 1<<64;
			int256 result = int256(xn) * (-x) >>64;
			if (isOutOfBounds(result)) {
				y -= 1<<64;
				store = xn / factorial;
				//reset xn and factorial
				xn = 1<<64;
				factorial = 1;
				break;
			}
			xn = int128(result);
			factorial *= y>>64;
			hsum += int128(1<<64).div(y);
			result = int256(hsum) * xn >> 64;
			if (isOutOfBounds(result)) {
				hsum -= int128(1<<64).div(y);
				factorial /= y>>64;
				xn = xn.div(-x);
				y -= 1<<64;
				store = xn / factorial;
				//reset xn and factorial
				xn = 1<<64;
				factorial = 1;
				break;
			}
			Sm1 = Sn;
			Sn += int128(result) / factorial;
			i++;
		}
		if (store == 0) {
			//copy x to top of the stack
			int128 _x = x;
			return int256(POWER_SERIES_G.add(_x.abs().ln()).sub(_x.exp().mul(Sn))).mul(2**32);
		}
		while ( (Sn - Sm1).abs() > _epsilon.mul(Sm1.abs()) && i < 36) {
			y += 1<<64;
			xn = xn.mul(-x);
			factorial *= y>>64;
			hsum += int128(1<<64).div(y);
			Sm1 = Sn;
			Sn += hsum.mul(xn).mul(store) / factorial;
			i++;
		}
		//copy x to top of the stack
		int128 _x = x;

		//to return a value inflated by 64 bits return int256(POWER_SERIES_G.add(_x.abs().ln()).sub(_x.exp().mul(Sn)));
		//we want a value inflated by 96 bits thus:
		return int256(POWER_SERIES_G.add(_x.abs().ln()).sub(_x.exp().mul(Sn))).mul(2**32);
	}

	function arg_add_series_return(int128 k, int128 Sn, int128 xx) private pure returns (int256) {
		/*
		we divide the exponent by 2 and then square the result is because
		the math library we use is bound to 128 bits
		x = 50 is the upper bound of the domain of this approximation function
		if we try to find (50).exp() we will get an overflow error from our math library
		thus we find (50/2).exp and cast to int256 and find the square
		*/
		int256 exp = int256((xx/2).exp())**2 >> 64;
		int256 a = exp * Sn;
		require(a/exp == Sn, "multiplication overflow");
		a >>= 64;
		int256 b = addition_series_data(uint8(k>>64)-7);
		int256 c = a + b;
		require((b >= 0 && c >= a) || (b < 0 && c < a), "addition overflow");
		return c;
	}

	function Argument_Addition_Series_Ei(int128 x) private pure returns (int256) {
		int128 k = ((x + (1<<63)) >> 64) << 64;
		int128 j = 0;
		int128 xx = k;
		int128 dx = x - xx;
		int128 xxj = xx;
		int128 edx = dx.exp();
		int128 Sm = 1 << 64;
		int128 Sn = (edx - (1<<64)).div(xxj);
		int128 term = MAX;
		int128 factorial = 1;
		int128 dxj = 1<<64;
		int128 _epsilon = epsilon; //gas savings
		while (term.abs() > _epsilon.mul(Sn.abs()) ) {
			j++;
			factorial *= j;
			xxj = xxj.mul(xx);
			dxj = dxj.mul(-dx);
			Sm = Sm.add(dxj / factorial);
			term = ( (factorial<<64).mul(edx.mul(Sm) - (1<<64) ) ).div(xxj);
			Sn = Sn.add(term);
		}

		//to return a value inflated by 64 bits return arg_add_series_return(k, Sn, xx);
		//we want a value inflated by 96 bits thus
		return arg_add_series_return(k, Sn, xx).mul(2**32);
	}


	function Continued_Fraction_Ei(int128 x) private pure returns (int256) {
		int256 Am1 = 1 << 64;
		int256 A0 = 0;
		int256 Bm1 = 0;
		int256 B0 = 1 << 64;
		int256 a = int256((x/2).exp())**2 >> 64;
		int256 b = (-x).add(1<<64);
		int256 Ap1 = (b.mul(A0) >> 64).add(a.mul(Am1) >> 64);
		int256 Bp1 = (b.mul(B0) >> 64).add(a.mul(Bm1) >> 64);
		int256 j = 1 << 64;
		int _epsilon = epsilon; //gas savings

		while ( ( (Ap1.mul(B0) >> 64).sub(A0.mul(Bp1) >> 64) ).abs() > (A0.mul(Bp1) >> 64).abs().mul(_epsilon) >> 64 ) {
			if ( Bp1.abs() > 1 << 64) {
				Am1 = A0.mul(1<<64).div(Bp1);
				A0 = Ap1.mul(1<<64).div(Bp1);
				Bm1 = B0.mul(1<<64).div(Bp1);
				B0 = 1 << 64;
			} else {
				Am1 = A0;
				A0 = Ap1;
				Bm1 = B0;
				B0 = Bp1;
			}
			a = j.mul(-j) >> 64;
			b += 2 << 64;
			Ap1 = (b.mul(A0) >> 64).add(a.mul(Am1) >> 64);
			Bp1 = (b.mul(B0) >> 64).add(a.mul(Bm1) >> 64);
			j += 1<<64;
		}

		//to get a value inflated by 64 bits return -Ap1).mul(1<<64).div(Bp1);
		//we want a value inflated by 96 bits thus:
		return (-Ap1).mul(1<<96).div(Bp1);
	}

	int private constant MAX_ITERATIONS = 10;

	function Continued_Fraction_Ei_2(int128 _x) private pure returns (int256) {
		int256 x = int256(_x) * 2**32;
		int256 Am1 = 1 << 96;
		int256 A0 = 0;
		int256 Bm1 = 0;
		int256 B0 = 1 << 96;
		int256 a = int256(_x.exp()) << 32;
		int256 b = (-x).add(1<<96);
		int256 Ap1 = a;
		int256 Bp1 = b;
		int256 j = 1;
		int _epsilon = epsilon; //gas savings

		//while ( ( (Ap1.mul(B0) >> 96).sub(A0.mul(Bp1) >> 96) ).abs() > (A0.mul(Bp1) >> 96).abs().mul(_epsilon) >> 64 ) {
		//inflate both sides by 96 bits
		while ( ( (Ap1.mul(B0)).sub(A0.mul(Bp1)) ).abs() > (A0.mul(Bp1) >> 64).abs().mul(_epsilon) && j <= MAX_ITERATIONS) {
			if ( Bp1.abs() > 1 << 96) {
				Am1 = A0.mul(1<<96).div(Bp1);
				A0 = Ap1.mul(1<<96).div(Bp1);
				Bm1 = B0.mul(1<<96).div(Bp1);
				B0 = 1 << 96;
			} else {
				Am1 = A0;
				A0 = Ap1;
				Bm1 = B0;
				B0 = Bp1;
			}
			a = -((j*j)<<96);
			b += 2 << 96;
			Ap1 = (b.mul(A0) >> 96).add(a.mul(Am1) >> 96);
			Bp1 = (b.mul(B0) >> 96).add(a.mul(Bm1) >> 96);
			j++;
		}

		return (-Ap1).mul(1<<96).div(Bp1);
	}


	/*
		@Description: approximates the exponential integral function

		@param int128 x: value for which to approximate Ei(x), inflated by 64 bits

		@return int256: an approximation of Ei(x) inflated by 96 bits
	*/
	function eval(int128 x) external pure returns (int256) {
		require(x >= int(-35 * 2**64) && x <= int(87 * 2**64), "Ei not in range");
		if (x < -5 * 2**64)
			return Continued_Fraction_Ei_2(x);
		if (x < int(uint(68 * 2**64) / 10))
			return Power_Series_Ei(x);
		if (x > int(50 * 2**64))
			return Continued_Fraction_Ei(x);
		return Argument_Addition_Series_Ei(x);
	}

}