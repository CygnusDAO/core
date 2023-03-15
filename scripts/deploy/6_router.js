const hre = require("hardhat")
const ethers = hre.ethers
const { LedgerSigner } = require("@anders-t/ethers-ledger")

/*
 * Deployment checks:
 *
 * 1. Factory address
 * 2. One Inch aggregator
 *
 */
async function deployRouter() {
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
    const factory = "0xC6842f698F19cB55be64Af54A8Ba681F22aF1876"
    // Oracle Denom Aggregator
    const oneInch = "0x1111111254eeb25477b68fb85ed929f73a960582"

    // ----------------------------- SETUP ----------------------------- //

    console.log("\n")
    console.log("--------------------------------------------------------")
    console.log("Deploying Router")
    console.log("--------------------------------------------------------")
    console.log("\n")

    // Router factory
    const Router = await ethers.getContractFactory("CygnusAltairX")

    // router
    const router = await Router.connect(deployer).deploy(factory, oneInch, {
        maxFeePerGas: "339642997673",
        maxPriorityFeePerGas: "31000000000",
        gasLimit: "7000000",
    })

    await router.deployed()

    console.log("Router deployed at: %s", router.address)
}

deployRouter();

