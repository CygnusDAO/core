const hre = require("hardhat")
const ethers = hre.ethers
const { LedgerSigner } = require("@anders-t/ethers-ledger")

/*
 * Deployment checks:
 *
 * 1. Get Pool ID
 * 2. Get Collateral Contract Address
 * 3. Initialize strategy with Pool ID
 */
async function initalizeVoid() {
    // Path
    const path = `44'/60'/2'/0/0`
    // Deployer
    const deployer = new LedgerSigner(hre.ethers.provider, path)

    console.log("--------------------------------------------------------")
    console.log("Initializing Strategy")
    console.log("--------------------------------------------------------")

    const collateralAddress = ""

    // Pool ID in the masterchef
    const pid = 0

    const collateral = await ethers.getContractAt("CygnusCollateral", collateralAddress)

    await collateral.connect(deployer).chargeVoid(pid)

    console.log("Strategy initialized for pool ID: %s", pid)
}

initalizeVoid()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
