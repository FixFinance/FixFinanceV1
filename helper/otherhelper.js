
function _advanceTimeAndBlock(advanceTime, advanceBlock) {
    return async (time) => {
        await advanceTime(time);
        await advanceBlock();

        return Promise.resolve(web3.eth.getBlock('latest'));
    }
}
advanceTimeAndBlock = async (time) => {
    await advanceTime(time);
    await advanceBlock();

    return Promise.resolve(web3.eth.getBlock('latest'));
}

function _advanceTime(web3) {
    return ((time) => {
        return new Promise((resolve, reject) => {
            web3.currentProvider.send({
                jsonrpc: "2.0",
                method: "evm_increaseTime",
                params: [time],
                id: new Date().getTime()
            }, (err, result) => {
                if (err) { return reject(err); }
                return resolve(result);
            });
        });
    });
}

function _advanceBlock(web3) { 
    return (() => {
        return new Promise((resolve, reject) => {
            web3.currentProvider.send({
                jsonrpc: "2.0",
                method: "evm_mine",
                id: new Date().getTime()
            }, (err, result) => {
                if (err) { return reject(err); }
                const newBlockHash = web3.eth.getBlock('latest').hash;

                return resolve(newBlockHash)
            });
        });
    });
}


module.exports = (web3) => {
    let advanceTime = _advanceTime(web3);
    let advanceBlock = _advanceBlock(web3);        
    let advanceTimeAndBlock = _advanceTimeAndBlock(advanceTime, advanceBlock)
    return ({
        advanceTime,
        advanceBlock,
        advanceTimeAndBlock
    });
}