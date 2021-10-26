/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * trufflesuite.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

/*

const HDWalletProvider = require('@truffle/hdwallet-provider');
// const infuraKey = "fj4jll3k.....";
//
// const fs = require('fs');
// const mnemonic = fs.readFileSync(".secret").toString().trim();
//unsecure pks for testnet use only
const UNSECURE_PKs = [
  `0xb188eca00c9a931eeb31dc0855bb8a8d051e513271ffea3ac3c8a080b34d27c3`,
  `0x640da2b249b24c424c7aa155085b4707e338783643b1e02de45334f78411e283`,
  `0x63366ef1bcca1f6ed61eb8628606f762226472f60d500ab057d5677df28f2489`,
  `0x5ee4e190ad83b16e6861b848daf76ad6a7dc39f89ce1589b38e10304cae3c118`,
  `0xbef24829cd8f3f60ef5a19be366b3b0311f1a23879949a270cae90b4b0e16abe`
];

*/

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  networks: {
    // Useful for testing. The `development` name is special - truffle uses it by default
    // if it's defined here and no other network is specified at the command line.
    // You should run a client (like ganache-cli, geth or parity) in a separate terminal
    // tab if you use this network and you must also set the `host`, `port` and `network_id`
    // options below to some value.
    //
    development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
      gas: 6000000
    }//,
/*
    matic: {
      provider: () => new HDWalletProvider(UNSECURE_PKs, 'https://polygon-mumbai.infura.io/v3/130607aa3e804a5a9feab69f92045243'),
      network_id: 80001,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 6000000
    },
    arbitrum: {
      provider: () => new HDWalletProvider(UNSECURE_PKs, 'https://arbitrum-rinkeby.infura.io/v3/130607aa3e804a5a9feab69f92045243'),
      network_id: 421611,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 6000000
    },
    rinkeby: {
      provider: () => new HDWalletProvider(UNSECURE_PKs, 'https://rinkeby.infura.io/v3/130607aa3e804a5a9feab69f92045243'),
      network_id: 4,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 6000000
    },
    kovan: {
      provider: () => new HDWalletProvider(UNSECURE_PKs, 'https://kovan.infura.io/v3/130607aa3e804a5a9feab69f92045243'),
      network_id: 42,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 6000000
    },
    optimism: {
      provider: () => new HDWalletProvider(UNSECURE_PKs, 'https://kovan.optimism.io'),
//      provider: () => new HDWalletProvider(UNSECURE_PKs, 'https://optimism-kovan.infura.io/v3/3675fefa54e649fb8b7b21b9544eb6dd'),
      network_id: 69,
      confirmations: 1,
      timeoutBlocks: 200,
      skipDryRun: true,
    }
*/
    // Another network with more advanced options...
    // advanced: {
    // port: 8777,             // Custom port
    // network_id: 1342,       // Custom network
    // gas: 8500000,           // Gas sent with each transaction (default: ~6700000)
    // gasPrice: 20000000000,  // 20 gwei (in wei) (default: 100 gwei)
    // from: <address>,        // Account to send txs from (default: accounts[0])
    // websockets: true        // Enable EventEmitter interface for web3 (default: false)
    // },
    // Useful for deploying to a public network.
    // NB: It's important to wrap the provider as a function.
    // ropsten: {
    // provider: () => new HDWalletProvider(mnemonic, `https://ropsten.infura.io/v3/YOUR-PROJECT-ID`),
    // network_id: 3,       // Ropsten's id
    // gas: 5500000,        // Ropsten has a lower block limit than mainnet
    // confirmations: 2,    // # of confs to wait between deployments. (default: 0)
    // timeoutBlocks: 200,  // # of blocks before a deployment times out  (minimum/default: 50)
    // skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
    // },
    // Useful for private networks
    // private: {
    // provider: () => new HDWalletProvider(mnemonic, `https://network.io`),
    // network_id: 2111,   // This network is yours, in the cloud.
    // production: true    // Treats this network as if it was a public net. (default: false)
    // }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.6.8",    // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
      // settings: {          // See the solidity docs for advice about optimization and evmVersion
      //  optimizer: {
      //    enabled: false,
      //    runs: 200
      //  },
      //  evmVersion: "byzantium"
      // }
    }
  }
};
