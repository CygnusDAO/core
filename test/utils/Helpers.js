const { BigNumber } = require('@ethersproject/bignumber');

function bnMantissa(n) {
	let den = 10e13;
	let num = Math.round(n*den);
	var len = Math.max( num.toString().length, den.toString().length, Math.round(Math.log10(num)) );

	const MAX_LEN = 14;

	if(len > MAX_LEN){

		num = Math.round(num / Math.pow(10, len - MAX_LEN));

		den = Math.round(den / Math.pow(10, len - MAX_LEN));
	}

	return (BigNumber.from(1e9)).mul(BigNumber.from(1e9)).mul(BigNumber.from(num)).div(BigNumber.from(den));
}

module.exports = {
  bnMantissa
}
