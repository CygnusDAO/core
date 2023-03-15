const hre = require("hardhat")
const ethers = hre.ethers
const { LedgerSigner } = require("@anders-t/ethers-ledger")

/*
 * Deployment checks:
 *
 * 1. Get deployed factory address
 * 2. Assign orbiter name for the DEX (Sushi, Velodrome, etc.)
 * 3. Deploy orbiters and initialize in Factory
 *
 */
async function deployOrbiters() {
    // Path
    const path = `44'/60'/2'/0/0`
    // Deployer
    const deployer = new LedgerSigner(hre.ethers.provider, path)
    const deployerAddress = await deployer.getAddress()

    // 3
    console.log("--------------------------------------------------------")
    console.log("Deploying with: %s", deployerAddress)
    console.log("Path: %s", path)
    console.log("--------------------------------------------------------")
    console.log("\n")

    // ----------------------------- SETUP ----------------------------- //
    //
    // Orbiter Name
    const deployedFactory = "0xc6842f698f19cb55be64af54a8ba681f22af1876"
    const orbiterName = "Sushiswap"
    const orbiterId = "0"

    console.log("--------------------------------------------------------")
    console.log("Deploying Orbiters: Albireo")
    console.log("--------------------------------------------------------")

    const Albireo = await ethers.getContractFactory("AlbireoOrbiter")
    const albireo = await Albireo.connect(deployer).deploy({
        maxFeePerGas: "339642997673",
        maxPriorityFeePerGas: "31000000000",
        gasLimit: "7000000",
    })
    await albireo.deployed()
    console.log("Albireo Deployed at: %s", albireo.address)

    console.log("--------------------------------------------------------")
    console.log("Deploying Orbiters: Deneb")
    console.log("--------------------------------------------------------")

    const Deneb = await ethers.getContractFactory("DenebOrbiter")
    const deneb = await Deneb.connect(deployer).deploy({
        maxFeePerGas: "339642997673",
        maxPriorityFeePerGas: "31000000000",
        gasLimit: "7000000",
    })
    await deneb.deployed()
    console.log("Deneb Deployed at: %s", deneb.address)

    console.log("--------------------------------------------------------")
    console.log("Initializing deployers in Factory")
    console.log("--------------------------------------------------------")

    const factory = await ethers.getContractAt("CygnusFactory", deployedFactory)
    await factory
        .connect(deployer)
        .initializeOrbiter(orbiterName, albireo.address, deneb.address, {
            maxFeePerGas: "339642997673",
            maxPriorityFeePerGas: "31000000000",
            gasLimit: "7000000",
        })

    console.log("Orbiters initialized:")

    const orbiter = await factory.getOrbiters(orbiterId)
    console.log(orbiter)
}

deployOrbiters()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
