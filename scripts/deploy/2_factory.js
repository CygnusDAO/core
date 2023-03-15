const hre = require("hardhat")
const ethers = hre.ethers
const { LedgerSigner } = require("@anders-t/ethers-ledger")

/*
 * Deployment checks:
 *
 * 1. Get DAO reserves address
 * 2. Get lending token address (USDC, BUSD, DAI, stablecoin)
 * 3. Get native address (WETH, WMATIC, WFTM, etc.)
 * 4. Get deployed oracle address
 */
async function deployFactory() {
    // Path
    const path = `44'/60'/2'/0/0`
    // Deployer
    const deployer = new LedgerSigner(hre.ethers.provider, path)
    const deployerAddress = await deployer.getAddress()

    console.log("--------------------------------------------------------")
    console.log("Deploying with: %s", deployerAddress)
    console.log("Path: %s", path)
    console.log("--------------------------------------------------------")
    console.log("\n")

    // ----------------------------- SETUP ----------------------------- //

    // Vault address
    const daoReserves = "0x90e9Ecc016A6971Cd28ceE85C53e72517A451a38"
    const usd = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
    const native = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"
    const oracle = "0xBF6f2C9E753583700Ce55cDAb271F83C6d5D0488"

    console.log("\n")
    console.log("--------------------------------------------------------")
    console.log("Deploying Factory")
    console.log("--------------------------------------------------------")
    console.log("\n")

    // Deploy
    const Factory = await ethers.getContractFactory("CygnusFactory")

    const factory = await Factory.connect(deployer).deploy(deployerAddress, daoReserves, usd, native, oracle, {
        maxFeePerGas: "339642997673",
        maxPriorityFeePerGas: "31000000000",
        gasLimit: "7000000",
    })

    await factory.deployed()

    console.log("Factory deployed at: %s", factory.address)
}

deployFactory()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
