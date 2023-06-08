require("@nomicfoundation/hardhat-chai-matchers");
require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");

const optimizerSettings = {
    enabled: true,
    runs: 800,
    details: {
        // The peephole optimizer is always on if no details are given,
        // use details to switch it off.
        peephole: true,
        // The inliner is always on if no details are given,
        // use details to switch it off.
        inliner: true,
        // The unused jumpdest remover is always on if no details are given,
        // use details to switch it off.
        jumpdestRemover: true,
        // Sometimes re-orders literals in commutative operations.
        orderLiterals: true,
        // Removes duplicate code blocks
        deduplicate: true,
        // Common subexpression elimination, this is the most complicated step but
        // can also provide the largest gain.
        cse: true,
        // Optimize representation of literal numbers and strings in code.
        constantOptimizer: true,
        yulDetails: {
            stackAllocation: true,
            optimizerSteps:
                "dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul[j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul]VcTOculjmul",
        },
    },
};

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        ...optimizerSettings,
                    },
                    metadata: {
                        bytecodeHash: "none",
                    },
                },
            },
        ],
        overrides: {
            "contracts/cygnus-periphery/CygnusAltair.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            "contracts/cygnus-periphery/CygnusAltairX.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            "contracts/cygnus-periphery/CollateralHarvester.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            "contracts/cygnus-periphery/BorrowableHarvester.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            "contracts/cygnus-token/CygnusComplexRewarder.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            "contracts/cygnus-oracle/CygnusNebulaOracle.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            "contracts/cygnus-core/Hangar18.sol": {
                version: "0.8.17",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
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
        },
        // Optimism
        optimism: {
            url: "https://rpc.ankr.com/optimism",
            chainId: 10,
        },
        bsc: {
            url: "https://rpc.ankr.com/bsc",
            chainId: 56,
        },
    },
    mocha: {
        timeout: 100000000,
    },
};
