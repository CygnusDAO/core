// JS
const fs = require("fs");
const path = require("path");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

/*////////////////////////////////////////////////////////////
 /                                                           /
 /              SETUP OF ALL CYGNUS CONTRACTS                /
 /                                                           /
 ////////////////////////////////////////////////////////////*/
module.exports = async function Make() {
  // Addresses in this chain //

  // 1. LP Token address -----------------------------------------------------
  const lpTokenAddress = "0x454e67025631c065d3cfad6d71e6892f74487a15";

  // 2. USDC address on this chain --------------------------------------------
  const usdcAddress = "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e";

  // 3. Native chain token ---------------------------------------------------
  const nativeAddress = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";

  // 4. Chainlink aggregators ------------------------------------------------

  // USDC aggregator
  const usdcAggregator = "0xF096872672F44d6EBA71458D74fe67F9a77a23B9";
  // Token0 from LP Token
  const token0Aggregator = "0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a";
  // Token1 from LP Token
  const token1Aggregator = "0x0A77230d17318075983913bC2145DB16C7366156";

  // 5. DEX of this LP Token -------------------------------------------------

  // Name
  const orbiterName = "TraderJoe";

  // 6. DEX Aggregator (1 Inch)
  //
  const oneInchAggregatorV4 = '0x1111111254fb6c44bac0bed2854e76f90643097d';

  // ═══════════════════ 0. SETUP ══════════════════════════════════════════════════════════

  // Admin and ReservesManager
  [owner, daoReserves, safeAddress1] = await ethers.getSigners();

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
  const orbiter = await factory.initializeOrbiter(orbiterName, albireo.address, deneb.address);

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

  // custom pool rates for the JoeAvax lending pool
  const baseRate = BigInt(0);

  const multiplier = BigInt(0);

  // Shuttle with LP Token address from setup
  await factory.deployShuttle(lpToken.address, 0, baseRate, multiplier);

  const shuttle = await factory.getShuttles(lpToken.address, 0);

  // ═══════════════════════════════════════════════════════════════════════════════════════

  console.log("Cygnus Collateral  | %s", shuttle.collateral);
  console.log("──────────────────────────────────────────────────────────────────────────────");
  console.log("Cygnus Borrowable  | %s", shuttle.borrowable);
  console.log("──────────────────────────────────────────────────────────────────────────────");

  // Borrowable and collateral contracts
  const borrowable = await ethers.getContractAt("CygnusBorrow", shuttle.borrowable, owner);

  const collateral = await ethers.getContractAt("CygnusCollateral", shuttle.collateral, owner);

  // Return standard + optional void (router, masterchef, reward token, pid, swapfee)
  return [oracle, factory, router, borrowable, collateral, usdc, lpToken];
};
