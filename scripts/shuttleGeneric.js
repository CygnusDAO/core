const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');

async function deploy() {
    // Constants
    const max = ethers.constants.MaxUint256;

    const addressZero = ethers.constants.AddressZero;

    // Signer and reservesManager
    const [owner, reservesManager] = await ethers.getSigners();

    // ═══════════════════ 0. SETUP ══════════════════════════════════════════════

    // Joe/Avax LP Token contract
    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';
    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // DAI Contract
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

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
        '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70',
        '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
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
        // WAVAX
        '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
    );

    console.log('Router:', router.address);

    // ═══════════════════ SHUTTLE ══════════════════════════════════════════════════════════════════════════

    // Pool customs
    const baseRate = BigInt(0.08e18);
    const kink = BigInt(0.75e18);
    const multi = BigInt(0.15e18);

    // Shuttle with LP Token 0x454e67025631c065d3cfad6d71e6892f74487a15
    await factory.deployShuttle(joeAvaxLPAddress, baseRate, multi, kink);

    const shuttle = await factory.getShuttles(joeAvaxLPAddress);

    console.log(shuttle);

    // ═══════════════════ IMPERSONATE ACCOUNTS ═════════════════════════════════════════════════════════════

    // BORROWER AND LENDER 1

    // Borrower: Random LP Holder for JOE / AVAX
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

    const collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, borrower);

    const borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, lender);

    /********************************************************************************************************
   
    
                            CYGNUS INTERACTIONS
    
     
     ********************************************************************************************************/

    // Approve router in LP
    await joeAvaxLP.connect(borrower).approve(router.address, max);

    // Mint CygLP
    await router.connect(borrower).mint(collateral.address, BigInt(30e18), borrower._address, max);

    // Approve router in DAI
    await DAI.connect(lender).approve(router.address, max);

    // Mint CygDAI
    await router.connect(lender).mint(borrowable.address, BigInt(1000e18), lender._address, max);

    // Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);

    // Borrow
    await router.connect(borrower).borrow(borrowable.address, BigInt(1e18), borrower._address, max, '0x');

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
