// JS
const fs = require("fs");
const path = require("path");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

/**
 * @notice Main test setup
 */
module.exports = async function Make() {
  // 0. Chain ID
  const chainId = 137;

  // Addresses in this chain //

  // 1. LP Token address -----------------------------------------------------
  const lpTokenAddress = "0xc4e595acdd7d12fec385e5da5d43160e8a0bac0e";

  // 2. USDC address on this chain --------------------------------------------
  const usdcAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";

  // 3. Native chain token ---------------------------------------------------
  const nativeAddress = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";

  // 4. Chainlink aggregators ------------------------------------------------

  // USDC aggregator
  const usdcAggregator = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
  // Token0 from LP Token
  const token0Aggregator = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
  // Token1 from LP Token
  const token1Aggregator = "0xF9680D99D6C9589e2a93a78A04A279e509205945";

  // 5. DEX of this LP Token -------------------------------------------------

  // Name
  const orbiterName = "Sushiswap";

  // 6. DEX Aggregator (1 Inch)
  //
  const oneInchAggregatorV4 = "0x1111111254eeb25477b68fb85ed929f73a960582";

  // ═══════════════════ 0. SETUP ══════════════════════════════════════════════════════════

  // Admin and ReservesManager
  const [owner, daoReserves] = await ethers.getSigners();

  // Make contract
  const usdcAbi = fs.readFileSync(path.resolve(__dirname, "./abis/usdc.json")).toString();
  const usdc = new ethers.Contract(usdcAddress, usdcAbi, owner);

  const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, "./abis/lptoken.json")).toString();
  const lpToken = new ethers.Contract(lpTokenAddress, lpTokenAbi, owner);

  // ═══════════════════ 1. ORACLE ═══════════════════════════════════════════════════════════

  const Oracle = await ethers.getContractFactory("ChainlinkNebulaOracle");

  // Deploy with Chainlink's USDC Aggregator
  const oracle = await Oracle.deploy(usdcAggregator);

  // Initialize oracle, else the deployment for this lending pool fails
  await oracle.initializeNebula(lpTokenAddress, token0Aggregator, token1Aggregator);

  console.log("──────────────────────────────────────────────────────────────────────────────");
  console.log("Cygnus LP Oracle   | %s", oracle.address);
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // ═══════════════════ 2. BORROW DEPLOYER ══════════════════════════════════════════════════

  const Albireo = await ethers.getContractFactory("AlbireoOrbiter");

  const albireo = await Albireo.deploy();

  console.log("Borrow Orbiter     | %s", albireo.address);
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // ═══════════════════ 3. COLLATERAL DEPLOYER ═════════════════════════════════════════════

  const Deneb = await ethers.getContractFactory("DenebOrbiter");

  const deneb = await Deneb.deploy();

  console.log("Collateral Orbiter | %s", deneb.address);
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // ═══════════════════ 4. FACTORY ═════════════════════════════════════════════════════════

  // Factory
  const Factory = await ethers.getContractFactory("CygnusFactory");

  const factory = await Factory.deploy(owner.address, daoReserves.address, usdcAddress, nativeAddress, oracle.address);

  // Orbiter
  await factory.initializeOrbiter(orbiterName, albireo.address, deneb.address);

  console.log("Cygnus Factory     | %s", factory.address);
  console.log("──────────────────────────────────────────────────────────────────────────────");
  console.log("Cygnus Reserves    | %s", await factory.daoReserves());
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // ═══════════════════ 5. ROUTER ══════════════════════════════════════════════════════════

  // Router
  const Router = await ethers.getContractFactory("CygnusAltairX");

  const router = await Router.deploy(factory.address, oneInchAggregatorV4);

  console.log("Cygnus Router      | %s", router.address);
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // ═══════════════════ 6. SHUTTLE ════════════════════════════════════════════════════════

  // Shuttle with LP Token address from setup
  await factory.deployShuttle(lpToken.address, 0, 0, 0);

  const shuttle = await factory.getShuttles(lpToken.address, 0);

  // ═══════════════════════════════════════════════════════════════════════════════════════

  console.log("Cygnus Collateral  | %s", shuttle.collateral);
  console.log("──────────────────────────────────────────────────────────────────────────────");
  console.log("Cygnus Borrowable  | %s", shuttle.borrowable);
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // Borrowable and collateral contracts
  const borrowable = await ethers.getContractAt("CygnusBorrow", shuttle.borrowable);

  const collateral = await ethers.getContractAt("CygnusCollateral", shuttle.collateral);

  // Return standard + optional void (router, masterchef, reward token, pid, swapfee)
  return [oracle, factory, router, borrowable, collateral, usdc, lpToken, chainId];
};
