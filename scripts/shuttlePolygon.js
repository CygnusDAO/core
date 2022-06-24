const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');
const { time } = require('@openzeppelin/test-helpers');

async function deploy() {
    // Constants
    const max = ethers.constants.MaxUint256;

    const addressZero = ethers.constants.AddressZero;

    // Signer and reservesManager
    const [owner, reservesManager] = await ethers.getSigners();

    // ═══════════════════ 0. SETUP ══════════════════════════════════════════════

    // Matic/Eth LP Token
    const maticEthLPAddress = '0xc4e595acDD7d12feC385E5dA5D43160e8A0bAC0E';

    // Native
    const native = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';

    // DAI Contract
    const daiAddress = '0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063';

    // LP Token ABI
    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // ═══════════════════ 1. ORACLE ════════════════════════════════════════════════════════════════════════

    // Oracle
    const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy with DAI denomination --> CHAINLINK's DAI AGGREGATOR
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

    const borrowerFirstDepositor = await ethers.provider.getSigner('0x085ff264ee5cea5f54acdd82188fbe1923d62c8d');

    // Lender: DAI Whale
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0x06959153b974d0d5fdfd87d561db6d8d4fa0bb0b'],
    });

    const lenderFirstDepositor = await ethers.provider.getSigner('0x06959153b974d0d5fdfd87d561db6d8d4fa0bb0b');

    // ═════════════════════ CONTRACTS ══════════════════════════════════════════════════════════════════════

    // Connect with borrower
    const maticEthLP = new ethers.Contract(maticEthLPAddress, lpTokenAbi, borrower);

    // Connect with lender
    const DAI = new ethers.Contract(daiAddress, daiAbi, lender);

    let collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, borrower);

    let borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, lender);

    // ═════════════════════ INITIALIZE MINICHEF ════════════════════════════════════════════════════════════

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

    /***********************************************************
   
    
                            INTERACTIONS
    
     
     ***********************************************************/

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
    await router.connect(borrower).borrow(borrowable.address, BigInt(0.01e18), borrower._address, max, '0x');

    // Check that we have dai
    const x = await DAI.balanceOf(borrower._address);

    console.log(x);
}

deploy();
/*
module.exports = {
    deploy,
};
*/
