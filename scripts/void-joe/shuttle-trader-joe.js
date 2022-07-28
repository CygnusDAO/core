const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');

const { time } = require('@openzeppelin/test-helpers');

// AVALANCHE SCRIPT FOR LENDING POOL

/*
 *  Deploys a lending pool on Avalanche. We use the LP Token Joe/Avax from Traderjoe as an example and
 *  the corresponding masterchef and pool Id: https://snowtrace.com/token/0x454E67025631C065d3cFAD6d71E6892f74487a15
 *
 *  The steps to deploy a lending pool is as follows:
 *
 *     1. Deploy oracle and initialize the LP Token pair we want to get the price of
 *     2. Deploy the Collateral `CygnusDeneb` - Contract that deploys collaterals
 *     3. Deploy the borrow orbiter `CygnusAlbireo` - Contract that deploys borrow contracts
 *     4. Deploy the factory with native chain token, address of dai, admin and reserves manager
 *     5. Initialize orbiters in the factory for each dex we want to deploy to
 *     6. Deploy the router for ease of use with contracts
 *     7. Deploy Shuttle from the factory with the address of the LP Token we want to create a lending pool with
 *     8. Initialize CygnusCollateralVoid
 */
async function deploy() {
    // Constants
    const max = ethers.constants.MaxUint256;

    // Signer and reservesManager
    const [owner, reservesManager, reinvestor] = await ethers.getSigners();

    // LP Token ABI
    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, '../abis/lptoken.json')).toString();

    // Dai ABI
    const daiAbi = fs.readFileSync(path.resolve(__dirname, '../abis/dai.json')).toString();

    // ═══════════════════ 0. SETUP ══════════════════════════════════════════════

    // DAI address in avalanche
    const dai = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // Native chain token (WAVAX)
    const native = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    // DAI Chainlink aggregator  in avalanche
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // CUSTOM //

    // JOE/AVAX LP Token
    const lpToken = '0x454E67025631C065d3cFAD6d71E6892f74487a15';
    // Chainlink Aggregators for token0 and token1 on Avalanche
    const token0Aggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';
    const token1Aggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    // VOID
    const joeRouter = '0x60ae616a2155ee3d9a68541ba4544862310933d4';
    const masterChef = '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F';
    const rewardToken = '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd';
    const pid = 6;

    // Borrower
    const borrowerAddress = '0x0f1410a815105f4429a404d2101890aa11d97951';
    const lenderAddress = '0x277b09605debf23776e87aa4cebbf85d8a0da353';

    // ═══════════════════ 1. ORACLE ════════════════════════════════════════════════════════════════════════

    // Oracle
    const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy with DAI denomination
    const nebula = await Nebula.deploy(daiAggregator);

    console.log('Nebula Oracle:', nebula.address);

    // Initialize oracle, else the deployment of this pool fails
    await nebula.initializeNebula(lpToken, token0Aggregator, token1Aggregator);

    // ═══════════════════ 2. COLLATERAL DEPLOYER ═══════════════════════════════════════════════════════════

    const Deneb = await ethers.getContractFactory('DenebOrbiter');

    const deneb = await Deneb.deploy();

    console.log('CollateralDeployer:', deneb.address);

    // ═══════════════════ 3. BORROWABLE DEPLOYER ═══════════════════════════════════════════════════════════

    const Albireo = await ethers.getContractFactory('AlbireoOrbiter');

    const albireo = await Albireo.deploy();

    console.log('BorrowDeployer', albireo.address);

    // ═══════════════════ 4. FACTORY ═══════════════════════════════════════════════════════════════════════

    // Factory
    const Factory = await ethers.getContractFactory('CygnusFactory');

    const factory = await Factory.deploy(owner.address, reservesManager.address, dai, native, nebula.address);

    console.log('Cygnus Factory:', factory.address);

    // ═══════════════════ 5. ROUTER ════════════════════════════════════════════════════════════════════════

    // Router
    const Router = await ethers.getContractFactory('CygnusAltairX');

    const router = await Router.deploy(factory.address);

    console.log('Router:', router.address);

    // ═══════════════════ Deployers ══════════════════════════════════════════════════════════════════════════

    await factory.setNewOrbiter('TraderJoe', deneb.address, albireo.address);

    // ═══════════════════ SHUTTLE ══════════════════════════════════════════════════════════════════════════

    // Pool customs
    const baseRate = BigInt(0.08e18);

    const kink = BigInt(2);

    const multi = BigInt(0.15e18);

    // Shuttle with LP Token
    await factory.deployShuttle(0, lpToken, baseRate, multi, kink);

    const shuttle = await factory.getShuttles(lpToken);

    console.log(shuttle);

    // ═══════════════════ IMPERSONATE ACCOUNTS ═════════════════════════════════════════════════════════════

    // BORROWER AND LENDER 1

    // Borrower: Random LP Holder for JOE/AVAX
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [borrowerAddress],
    });

    const borrower = await ethers.provider.getSigner(borrowerAddress);

    // Lender: DAI Whale
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [lenderAddress],
    });

    const lender = await ethers.provider.getSigner(lenderAddress);

    // ═════════════════════ CONTRACTS ══════════════════════════════════════════════════════════════════════

    // Connect with borrower
    const LPTOKEN = new ethers.Contract(lpToken, lpTokenAbi, borrower);

    // Connect with lender
    const DAI = new ethers.Contract(dai, daiAbi, lender);

    // Get deployed collateral contract
    const collateral = await ethers.getContractAt('CygnusCollateral', shuttle.collateral, borrower);

    // Get deployed borrow contract
    const borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusDai, lender);

    // ═════════════════════ INITIALIZE VOID ════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(joeRouter, masterChef, rewardToken, 6, 997);

    /********************************************************************************************************
   
    
     CYGNUS INTERACTIONS - Connect to the router and test mint functions for borrow and collateral contracts.
                         - Increase debt ratio to 100% and keep liquidation incentive to 5% to do a max leverage
                           
    
     
     ********************************************************************************************************/

    // Increase debt ratio to 100%, the maximum amount
    await collateral.connect(owner).setDebtRatio(BigInt(1e18));

    console.log(
        'LP Balance of borrower before interacting with Cygnus: %s',
        (await LPTOKEN.balanceOf(borrower._address)) / 1e18,
    );

    console.log(
        'DAI Balance of lender before interacting with Cygnus: %s',
        (await DAI.balanceOf(lender._address)) / 1e18,
    );

    console.log('---- Borrower deposits 1 LP token of joe/Avax into Cygnus ----');

    // Price of 1 LP Token of joe/avax in DAI
    const oneLPToken = await collateral.getLPTokenPrice();

    // Borrower: Deposits 100 LP Token = ~740 usd
    await LPTOKEN.connect(borrower).approve(router.address, max);
    await router.connect(borrower).mint(collateral.address, BigInt(100e18), borrower._address, max);

    // Lender: Deposits 1000 dai
    await DAI.connect(lender).approve(router.address, max);
    await router.connect(lender).mint(borrowable.address, BigInt(25000e18), lender._address, max);

    console.log('----------------------------------------------------------------------------------------------');

    console.log('PRICE OF 1 LP TOKEN OF JOE/AVAX: %s DAI', oneLPToken / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('----------------------------------------------------------------------------------------------');

    console.log('BEFORE LEVERAGE');

    console.log('----------------------------------------------------------------------------------------------');

    const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address);

    const cygDAIBalanceBeforeL = await borrowable.balanceOf(lender._address);

    const albireoBalanceBeforeL = await borrowable.totalBalance();

    const cygLPTotalBalanceBeforeL = await collateral.totalBalance();

    const daiBalanceBeforeL = await DAI.balanceOf(borrower._address);

    console.log('BORROWER: DAI Balance borrower before leverage: %s DAI', daiBalanceBeforeL / 1e18);

    console.log('LENDER: CygDAI balance of lender: %s', cygDAIBalanceBeforeL / 1e18);

    console.log('BORROWER: CygLP balance of borrower before leverage: %s CYG-LP', cygLPBalanceBeforeL / 1e18);

    console.log('PROTOCOL: totalBalance of borrowable before leverage: %s DAI', albireoBalanceBeforeL / 1e18);

    console.log('PROTOCOL: totalBalance of collateral before leverage: %s LP TOKENS', cygLPTotalBalanceBeforeL / 1e18);

    console.log('----------------------------------------------------------------------------------------------');

    console.log('AFTER LEVERAGE');

    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);

    // Borrower 9x leverage (borrows DAI equivalent to 800 LP Tokens)
    await router
        .connect(borrower)
        .leverage(collateral.address, BigInt(oneLPToken) * BigInt(800), borrower._address, max, '0x');

    const borrowBalanceAfter = await borrowable.getBorrowBalance(borrower._address);

    console.log('PROTOCOL: outstanding borrow balance of borrower: %s DAI', borrowBalanceAfter / 1e18);

    console.log('BORROWER: Debt ratio after leverage x9: %s', await collateral.getDebtRatio(borrower._address));

    const denebBalanceAfterL = await collateral.balanceOf(borrower._address);

    console.log('BORROWER: CYG-LP balance of borrower after leverage: %s CYG-LP', denebBalanceAfterL / 1e18);

    const albireoBalanceAfterL = await borrowable.totalBalance();

    console.log('PROTOCOL: totalBalance of borrowable after leverage: %s DAI', albireoBalanceAfterL / 1e18);

    const totalBalanceC = await collateral.totalBalance();

    console.log('PROTOCOL: totalBalance of collateral after leverage: %s LP TOKENS', totalBalanceC / 1e18);

    console.log('----------------------------------------------------------------------------------------------');

    console.log('REINVEST REWARDS');

    console.log('----------------------------------------------------------------------------------------------');

    // Create
    const REWARDTOKEN = new ethers.Contract(rewardToken, daiAbi, owner);

    const reinvestorBalance = await REWARDTOKEN.balanceOf(reinvestor.address);

    const balanceBeforeReinvest = await collateral.totalBalance();

    console.log('PROTOCOL: totalBalance of collateral before reinvesting: %s LP TOKENS', balanceBeforeReinvest / 1e18);

    console.log(
        'PROTOCOL: totalBalance of rewards token of the reinvestor before reinvesting: %s JOE',
        reinvestorBalance / 1e18,
    );

    // Increase 7 days
    await time.increase(60 * 60 * 24 * 7);

    console.log('7 Days pass...');

    await collateral.connect(reinvestor).reinvestRewards();

    const reinvestorBalanceAfter = await REWARDTOKEN.balanceOf(reinvestor.address);

    const balanceAfterReinvest = await collateral.totalBalance();

    console.log('PROTOCOL: totalBalance of collateral after reinvesting: %s LP TOKENS', balanceAfterReinvest / 1e18);

    console.log(
        'PROTOCOL: balance of rewards token of the reinvestor after reinvesting: %s JOE',
        reinvestorBalanceAfter / 1e18,
    );

    console.log('----------------------------------------------------------------------------------------------');

    console.log('AFTER DELEVERAGE');

    console.log('----------------------------------------------------------------------------------------------');

    // Deleverage everything
    await collateral.connect(borrower).approve(router.address, max);

    const maxBalance = await collateral.balanceOf(borrower._address);

    // Deleverage up to original deposited amount + estimate of swap fees (0.3% for each swap and we're doing 6 swaps max)
    await router.connect(borrower).deleverage(collateral.address, BigInt(maxBalance) - BigInt(91.5e18), max, '0x');

    const newBalance = await collateral.balanceOf(borrower._address);

    // Redeem
    await router.connect(borrower).redeem(collateral.address, newBalance, borrower._address, max, '0x');

    const finalDenebBalance = await collateral.balanceOf(borrower._address);

    const finalAlbireoBalance = await borrowable.totalBalance();

    const outstandingBalance = await borrowable.getBorrowBalance(borrower._address);

    console.log(
        'PROTOCOL: outstanding borrow balance of borrower after de-leverage: %s DAI',
        outstandingBalance / 1e18,
    );

    console.log('BORROWER: CYG-LP balance of borrower after de-leverage: %s CYG-LP', finalDenebBalance / 1e18);

    console.log('PROTOCOL: totalBalance of borrowable after de-leverage: %s DAI', finalAlbireoBalance / 1e18);

    const totalBalanceD = await collateral.totalBalance();

    console.log('PROTOCOL: totalBalance of collateral after de-leverage: %s LP TOKENS', totalBalanceD / 1e18);

    console.log('----------------------------------------------------------------------------------------------');

    console.log('REDEEM AND LEAVE CYGNUS FOREVER');

    console.log('----------------------------------------------------------------------------------------------');

    const balanceCygDaiLender = await borrowable.balanceOf(lender._address);

    await borrowable.connect(lender).approve(router.address, max);
    await router.connect(lender).redeem(borrowable.address, balanceCygDaiLender, lender._address, max, '0x');

    const finalLPBalance = await LPTOKEN.balanceOf(borrower._address);
    const finalDaiBalance = await DAI.balanceOf(lender._address);
    const daiBalanceAfter = await DAI.balanceOf(borrower._address);

    console.log('BORROWER: DAI Balance borrower after de-leverage: %s DAI', daiBalanceAfter / 1e18);
    console.log('LENDER: DAI Balance of lender after interacting wtih Cygnus: %s DAI', finalDaiBalance / 1e18);
    console.log('BORROWER: LP Balance of borrower after interacting with Cygnus: %s', finalLPBalance / 1e18);

    console.log(
        'PROTOCOL: totalBalance of collateral after full redeem: %s LP TOKENS',
        (await collateral.totalBalance()) / 1e19,
    );

    console.log('PROTOCOL: totalSupply of collateral after full redeem: %s CYG-LP', await collateral.totalSupply());

    // only cygDai left in the pool should be the DAO reserves
    console.log(
        'PROTOCOL: totalBalance of borrowable after full redeem: %s DAI',
        (await borrowable.totalBalance()) / 1e18,
    );
    console.log(
        'PROTOCOL: totalSupply of borrowable after full redeem: %s CygDAI',
        (await borrowable.totalSupply()) / 1e18,
    );

    console.log(
        'RESERVES: balanceOf reserves manager: %s CygDAI',
        (await borrowable.balanceOf(reservesManager.address)) / 1e18,
    );
}

deploy();
/*
module.exports = {
    deploy,
};
*/
