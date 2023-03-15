require("@nomicfoundation/hardhat-toolbox");
require('hardhat-contract-sizer');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 420,
      },
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  defaultNetwork: "localhost",
  networks: {
    // Local
    localhost: {
      url: "http://localhost:8545",
      chainId: 31337,
      timeout: 400000000,
    },
    // Mainnet
    mainnet: {
      url: "https://rpc.ankr.com/eth",
      chainId: 1,
    },
    // Arbitrum
    arbitrum: {
      url: "https://rpc.ankr.com/arbitrum",
      chainId: 42161,
    },
    // Avalanche
    avalanche: {
      url: "https://rpc.ankr.com/avalanche",
      chainId: 43114,
    },
    // Fantom
    fantom: {
      url: "https://rpc.ankr.com/fantom",
      chainId: 250,
    },
    // Polygon
    polygon: {
      url: "https://rpc.ankr.com/polygon",
      chainId: 137,
      gasPrice: 8000000000
    },
    bsc: {
      url: "https://rpc.ankr.com/bsc",
      chainId: 56,
    },
  },
}
