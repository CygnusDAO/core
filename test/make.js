// JS
const fs = require('fs');
const path = require('path');

// Hardhat
const hre = require('hardhat');
const ethers = hre.ethers;

/*////////////////////////////////////////////////////////////
 /                                                           /
 /              SETUP OF ALL CYGNUS CONTRACTS                /
 /                                                           /
 ////////////////////////////////////////////////////////////*/
module.exports = async function make() {
    // Addresses in this chain //

    // 1. LP Token address -----------------------------------------------------
    const lpTokenAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // 2. DAI address on this chain --------------------------------------------
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // 3. Native chain token ---------------------------------------------------
    const nativeAddress = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    // 4. Chainlink aggregators ------------------------------------------------

    // DAI aggregator
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';
    // Token0 from LP Token
    const token0Aggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';
    // Token1 from LP Token
    const token1Aggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    // 5. DEX of this LP Token -------------------------------------------------

    // Name
    const orbiterName = 'TraderJoe';

    ///////////////////////////////// OPTIONAL /////////////////////////////////
    // ---------------------------- Cygnus Void --------------------------------

    // Dex router
    const voidRouter = '0x60ae616a2155ee3d9a68541ba4544862310933d4';
    // Masterchef for this LP Token
    const masterChef = '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F';
    // reward token
    const rewardToken = '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd';
    // Pool ID in the masterchef
    const pid = 6;
    // Dex swap fee
    const swapFee = 997;

    // ═══════════════════ 0. SETUP ══════════════════════════════════════════════════════════

    // Admin and ReservesManager
    [owner, daoReservesManager, safeAddress1] = await ethers.getSigners();

    // Make contract
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/dai.json')).toString();
    const dai = new ethers.Contract(daiAddress, daiAbi, owner);

    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();
    const lpToken = new ethers.Contract(lpTokenAddress, lpTokenAbi, owner);

    // ═══════════════════ 1. ORACLE ═══════════════════════════════════════════════════════════

    const Oracle = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy with Chainlink's dai Aggregator
    const oracle = await Oracle.deploy(daiAggregator);

    // Initialize oracle, else the deployment for this lending pool fails
    await oracle.initializeNebula(lpTokenAddress, token0Aggregator, token1Aggregator);

    console.log('──────────────────────────────────────────────────────────────────────────────');
    console.log('Cygnus LP Oracle   | %s', oracle.address);
    console.log('──────────────────────────────────────────────────────────────────────────────');

    // ═══════════════════ 2. BORROW DEPLOYER ══════════════════════════════════════════════════

    const Albireo = await ethers.getContractFactory('AlbireoOrbiter');

    const albireo = await Albireo.deploy();

    console.log('Borrow Orbiter     | %s', albireo.address);
    console.log('──────────────────────────────────────────────────────────────────────────────');

    // ═══════════════════ 3. COLLATERAL DEPLOYER ═════════════════════════════════════════════

    const Deneb = await ethers.getContractFactory('DenebOrbiter');

    const deneb = await Deneb.deploy();

    console.log('Collateral Orbiter | %s', deneb.address);
    console.log('──────────────────────────────────────────────────────────────────────────────');

    // ═══════════════════ 4. FACTORY ═════════════════════════════════════════════════════════

    // Factory
    const Factory = await ethers.getContractFactory('CygnusFactory');

    const factory = await Factory.deploy(
        owner.address,
        daoReservesManager.address,
        daiAddress,
        nativeAddress,
        oracle.address,
    );

    // Orbiter
    const orbiter = await factory.setNewOrbiter(orbiterName, deneb.address, albireo.address);

    console.log('Cygnus Factory     | %s', factory.address);
    console.log('──────────────────────────────────────────────────────────────────────────────');
    console.log('Cygnus Reserves    | %s', await factory.vegaTokenManager());
    console.log('──────────────────────────────────────────────────────────────────────────────');

    // ═══════════════════ 5. ROUTER ══════════════════════════════════════════════════════════

    // Router
    const Router = await ethers.getContractFactory('CygnusAltairX');

    const router = await Router.deploy(factory.address);

    console.log('Cygnus Router      | %s', router.address);
    console.log('──────────────────────────────────────────────────────────────────────────────');

    // ═══════════════════ 6. SHUTTLE ════════════════════════════════════════════════════════

    // custom pool rates for the JoeAvax lending pool
    const baseRate = BigInt(0.08e18);

    const multiplier = BigInt(0.15e18);

    const kinkMultiplier = BigInt(3);

    // Shuttle with LP Token address from setup
    await factory.deployShuttle(lpToken.address, 0, baseRate, multiplier, kinkMultiplier);

    const shuttle = await factory.getShuttles(lpToken.address);

    // ═══════════════════════════════════════════════════════════════════════════════════════

    console.log('Cygnus Collateral  | %s', shuttle.collateral);
    console.log('──────────────────────────────────────────────────────────────────────────────');
    console.log('Cygnus Borrowable  | %s', shuttle.cygnusDai);
    console.log('──────────────────────────────────────────────────────────────────────────────');


    // Borrowable and collateral contracts
    const borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusDai, owner);

    const collateral = await ethers.getContractAt('CygnusCollateral', shuttle.collateral, owner);

    // Return standard + optional void (router, masterchef, reward token, pid, swapfee)
    return [oracle, factory, router, borrowable, collateral, dai, lpToken, voidRouter, masterChef, rewardToken, pid, swapFee];
};
