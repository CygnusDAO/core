const hre = require("hardhat");
const ethers = hre.ethers;
const { LedgerSigner } = require("@anders-t/ethers-ledger");

const { getAddress } = require("@ethersproject/address");

/*
 * Deployment checks:
 *
 * 1. Get addresses for NATIVE TOKEN, USDC and USDC AGGREGATOR for this chain
 * 2. Deploy Collateral Deployer
 * 3. Deploy Borrow Deployer
 * 4. Deploy Oracle with USDC Aggregator
 * 5. Deploy factory with addresses from 2,3,4 and reserves manager
 * 6. Deploy Router with factory address
 */
async function main() {
  // Path
  const path = `44'/60'/2'/0/0`;

  // Deployer
  const deployer = new LedgerSigner(hre.ethers.provider, path);
  const deployerAddress = await deployer.getAddress();

  console.log("--------------------------------------------------------");
  console.log("Deploying with: %s", deployerAddress);
  console.log("Path: %s", deployerAddress);
  console.log("--------------------------------------------------------");

  // ═══════════════════ 1. SETUP

  // const usdcAggregator = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
  // ═══════════════════ LP AND AGGREGATORS
  //
  const lpTokenAddress = "0xe62ec2e799305e0d367b0cc3ee2cda135bf89816";
  const token0Aggregator = "0xc907E116054Ad103354f2D350FD2514433D57F6f";
  const token1Aggregator = "0xF9680D99D6C9589e2a93a78A04A279e509205945";

  // ═══════════════════ ORBITER
  const voidRouter = "0x1b02da8cb0d097eb8d57a175b88c7d8b47997506";
  const masterChef = "0x0769fd68dfb93167989c6f7254cd0d766fb2841f";
  const rewardToken = "0x0b3f868e0be5597d5db7feb59e1cadbb0fdda50a";
  const pid = 3;

  // ═══════════════════ 2. ADD ORACLE
  const oracle = await ethers.getContractAt("ChainlinkNebulaOracle", "0x864e3d5c50eadff7859ea46854d4a0b5cacb74bd");
  await oracle.connect(deployer).initializeNebula(lpTokenAddress, token0Aggregator, token1Aggregator, {
    maxFeePerGas: "51178637350",
    maxPriorityFeePerGas: "31000000000",
  });

  const factory = await ethers.getContractAt("CygnusFactory", "0x8e2412f222e5159f4265b68be5ec4b3e01bcbf6c");
  await factory.connect(deployer).deployShuttle(lpTokenAddress, 0, 0, 0, {
    maxFeePerGas: "51178637350",
    maxPriorityFeePerGas: "31000000000",
  });

  const shuttles = await factory.getShuttles(lpTokenAddress, 0, {
    maxFeePerGas: "51178637350",
    maxPriorityFeePerGas: "31000000000",
  });

  const collateral = await ethers.getContractAt("CygnusCollateral", shuttles.collateral);

  await collateral
    .connect(deployer)
    .connect(deployer)
    .chargeVoid(voidRouter, masterChef, rewardToken, pid, {
      maxFeePerGas: "51178637350",
      maxPriorityFeePerGas: "31000000000",
    });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
