
module.exports = async function(callback) {
	let accounts = await web3.eth.getAccounts();
	console.log(accounts);
	callback();
}
