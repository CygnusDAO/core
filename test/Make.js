// JS
const fs = require("fs");
const path = require("path");
const chalk = require("chalk");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

/**
 *  The purpose of this script is to simulate the Cygnus contracts for testing/scripting purposes.
 *  It basically deploys all that is required for the full protocol to work, including factory,
 *  pool deployers, oracle, harvesters, periphery, core contracts, ts.
 *    1. Deploys CygnusNebulaOracle contract, which is the main oracle for the collateral
 *       - Initializes the LP token with the aggregators
 *    2. Deploys AlbireoOrbiter contract, which is used to deploy CygnusBorrow.sol
 *    3. Deploys DenebOrbiter contract, which is used to deploy CygnusCollateral.sol
 *    4. Deploys Hangar18 contract, which is the factory-like contract that deploys lending pools
 *       - Initializes the Hangar18 contract with the two orbiter contracts and the oracle contract.
 *    5. Deploys a CygnusAltairX contract, which is a router contract to interact with core
 *       (ie it's used to leverage/deleverage/borrow/repay/liquidate, etc.)
 *
 *  NOTE: Each step is logged to the console with the contract address once it has been completed.
 */
module.exports = async function Make() {
    /**
     *
     *                                    MAKE CYGNUS CORE
     *
     *  NOTE: When making the protocol from your own machine and you want to test different LPs,
     *        or chains, make sure to update the below (all variables until phase 1 `Oracle`):
     *
     *        `chainId`        - Used for the 1inch aggregator mainly
     *        `lpTokenAddress` - The address of the liquidity token on this chain
     *        `usdcAddress`    - The address of the USD Coin token on this chain
     *        `nativeAddress`  - The address of WETH, WFTM or native, used for 1inch mainly
     *        `usdcAggregator` - The address of the Chainlink Aggregator for the lending token.
     *                           You can find all addresses by chain here:
     *                           https://docs.chain.link/data-feeds/price-feeds/addresses/
     *        `aggregators`    - Array consisting of Chainlink Aggregators for the LP Token's assets
     *                           (ie if LP consists of BTC/ETH then use Chainlink'sBTC aggregator
     *                           and ETH aggregator. We use an array to make sure our oracle is
     *                           compatible with pools that use more than 2 tokens, such as Balancer
     *                           where they have BPTs of 5 tokens for example).
     *        `orbiterName`   -  Optional, it's useful when querying deployers from the factory contract.
     */
    // Set the chain ID
    const chainId = 10; // For 1inch

    // Hypervisor: ETH/USDC
    const lpTokenAddress = "0xB5C335Cfaf1769eE02597C6aC2db883F793A020D";

    // Set the USDC address on this chain
    const usdcAddress = "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8";

    // Set the native chain token address (ie WETH)
    const nativeAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1";

    // Set the Chainlink aggregator addresses for USDC
    const usdcAggregator = "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3";

    // Set the chainlink aggregator addresses for the LP token's assets (token0/token1)
    const aggregators = ["0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612", "0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6"];

    // Set a friendly name for the orbiter
    const orbiterName = "Zyberswap: Rewards";

    // You can create your own below or just leave as it is

    // Set the owner and daoReserves addresses
    const [owner, daoReserves] = await ethers.getSigners();

    // Create the USDC contract to return the contract object
    const usdcAbi = fs.readFileSync(path.resolve(__dirname, "../scripts/abis/usdc.json")).toString();
    const usdc = new ethers.Contract(usdcAddress, usdcAbi, owner);

    // Create the LP Token contract to return the contract object (this is a uniV2Pair contract
    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, "../scripts/abis/lptoken.json")).toString();
    const lpToken = new ethers.Contract(lpTokenAddress, lpTokenAbi, owner);

    // ═══════════════════ 1. ORACLE ═══════════════════════════════════════════════════════════

    // Create a CygnusNebulaOracle contract instance with the address of the denomination token (USDC)
    // and its Chainlink aggregator
    const Oracle = await ethers.getContractFactory("CygnusNebulaOracle");
    const oracle = await Oracle.deploy(usdcAddress, usdcAggregator);

    // Initialize the oracle for the LP token, which is necessary for the deployment of this lending pool to succeed
    await oracle.initializeNebula(lpTokenAddress, aggregators);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus LP Oracle   | %s", chalk.yellowBright(oracle.address));

    // ═══════════════════ 2. BORROW DEPLOYER ══════════════════════════════════════════════════

    // Deploy the CygnusBorrow deployer
    const Albireo = await ethers.getContractFactory("AlbireoOrbiter");
    const albireo = await Albireo.deploy();

    // ═══════════════════ 3. COLLATERAL DEPLOYER ══════════════════════════════════════════════

    // Deploy the CygnusCollateral deployer
    const Deneb = await ethers.getContractFactory("DenebOrbiter");
    const deneb = await Deneb.deploy();

    // ═══════════════════ 4. HANGAR18 ═════════════════════════════════════════════════════════

    // Create a Hangar18 factory contract instance
    const Factory = await ethers.getContractFactory("Hangar18");
    const factory = await Factory.deploy(owner.address, daoReserves.address, usdcAddress, nativeAddress);

    // Initialize the factory with the Albireo and Deneb orbiter instances, and the CygnusNebulaOracle instance
    await factory.initializeOrbiter(orbiterName, albireo.address, deneb.address, oracle.address);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Factory     | %s", chalk.green(factory.address));

    // ═══════════════════ 5. SHUTTLE ══════════════════════════════════════════════════════════

    // Deploy lending pool
    await factory.deployShuttle(lpToken.address, 0);

    // Get shuttle
    const shuttle = await factory.getShuttles(lpToken.address, 0);

    // Get the borrowable contract deployed
    const borrowable = await ethers.getContractAt("CygnusBorrow", shuttle.borrowable);

    // Get the collateral contract deployed
    const collateral = await ethers.getContractAt("CygnusCollateral", shuttle.collateral);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Collateral  | %s", chalk.green(shuttle.collateral));
    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Borrowable  | %s", chalk.green(shuttle.borrowable));

    // ═══════════════════ 6. ROUTER ═══════════════════════════════════════════════════════════

    // Deploy the CygnusAltairX router to do borrows, liquidations, leverage, deleverage, repays, etc.
    const Router = await ethers.getContractFactory("CygnusAltairX");
    const router = await Router.deploy(factory.address);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Router      | %s", chalk.magentaBright(router.address));

    // ═══════════════════ 7. CYG TOKEN ════════════════════════════════════════════════════════

    // CYG token
    const CygToken = await ethers.getContractFactory("CygnusERC20");
    const cygToken = await CygToken.deploy("Cygnus", "CYG", 18);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Token       | %s", chalk.redBright(cygToken.address));

    // ═══════════════════ 8. CYG REWARDER ═════════════════════════════════════════════════════

    // CYG Rewarder
    const CygRewarder = await ethers.getContractFactory("CygnusComplexRewarder");

    // 3_000_000 Tokens as an example
    const totalCygRewards = "3000000000000000000000000";

    // Deploy with totalCyg rewards as 3M and the contract creates the emissions curve
    const cygRewarder = await CygRewarder.deploy(factory.address, cygToken.address, totalCygRewards);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus X1 Vault    | %s", chalk.redBright(cygRewarder.address));
    console.log("\t-----------------------------------------------------------------------------");

    // Initialize rewarder
    await cygRewarder.initializeShuttleRewards(0, 1000);

    // Set rewarder in borrowable
    await borrowable.setCygnusBorrowRewarder(cygRewarder.address);

    // Send the 3 M tokens from Owner to rewarder
    await cygToken.transfer(cygRewarder.address, totalCygRewards);

    // Set the X1 Vault (not needed)
    await factory.setCygnusX1Vault(cygRewarder.address);

    // ═════════════════════════════════════════════════════════════════════════════════════════

    return [
        oracle, // The oracle contract instance.
        factory, // The hagar18 contract instance
        router, // The CygnusAltairX router contract instance
        borrowable, // The CygnusBorrow.sol contract instance which accepts stablecoin deposits
        collateral, // The CygnusCollateral.sol contract instance which accepts LP Token deposits
        usdc, // THe Borrowable's underlying stablecoin contract instance
        lpToken, // The collateral's underlying LP Token contract instance
        chainId, // The chain ID used for 1inch swaps
    ];
};
