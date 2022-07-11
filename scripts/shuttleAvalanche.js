const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');

// AVALANCHE SCRIPT FOR LENDING POOL

/*
 *  Deploys a lending pool on Avalanche. We use the LP Token Joe/Avax from Traderjoe as an example and 
 *  the corresponding masterchef and pool Id: https://snowtrace.com/token/0x454E67025631C065d3cFAD6d71E6892f74487a15
 *
 *  The steps to deploy a lending pool is as follows:
 *
 *     1. Deploy oracle and initialize the LP Token pair we want to get the price of
 *     2. Deploy the `collateral deployer` contract which deploys collaterals for Cygnus
 *     3. Deploy the `borrow deployer` contract which deploys the borrow contracts for Cygnus
 *     4. Deploy the factory with the above addresses
 *     5. Deploy the router for ease of use with contracts
 *     6. Deploy Shuttle from the factory with the address of the LP Token we want to create a lending pool with
 *     7. Initialize CygnusCollateralVoid
 */
async function deploy() {
    // Constants
    const max = ethers.constants.MaxUint256;

    // Signer and reservesManager
    const [owner, reservesManager] = await ethers.getSigners();

    // ═══════════════════ 0. SETUP ══════════════════════════════════════════════

    // JOE/AVAX LP Token
    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // LP Token and DAI ABI
    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // DAI Contract on Avalanche
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // DAI ABI
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // Native AVAX
    const native = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    // ═══════════════════ 1. ORACLE ════════════════════════════════════════════════════════════════════════

    // Oracle
    const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy with DAI denomination --> CHAINLINK's DAI AGGREGATOR
    const nebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

    console.log('Nebula Oracle:', nebula.address);

    // Initialize oracle, else the deployment of this pool fails
    await nebula.initializeNebula(
        joeAvaxLPAddress,
        '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a',
        '0x0A77230d17318075983913bC2145DB16C7366156',
    );

    // ═══════════════════ 2. COLLATERAL DEPLOYER ═══════════════════════════════════════════════════════════

    const Deneb = await ethers.getContractFactory('CygnusDeneb');

    const deneb = await Deneb.deploy();

    console.log('CollateralDeployer:', deneb.address);

    // ═══════════════════ 3. BORROWABLE DEPLOYER ═══════════════════════════════════════════════════════════

    const Albireo = await ethers.getContractFactory('CygnusAlbireo');

    const albireo = await Albireo.deploy();

    console.log('BorrowDeployer', albireo.address);

    // ═══════════════════ 4. FACTORY ═══════════════════════════════════════════════════════════════════════

    // Factory
    const Factory = await ethers.getContractFactory('CygnusFactory');

    const factory = await Factory.deploy(
        owner.address,
        reservesManager.address,
        daiAddress,
        native,
        deneb.address,
        albireo.address,
        nebula.address,
    );

    console.log('Cygnus Factory:', factory.address);

    // ═══════════════════ 5. ROUTER ════════════════════════════════════════════════════════════════════════

    // Router
    const Router = await ethers.getContractFactory('CygnusAltair');

    const router = await Router.deploy(factory.address);

    console.log('Router:', router.address);

    // ═══════════════════ SHUTTLE ══════════════════════════════════════════════════════════════════════════

    // Pool customs
    const baseRate = BigInt(0.08e18);

    const kink = BigInt(0.75e18);

    const multi = BigInt(0.15e18);

    // Shuttle with LP Token 
    await factory.deployShuttle(joeAvaxLPAddress, baseRate, multi, kink);

    const shuttle = await factory.getShuttles(joeAvaxLPAddress);

    console.log(shuttle);

    // ═══════════════════ IMPERSONATE ACCOUNTS ═════════════════════════════════════════════════════════════

    // BORROWER AND LENDER 1

    // Borrower: Random LP Holder for JOE/AVAX
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0x0f1410a815105f4429a404d2101890aa11d97951'],
    });

    const borrower = await ethers.provider.getSigner('0x0f1410a815105f4429a404d2101890aa11d97951');

    // Lender: DAI Whale
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0x277b09605debf23776e87aa4cebbf85d8a0da353'],
    });

    const lender = await ethers.provider.getSigner('0x277b09605debf23776e87aa4cebbf85d8a0da353');

    // ═════════════════════ CONTRACTS ══════════════════════════════════════════════════════════════════════

    // Connect with borrower
    const joeAvaxLP = new ethers.Contract(joeAvaxLPAddress, lpTokenAbi, borrower);

    // Connect with lender
    const DAI = new ethers.Contract(daiAddress, daiAbi, lender);

    // Get deployed collateral contract
    const collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, borrower);

    // Get deployed borrow contract
    const borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, lender);

    // ═════════════════════ INITIALIZE MINICHEF ════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral
        .connect(owner)
        .initializeVoid(
            '0x60ae616a2155ee3d9a68541ba4544862310933d4',
            '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F',
            '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd',
            6,
            997,
        );

    /********************************************************************************************************
   
    
     CYGNUS INTERACTIONS - Connect to the router and test mint functions for borrow and collateral contracts,
                           and borrow 1 DAI
    
     
     ********************************************************************************************************/


    // Borrower mints collateral

    await joeAvaxLP.connect(borrower).approve(router.address, max);

    await router.connect(borrower).mint(collateral.address, BigInt(1e18), borrower._address, max);

    // Lender mints borrowable
 
    await DAI.connect(lender).approve(router.address, max);

    await router.connect(lender).mint(borrowable.address, BigInt(10e18), lender._address, max);

    // Borrower borrows 1 DAI

    await borrowable.connect(borrower).borrowApprove(router.address, max);

    await router.connect(borrower).borrow(borrowable.address, BigInt(1e18), borrower._address, max, '0x');

    // Check that user has Dai
    let borrowersDaiBalance = await DAI.balanceOf(borrower._address);

    console.log('Borrowers DAI Balance: %s', borrowersDaiBalance);

    console.log('Total Balance of collateral before reinvesting: %s', await collateral.totalBalance());

    console.log('----------------------- 10 Days pass -----------------------');

    await time.increase(60 * 60 * 24 * 10);

    await collateral.connect(borrower).reinvestRewards();

    console.log('Total Balance of collateral after reinvesting: %s', await collateral.totalBalance());
}

deploy();
/*
module.exports = {
    deploy,
};
*/
