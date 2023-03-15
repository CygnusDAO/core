const hre = require("hardhat");
const ethers = hre.ethers;
const { LedgerSigner } = require("@anders-t/ethers-ledger");

/*
 * Deployment checks:
 *
 * 1. Get Factory Address
 * 2. Get Oracle Address
 *
 * 3. Get LP Token Address (ie. WETH/MMATIC)
 * 4. Get Chainlink oracle for token A (WETH)
 * 5. Get Chainlink oracle for token B (MATIC)
 *
 * 6. Get Orbiter ID (Sushi, Pancakeswap, etc.)
 * 7. Set Base Rate and Multiplier
 * 8. Deploy
 *
 */
async function deployShuttle() {
  // Path
  const path = `44'/60'/2'/0/0`;
  // Deployer
  const deployer = new LedgerSigner(hre.ethers.provider, path);
  const deployerAddress = await deployer.getAddress();

  console.log("--------------------------------------------------------");
  console.log("Deploying with: %s", deployerAddress);
  console.log("Path: %s", path);
  console.log("--------------------------------------------------------");
  console.log("\n")

  // ----------------------------- SETUP ----------------------------- //

  // ETH-MATIC

  // Factory
  const factoryAddress = '0xC6842f698F19cB55be64Af54A8Ba681F22aF1876'
  const oracleAddress = '0xbf6f2c9e753583700ce55cdab271f83c6d5d0488'

  // LP
  const lpToken = '0x4b1f1e2435a9c96f7330faea190ef6a7c8d70001';
  const chainlinkTokenA = '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7';
  const chainlinkTokenB = '0x0A6513e40db6EB1b165753AD52E80663aeA50545'

  // Interest params
  const orbiterId = 0;
  const base = 0;
  const multi = 0;

  console.log("\n")
  console.log("--------------------------------------------------------");
  console.log("Initializing Oracle with LP");
  console.log("--------------------------------------------------------");

  const oracle = await ethers.getContractAt("CygnusNebulaOracle", oracleAddress);
  await oracle.connect(deployer).initializeNebula(lpToken, chainlinkTokenA, chainlinkTokenB, { maxFeePerGas: "339642997673", maxPriorityFeePerGas: "31000000000", gasLimit: "7000000", });

  console.log("Oracle initialized");
  console.log("\n")
  console.log("--------------------------------------------------------");
  console.log("Deploying Lending Pool");
  console.log("--------------------------------------------------------");
  console.log("\n")

  const factory = await ethers.getContractAt("CygnusFactory", factoryAddress);
  await factory.connect(deployer).deployShuttle(lpToken, orbiterId, base, multi, {
        maxFeePerGas: "339642997673",
        maxPriorityFeePerGas: "31000000000",
        gasLimit: "7000000",
    });

  console.log("Lending pool deployed. Shuttle:");

  console.log(await factory.getShuttles(lpToken, orbiterId));
}

deployShuttle()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
