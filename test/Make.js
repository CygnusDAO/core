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
    const chainId = 137; // For 1inch

    // Matic / ETH
    const lpTokenAddress = "0x3cc20a6795c4b57d9817399f68e83e71c8626580";

    // Set the USDC address on this chain
    const usdcAddress = "0x2791bca1f2de4661ed88a30c99a7a9449aa84174";

    // Set the native chain token address (ie WETH)
    const nativeAddress = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270";

    // Set the Chainlink aggregator addresses for USDC
    const usdcAggregator = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";

    // Set the chainlink aggregator addresses for the LP token's assets (token0/token1)
    const aggregators = ["0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7", "0xF9680D99D6C9589e2a93a78A04A279e509205945"];

    // Set a friendly name for the orbiter
    const orbiterName = "Gamma: Concentrated LP";

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
    // Deploy registry first
    const Registry = await ethers.getContractFactory("CygnusNebulaRegistry");
    const registry = await Registry.deploy();

    // Deploy nebula
    const Nebula = await ethers.getContractFactory("CygnusNebula");
    const nebula = await Nebula.deploy(usdcAddress, usdcAggregator, registry.address);

    // Add nebula to registry
    await registry.createNebula(nebula.address);
    // Initialize LP Oracle
    await registry.createNebulaOracle(0, lpTokenAddress, aggregators);

    await nebula.lpTokenPriceUsd(lpTokenAddress);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus LP Registry | %s", chalk.yellowBright(registry.address));
    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus LP Oracle   | %s", chalk.yellowBright(nebula.address));

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
    const factory = await Factory.deploy(owner.address, daoReserves.address, usdcAddress, nativeAddress, registry.address);

    // Initialize the factory with the Albireo and Deneb orbiter instances, and the CygnusNebulaOracle instance
    await factory.initializeOrbiter(orbiterName, albireo.address, deneb.address);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Factory     | %s", chalk.green(factory.address));

    const DAOReserves = await ethers.getContractFactory("CygnusDAOReserves");
    const reserves = await DAOReserves.deploy(factory.address);
    await factory.setPendingDaoReserves(reserves.address);
    await factory.setNewDaoReserves();

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
    const Router = await ethers.getContractFactory("CygnusAltair");
    const router = await Router.deploy(factory.address);

    const RouterX = await ethers.getContractFactory("CygnusAltairX");
    const routerX = await RouterX.deploy(factory.address, orbiterName, registry.address);
    await router.setAltairExtension(0, routerX.address);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Router      | %s", chalk.magentaBright(router.address));

    // ═══════════════════ 7. CYG TOKEN ════════════════════════════════════════════════════════

    // CYG token
    const CygToken = await ethers.getContractFactory("Cygnus");
    const cygToken = await CygToken.deploy();

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Token       | %s", chalk.cyanBright(cygToken.address));

    // ═══════════════════ 8. CYG REWARDER ═════════════════════════════════════════════════════

    // CYG Rewarder
    const CygRewarder = await ethers.getContractFactory("PillarsOfCreation");

    // 2_000_000 Tokens as an example
    const totalCygRewards = BigInt(1_750_000e18);
    const totalCygRewardsDAO = BigInt(500_000e18);

    // Deploy with totalCyg rewards as 3M and the contract creates the emissions curve
    const cygRewarder = await CygRewarder.deploy(factory.address, cygToken.address, totalCygRewards, totalCygRewardsDAO);

    // Set rewarder in borrowable
    await borrowable.setPillarsOfCreation(cygRewarder.address);

    // Transfer ownership
    await cygToken.connect(owner).transferOwnership(cygRewarder.address);

    await cygRewarder.initializePillars();

    // Initialize rewarder for shuttle ID 0 with 1000 alloc points
    await cygRewarder.setLendingRewards(borrowable.address, 1000);
    await cygRewarder.setBorrowRewards(borrowable.address, collateral.address, 1000);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus Rewarder    | %s", chalk.cyanBright(cygRewarder.address));

    // ═══════════════════ 9. X1 Vault ═════════════════════════════════════════════════════

    const Vault = await ethers.getContractFactory("CygnusX1Vault");
    const vault = await Vault.deploy(factory.address, cygToken.address);

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnus X1 Vault    | %s", chalk.cyanBright(vault.address));

    // Set the X1 Vault (not needed)
    await factory.setCygnusX1Vault(vault.address);

    // ═══════════════════ 10. DAO Reserves ═════════════════════════════════════════════════════

    console.log("\t-----------------------------------------------------------------------------");
    console.log("\tCygnusDAO Reserves | %s", chalk.whiteBright(reserves.address));
    console.log("\t-----------------------------------------------------------------------------");

    // Needed
    await reserves.setCYGToken(cygToken.address);

    // ═════════════════════════════════════════════════════════════════════════════════════════

    return [
        nebula, // CygnusNebulaOracle.sol
        factory, // Hangar18.sol
        router, // CygnusAltairX.sol
        borrowable, // The CygnusBorrow.sol contract instance which accepts stablecoin deposits
        collateral, // The CygnusCollateral.sol contract instance which accepts LP Token deposits
        usdc, // The Borrowable's underlying stablecoin contract instance
        lpToken, // The collateral's underlying LP Token contract instance
        chainId, // The chain ID used for 1inch swaps
        cygRewarder, // ComplexRewarder.sol
        vault, // CygnusX1Vault.sol
        reserves,
        cygToken,
        registry,
    ];
};
