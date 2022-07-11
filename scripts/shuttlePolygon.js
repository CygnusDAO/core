const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');
const { time } = require('@openzeppelin/test-helpers');

// POLYGON SCRIPT FOR LENDING POOL

/*
 *  Deploys a lending pool on Polygon. We use the LP Token Matic/Eth from sushiswap as an example and 
 *  the corresponding masterchef and pool Id: https://polygonscan.com/token/0xc4e595acDD7d12feC385E5dA5D43160e8A0bAC0E
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

    // Matic/Eth LP Token
    const maticEthLPAddress = '0xc4e595acDD7d12feC385E5dA5D43160e8A0bAC0E';

    // LP Token ABI and DAI Abi
    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // DAI Contract on Polygon
    const daiAddress = '0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063';

    // Dai ABI
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // Native MATIC
    const native = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';

    // ═══════════════════ 1. ORACLE ════════════════════════════════════════════════════════════════════════

    // Oracle
    const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy with CHAINLINK'S DAI AGGREGATOR on Polygon
    const nebula = await Nebula.deploy('0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D');

    console.log('Nebula Oracle:', nebula.address);

    // Initialize oracle, else the deployment of this pool fails
    await nebula.initializeNebula(
        maticEthLPAddress,
        '0xAB594600376Ec9fD91F8e885dADF0CE036862dE0',
        '0xF9680D99D6C9589e2a93a78A04A279e509205945',
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

    const router = await Router.deploy(
        factory.address,
        deneb.address,
        albireo.address,
        // WMATIC
        native,
    );

    console.log('Router:', router.address);

    // ═══════════════════ SHUTTLE ══════════════════════════════════════════════════════════════════════════

    // Pool customs
    const baseRate = BigInt(0.08e18);

    const kink = BigInt(0.75e18);

    const multi = BigInt(0.15e18);

    // Shuttle with LP Token https://polygonscan.com/token/0xc4e595acDD7d12feC385E5dA5D43160e8A0bAC0E
    await factory.deployShuttle(maticEthLPAddress, baseRate, multi, kink);

    const shuttle = await factory.getShuttles(maticEthLPAddress);

    console.log(shuttle);

    // ═══════════════════ IMPERSONATE ACCOUNTS ═════════════════════════════════════════════════════════════

    // BORROWER AND LENDER 1

    // Borrower: Random LP Holder for MATIC / ETH
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0x9854179bbbda1154f439116d31a646b15ec26e2d'],
    });

    const borrower = await ethers.provider.getSigner('0x9854179bbbda1154f439116d31a646b15ec26e2d');

    // Lender: DAI Whale
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0xc06320d9028f851c6ce46e43f04aff0a426f446c'],
    });

    const lender = await ethers.provider.getSigner('0xc06320d9028f851c6ce46e43f04aff0a426f446c');

    // BORROWER AND LENDER 2

    // Borrower: Random LP Holder for MATIC / ETH
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0x085ff264ee5cea5f54acdd82188fbe1923d62c8d'],
    });

    // ═════════════════════ CONTRACTS ══════════════════════════════════════════════════════════════════════

    // Connect with borrower
    const maticEthLP = new ethers.Contract(maticEthLPAddress, lpTokenAbi, borrower);

    // Connect with lender
    const DAI = new ethers.Contract(daiAddress, daiAbi, lender);

    // Get deployed collateral contract
    let collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, borrower);

    // Get deployed borrowable contract
    let borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, lender);

    // ═════════════════════ INITIALIZE CYGNUSVOID ══════════════════════════════════════════════════════════

    // Initialize with: SUSHI ROUTER / MiniChefV2 / SUSHI / 0 pool id / swapfee
    await collateral
        .connect(owner)
        .initializeVoid(
            '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
            '0x0769fd68dFb93167989C6f7254cd0D766Fb2841F',
            '0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a',
            0,
            997,
        );

    /********************************************************************************************************
   
    
     CYGNUS INTERACTIONS - Connect to the router and test mint functions for borrow and collateral contracts,
                           and borrow 1 DAI
    
     
     ********************************************************************************************************/

    // Approve router in LP
    await maticEthLP.connect(borrower).approve(router.address, max);

    // Mint CygLP
    await router.connect(borrower).mint(collateral.address, BigInt(10e18), borrower._address, max);

    // Approve router in DAI
    await DAI.connect(lender).approve(router.address, max);

    // Mint CygDAI
    await router.connect(lender).mint(borrowable.address, BigInt(1000e18), lender._address, max);

    // Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);

    // Borrow
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
