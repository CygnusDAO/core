require('solidity-coverage');
require('hardhat-gas-reporter');
require('hardhat-contract-sizer');
require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-ethers');
const fs = require('fs');
const path = require('path');

// Ethers
const { ethers } = require('ethers');

// KEYS
require('dotenv').config({ path: path.resolve(__dirname, './.env') });
const { PRIVATE_KEY } = process.env;

module.exports = {
    solidity: {
        version: '0.8.4',
        settings: {
            optimizer: {
                enabled: true,
                runs: 800,
            },
        },
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS ? false : true,
    },
    defaultNetwork: 'localhost',
    networks: {
        hardhat: {},
        localhost: {
            url: 'http://localhost:8545',
            chainId: 31337,
        },
        avalancheFujiTestnet: {
            url: 'https://api.avax.network/ext/bc/C/rpc',
            chainId: 43113,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: 'https://api.avax-test.network/ext/bc/C/rpc',
                enabled: true,
            },
        },
        avalancheMain: {
            url: 'https://api.avax.network/ext/bc/C/rpc',
            chainId: 43114,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: 'https://api.avax.network/ext/bc/C/rpc',
                enabled: true,
            },
        },
        mainnet: {
            url: 'https://rpc.ankr.com/eth',
            chainId: 1,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: 'https://rpc.ankr.com/eth',
                enabled: true,
            },
        },
        fantom: {
            url: 'https://rpc.ftm.tools/',
            chainId: 250,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: 'https://rpc.ftm.tools/',
                enabled: true,
            },
        },
        polygon: {
            url: 'https://polygon-rpc.com',
            chainId: 137,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: `https://polygon-rpc.com`,
                enabled: true,
            },
        },
        ropsten: {
            url: 'https://ropsten.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161',
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: `https://ropsten.infura.io/v3/${process.env.API_KEY}`,
                enabled: true,
            },
        },
    },
    paths: {
        artifacts: './artifacts',
        cache: './cache',
    },
};
