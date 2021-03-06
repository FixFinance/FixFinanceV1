/*
   This is a js implementation of the following c file
   http://www.mymathlib.com/c_source/functions/exponential_integrals/exponential_integral_Ei.c
*/
const epsilon = 0.00000000000000000108420217248550443400745280086994171142578125;
//const epsilon = 0.000000000108420217248550443400745280086994171142578125;

function Ei(x) {
   if (x < -5.0) return Continued_Fraction_Ei(x);
   if ( x <= 6.8 )  return Power_Series_Ei(x);
   if ( x < 50.0 ) return Argument_Addition_Series_Ei(x);
   return Continued_Fraction_Ei(x);
}


function Power_Series_Ei(x) { 
   var xn = -x;
   var Sn = -x;
   var Sm1 = 0.0;
   var hsum = 1.0;
   var g = 0.5772156649015328606065121;
   var y = 1.0;
   var factorial = 1.0;
  
   if ( x == 0.0 ) return -Infinity;
 
   let i = 0;
   let caught = false;
   while ( Math.abs(Sn - Sm1) > epsilon * Math.abs(Sm1) ) {
      Sm1 = Sn;
      y += 1.0;
      xn *= (-x);
      factorial *= y;
      hsum += (1.0 / y);
      Sn += hsum * xn / factorial;
      i++;
   }
   return (g + Math.log(Math.abs(x)) - Math.exp(x) * Sn);
}

function Argument_Addition_Series_Ei(x) {
	var ei = [
      1.915047433355013959531e2,  4.403798995348382689974e2,
      1.037878290717089587658e3,  2.492228976241877759138e3,
      6.071406374098611507965e3,  1.495953266639752885229e4,
      3.719768849068903560439e4,  9.319251363396537129882e4,
      2.349558524907683035782e5,  5.955609986708370018502e5,
      1.516637894042516884433e6,  3.877904330597443502996e6,
      9.950907251046844760026e6,  2.561565266405658882048e7,
      6.612718635548492136250e7,  1.711446713003636684975e8,
      4.439663698302712208698e8,  1.154115391849182948287e9,
      3.005950906525548689841e9,  7.842940991898186370453e9,
      2.049649711988081236484e10, 5.364511859231469415605e10,
      1.405991957584069047340e11, 3.689732094072741970640e11,
      9.694555759683939661662e11, 2.550043566357786926147e12,
      6.714640184076497558707e12, 1.769803724411626854310e13,
      4.669055014466159544500e13, 1.232852079912097685431e14,
      3.257988998672263996790e14, 8.616388199965786544948e14,
      2.280446200301902595341e15, 6.039718263611241578359e15,
      1.600664914324504111070e16, 4.244796092136850759368e16,
      1.126348290166966760275e17, 2.990444718632336675058e17,
      7.943916035704453771510e17, 2.111342388647824195000e18,
      5.614329680810343111535e18, 1.493630213112993142255e19,
      3.975442747903744836007e19, 1.058563689713169096306e20
   ];
   var  k = Math.floor(x + 0.5);
   var  j = 0;
   var xx = k;
   var dx = x - xx;
   var xxj = xx;
   var edx = Math.exp(dx);
   var Sm = 1.0;
   var Sn = (edx - 1.0) / xxj;
   var term = Math.max();
   var factorial = 1.0;
   var dxj = 1.0;

   while (Math.abs(term) > epsilon * Math.abs(Sn) ) {
      j++;
      factorial *= j;
      xxj *= xx;
      dxj *= (-dx);
      Sm += (dxj / factorial);
      term = ( factorial * (edx * Sm - 1.0) ) / xxj;
      Sn += term;
   }
   
   return ei[k-7] + Sn * Math.exp(xx); 
}

function Continued_Fraction_Ei(x) {
   var Am1 = 1.0;
   var A0 = 0.0;
   var Bm1 = 0.0;
   var B0 = 1.0;
   var a = Math.exp(x);
   var b = -x + 1.0;
   var Ap1 = b * A0 + a * Am1;
   var Bp1 = b * B0 + a * Bm1;
   var j = 1;

   a = 1.0;
   while ( Math.abs(Ap1 * B0 - A0 * Bp1) > epsilon * Math.abs(A0 * Bp1) ) {
      if ( Math.abs(Bp1) > 1.0) {
         Am1 = A0 / Bp1;
         A0 = Ap1 / Bp1;
         Bm1 = B0 / Bp1;
         B0 = 1.0;
      } else {
         Am1 = A0;
         A0 = Ap1;
         Bm1 = B0;
         B0 = Bp1;
      }
      a = -j * j;
      b += 2.0;
      Ap1 = b * A0 + a * Am1;
      Bp1 = b * B0 + a * Bm1;
      j += 1;
   }
   return (-Ap1 / Bp1);
}

module.exports = {
   eval: Ei
};