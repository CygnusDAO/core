const hre = require("hardhat")
const ethers = hre.ethers
const { LedgerSigner } = require("@anders-t/ethers-ledger")

/*
 * Deployment checks:
 *
 * 1. Get the denomination token (USDC, BUSD, etc.);
 * 2. Get the denomination token chainlink aggreagtor
 * 3. Deploy oracle
 */
async function deployOracle() {
    // Path
    const path = `44'/60'/2'/0/0`
    // Deployer
    const deployer = new LedgerSigner(hre.ethers.provider, path)
    const deployerAddress = await deployer.getAddress()

    console.log("--------------------------------------------------------")
    console.log("Deploying with: %s", deployerAddress)
    console.log("Path: %s", deployerAddress)
    console.log("--------------------------------------------------------")
    console.log("\n")

    // ----------------------------- SETUP ----------------------------- //

    // Oracle Denom Asset
    const lendingToken = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
    // Oracle Denom Aggregator
    const lendingTokenChainlink = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7"

    // ----------------------------- SETUP ----------------------------- //

    console.log("\n")
    console.log("--------------------------------------------------------")
    console.log("Deploying Oracle")
    console.log("--------------------------------------------------------")
    console.log("\n")

    // Oracle
    const Oracle = await ethers.getContractFactory("CygnusNebulaOracle")
    // oracle
    const oracle = await Oracle.connect(deployer).deploy(lendingToken, lendingTokenChainlink, {
        maxFeePerGas: "339642997673",
        maxPriorityFeePerGas: "31000000000",
        gasLimit: "7000000",
    })

    await oracle.deployed()

    console.log("Oracle deployed at: %s", oracle.address)
}

deployOracle()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
