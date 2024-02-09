require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

const fs = require('fs');
const mnemonic = fs.readFileSync('.secret').toString().trim();


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: '0.8.23',
  networks: {
    development: {
      url: 'http://127.0.0.1:8545',
      accounts: {
        mnemonic: mnemonic,
      },
    },
    neon_devnet: {
      url: 'https://proxy.devnet.neonlabs.org/solana',
      chainId: 245022926,
    },
    neon_testnet: {
      url: 'https://proxy.testnet.neonlabs.org/solana',
      chainId: 245022940,
    },
    bsc_testnet: {
      url: 'https://data-seed-prebsc-1-s1.binance.org:8545',
      chainId: 97,
    },
    bsc: {
      url: 'https://bsc-dataseed1.binance.org',
      chainId: 56,
    },
    mumbai: {
      url: 'https://polygon-mumbai.infura.io/ws/v3/',
      chainId: 80001,
    },
    matic: {
      url: 'https://polygon-mainnet.infura.io/ws/v3/',
      chainId: 137,
    },
    ropsten: {
      url: 'wss://ropsten.infura.io/ws/v3/',
      chainId: 3,
    },
    rinkeby: {
      url: 'wss://rinkeby.infura.io/ws/v3/',
      chainId: 4,
    },
  },
};
