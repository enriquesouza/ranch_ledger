require('dotenv').config();
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

const HDWalletProvider = require('@truffle/hdwallet-provider');
const NonceTrackerSubprovider = require("web3-provider-engine/subproviders/nonce-tracker")

const fs = require('fs');
const mnemonic = fs.readFileSync('.secret').toString().trim();
const privateKey = '';
const endpointUrl = 'https://kovan.infura.io/v3/';

module.exports = {
    plugins: ['truffle-plugin-verify'],

    api_keys: {
        etherscan: '',
        optimistic_etherscan: 'MY_API_KEY',
        arbiscan: 'MY_API_KEY',
        bscscan: 'MY_API_KEY',
        snowtrace: 'MY_API_KEY',
        polygonscan: '',
        ftmscan: 'MY_API_KEY',
        hecoinfo: 'MY_API_KEY',
        moonscan: 'MY_API_KEY',
        kovan: '',
    },
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
        //`http://127.0.0.1:8545`
        //https://docs.nethereum.com/en/latest/ethereum-and-clients/ganache-cli/
        development: {
            host: '127.0.0.1', // Localhost (default: none)
            port: 8545, // Standard Ethereum port (default: none)
            network_id: '*', // Any network (default: none)
            allowUnlimitedContractSize: true,
            timeoutBlocks: 200,
            skipDryRun: true,
            websockets: true,
            networkCheckTimeout: 1000000,
            //confirmations: 1,
            //gas: 8500000, // Gas sent with each transaction (default: ~6700000)
            //gasPrice: 20000000000, // 20 gwei (in wei) (default: 100 gwei)
            //provider: () => new HDWalletProvider(mnemonic, `ws://localhost:8545`),
            provider: () =>
                new HDWalletProvider({
                    mnemonic: mnemonic,
                    providerOrUrl: `ws://localhost:8545`,
                    numberOfAddresses: 100,
                }),
        },
        neon_devnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://proxy.devnet.neonlabs.org/solana`),
            network_id: 245022926,
            confirmations: 2,
            timeoutBlocks: 200,
            skipDryRun: true,
        },
        neon_testnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://proxy.testnet.neonlabs.org/solana`),
            network_id: 245022940,
            confirmations: 10,
            timeoutBlocks: 200,
            skipDryRun: true,
        },
        bsc_testnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545`),
            network_id: 97,
            confirmations: 10,
            timeoutBlocks: 200,
            skipDryRun: true,
        },
        bsc: {
            provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
            network_id: 56,
            confirmations: 10,
            timeoutBlocks: 200,
            skipDryRun: true,
        },
        mumbai: {
            provider: () =>
                new HDWalletProvider(mnemonic, `wss://polygon-mumbai.infura.io/ws/v3/`),
            network_id: 80001,
            gas: 4000000, //make sure this gas allocation isn't over 4M, which is the max
            allowUnlimitedContractSize: true,
            timeoutBlocks: 200,
            skipDryRun: true,
            websockets: true,
            networkCheckTimeout: 1000000,
        },
        matic: {
            provider: () => {
                let wallet = new HDWalletProvider(
                    mnemonic,
                    `wss://polygon-mainnet.infura.io/ws/v3/`
                );
                let nonceTracker = new NonceTrackerSubprovider();
                wallet.engine._providers.unshift(nonceTracker);
                nonceTracker.setEngine(wallet.engine);
                return wallet;
            },
            // new HDWalletProvider(mnemonic, `https://polygon-mainnet.infura.io/v3/`),
            network_id: 137,
            skipDryRun: true,
            websockets: true,
            timeoutBlocks: 50000,
            networkCheckTimeout: 10000000,
            confirmations: 1,
            gas: process.env.GAS_LIMIT, //make sure this gas allocation isn't over 4M, which is the max
            allowUnlimitedContractSize: true,
            gasPrice: process.env.GAS_PRICE, // 20 gwei (in wei) (default: 100 gwei)
            // maxFeePerGas: 3000000000,
            // maxPriorityFeePerGas: 2500000000,
        },
        ropsten: {
            provider: function () {
                return new HDWalletProvider(mnemonic, 'wss://ropsten.infura.io/ws/v3/');
            },
            network_id: 3,
            gas: 4000000, //make sure this gas allocation isn't over 4M, which is the max
            allowUnlimitedContractSize: true,
            timeoutBlocks: 200,
            skipDryRun: true,
            websockets: true,
            networkCheckTimeout: 1000000,
        },
        rinkeby: {
            provider: function () {
                return new HDWalletProvider(mnemonic, 'wss://rinkeby.infura.io/ws/v3/');
            },
            network_id: 4,
            gas: 4000000, //make sure this gas allocation isn't over 4M, which is the max
            allowUnlimitedContractSize: true,
            timeoutBlocks: 200,
            skipDryRun: true,
            websockets: true,
            networkCheckTimeout: 1000000,
        },
        // Another network with more advanced options...
        // advanced: {
        // port: 8777,             // Custom port
        // network_id: 1342,       // Custom network
        // gas: 8500000,           // Gas sent with each transaction (default: ~6700000)
        // gasPrice: 20000000000,  // 20 gwei (in wei) (default: 100 gwei)
        // from: <address>,        // Account to send txs from (default: accounts[0])
        // websocket: true        // Enable EventEmitter interface for web3 (default: false)
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
        enableTimeouts: false,
        before_timeout: 60000 * 60 * 24,
    },

    // Configure your compilers
    compilers: {
        solc: {
            version: '0.8.23', // Fetch exact version from solc-bin (default: truffle's version)
            // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
            settings: {
                // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 200000,
                },
                evmVersion: 'byzantium',
            },
        },
    },

    // Truffle DB is currently disabled by default; to enable it, change enabled:
    // false to enabled: true. The default storage location can also be
    // overridden by specifying the adapter settings, as shown in the commented code below.
    //
    // NOTE: It is not possible to migrate your contracts to truffle DB and you should
    // make a backup of your artifacts to a safe location before enabling this feature.
    //
    // After you backed up your artifacts you can utilize db by running migrate as follows:
    // $ truffle migrate --reset --compile-all
    //
    // db: {
    // enabled: false,
    // host: "127.0.0.1",
    // adapter: {
    //   name: "sqlite",
    //   settings: {
    //     directory: ".db"
    //   }
    // }
    // }
};
