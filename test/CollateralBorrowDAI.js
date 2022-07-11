// Hardhat
const chai = require('chai');
const hre = require('hardhat');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;

// Node
const fs = require('fs');
const path = require('path');
const { time } = require('@openzeppelin/test-helpers');

// Custom errors
const { CygnusTerminalErrors } = require('./errors/CygnusTerminalErrors.js');
const { CygnusCollateralErrors } = require('./errors/CygnusCollateralErrors.js');
const { CygnusBorrowErrors } = require('./errors/CygnusBorrowErrors.js');

chai.use(solidity);

/*
 *
 *  Tests for users who take out DAI loans. Runs all tests on forked C-Chain and uses the router to perform
 *  all the normal interactions.
 *
 *  Impersonates a random DAI whale to do the lending and a random LP whale from the LP token to do the borrowing.
 *
 *  To replicate tests update constants and external contracts.
 *
 *  Checks for:
 *    . Deployment of Collateral/Borrow shuttle from factory
 *    . Borrower LP Token deposits
 *    . Lender DAI Token deposits
 *    . Borrower maxes out DAI loan against collateral
 *    . Admin increases protocol settings (max debt ratio)
 *    . Borrow repays borrows
 *    . Reinvesting rewards
 */
describe('CYGNUS COLLATERAL: DEPOSIT LP TOKEN & BORROW DAI/REPAY DAI', function () {
    /* ──────────────────────────────────────────── Constants ─────────────────────────────────────────────  */

    const max = ethers.constants.MaxUint256;

    const addressZero = ethers.constants.AddressZero;

    // DAI
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // WAVAX
    const nativeToken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    /* ─────────────────────────────────────── External Contracts ─────────────────────────────────────────  */

    // dai and JoeAvax LP Token contracts
    let dai, joeAvaxLP;

    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // Abis
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/dai.json')).toString();

    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // Chainlink V3 Aggregators
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    const joeAggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';

    const avaxAggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    /* ───────────────────────────────────────── Cygnus Contracts ─────────────────────────────────────────  */

    // Cygnus Contracts
    let collateral, borrowable, nebula, factory, router, mockB, mockC;

    /* ────────────────────────────────────────────── Users ───────────────────────────────────────────────  */

    // Users to account for the min liquidity requirement
    let borrowerFirstDepositor, lenderFirstDepositor;

    // Main accounts that interact with Cygnus
    let borrower, lender;

    // Initial balances of borrower and lender before they interact with Cygnus, check that they get full amount
    let borrowerInitialLPBalance, borrowerInitialDaiBalance, lenderInitialDaiBalance;

    /* ──────────────────────────────────────────── Addresses ─────────────────────────────────────────────  */

    // Admin, reservesManager, safeAddress2 in case we need
    let owner, safeAddress1, safeAddress2;

    // Lending pool
    let shuttle;

    before(async () => {
        // Admin and ReservesManager
        [owner, safeAddress1, safeAddress2] = await ethers.getSigners();

        // ═══════════════════ 1. ORACLE ═════════════════════════════════════════════════════════

        const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

        // Deploy with Chainlink's dai Aggregator
        nebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

        console.log('Nebula Oracle:', nebula.address);

        // Initialize oracle, else the deployment for this lending pool fails
        await nebula.initializeNebula(joeAvaxLPAddress, joeAggregator, avaxAggregator);

        // ═══════════════════ 2. COLLATERAL DEPLOYER ═════════════════════════════════════════════

        const Deneb = await ethers.getContractFactory('CygnusDeneb');

        const deneb = await Deneb.deploy();

        console.log('CollateralDeployer:', deneb.address);

        // ═══════════════════ 3. BORROW DEPLOYER ═════════════════════════════════════════════════

        const Albireo = await ethers.getContractFactory('CygnusAlbireo');

        const albireo = await Albireo.deploy();

        console.log('BorrowDeployer', albireo.address);

        // ═══════════════════ 4. FACTORY ═════════════════════════════════════════════════════════

        // Factory
        const Factory = await ethers.getContractFactory('CygnusFactory');

        factory = await Factory.deploy(
            owner.address,
            safeAddress1.address,
            daiAddress,
            nativeToken,
            deneb.address,
            albireo.address,
            nebula.address,
        );

        console.log('Cygnus Factory:', factory.address);

        // ═══════════════════ 5. ROUTER ══════════════════════════════════════════════════════════

        // Router
        const Router = await ethers.getContractFactory('CygnusAltair');

        router = await Router.deploy(factory.address);

        console.log('Router:', router.address);

        // ═══════════════════ 6. SHUTTLE ══════════════════════════════════════════════════════════

        // custom pool rates for the JoeAvax lending pool
        const shuttleBaseRate = BigInt(0.08e18);
        const shuttleKinkRate = BigInt(0.75e18);
        const shuttleMultiplier = BigInt(0.15e18);

        // Shuttle with LP Token 0x454e67025631c065d3cfad6d71e6892f74487a15
        await factory.deployShuttle(joeAvaxLPAddress, shuttleBaseRate, shuttleMultiplier, shuttleKinkRate);
        shuttle = await factory.getShuttles(joeAvaxLPAddress);
        console.log(shuttle);

        // ═══════════════════ ACCOUNTS ════════════════════════════════════════════════════════════

        // BORROWER AND LENDER 1

        // Borrower: Random LP Holder for JOE / AVAX
        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: ['0x0f1410a815105f4429a404d2101890aa11d97951'],
        });

        borrower = await ethers.provider.getSigner('0x0f1410a815105f4429a404d2101890aa11d97951');

        // Lender: Random DAI Whale
        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: ['0x277b09605debf23776e87aa4cebbf85d8a0da353'],
        });

        lender = await ethers.provider.getSigner('0x277b09605debf23776e87aa4cebbf85d8a0da353');

        // BORROWER AND LENDER 2

        // Borrower: Random LP Holder for JOE / AVAX
        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: ['0x14E895102acd7D639C76276094990dCfDD20102F'],
        });

        borrowerFirstDepositor = await ethers.provider.getSigner('0x14E895102acd7D639C76276094990dCfDD20102F');

        // Lender: dai Whale
        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: ['0x7851dc7cf893242dfb5fe283116d68cfb8a828fe'],
        });

        lenderFirstDepositor = await ethers.provider.getSigner('0x7851dc7cf893242dfb5fe283116d68cfb8a828fe');

        // ═══════════════════ LP TOKEN and DAI ═════════════════════════════════════════════════════

        // Connect with borrower
        joeAvaxLP = new ethers.Contract(joeAvaxLPAddress, lpTokenAbi, borrower);
        // Connect with lender
        dai = new ethers.Contract(daiAddress, daiAbi, lender);

        // Balance of Borrower's LP before interactions with Cygnus
        borrowerInitialLPBalance = await joeAvaxLP.balanceOf(borrower._address);

        // Balance of Borrower's DAI before interactions with Cygnus
        borrowerInitialDaiBalance = await dai.balanceOf(borrower._address);

        // Balance of Lender's dai before interactions with Cygnus
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);

        // ═══════════════════ MOCKS ════════════════════════════════════════════════════════════════

        collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, borrower);

        borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, lender);

        // ═══════════════════ INITIALIZE VOID ═════════════════════════════════════════════════════

        await collateral
            .connect(owner)
            .initializeVoid(
                '0x60ae616a2155ee3d9a68541ba4544862310933d4',
                '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F',
                '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd',
                6,
                997,
            );

        // Set liquidation incentive to 0 for now
        await collateral.connect(owner).setLiquidationIncentive(BigInt(1e18));
    });

    /*
     *
     *
     *  START TESTS
     *
     *
     */
    describe('Deployment of pools from factory', function () {
        /*
         *
         *  Deploys from factory and checks initial state + deposit first amounts to run easier testing
         *  on `Borrower` account
         *
         *
         */
        it('Checks collateral contract is deployed', async () => {
            expect(await collateral.name()).to.eq('Cygnus: Collateral');
        });

        it('Checks borrow contract is deployed', async () => {
            expect(await borrowable.name()).to.eq('Cygnus: Borrow');
        });

        // To remove the MINIMUM LIQUIDITY factor for the rest of lenders
        it('The first lender deposits the first dai in borrow contract', async () => {
            // Approve first
            await dai.connect(lenderFirstDepositor).approve(router.address, max);

            // Deposit
            await router
                .connect(lenderFirstDepositor)
                .mint(borrowable.address, BigInt(200000e18), lenderFirstDepositor._address, max);
        });

        it('Check that totalBalance of borrowable is equal to dai.balanceOf(borrowable)', async () => {
            const daiBalanceBorrowable = await dai.balanceOf(borrowable.address);

            expect(await borrowable.totalBalance()).to.eq(daiBalanceBorrowable);
        });

        // To remove the MINIMUM LIQUIDITY factor for the rest of borrowers
        it('The first borrower deposits the first LP Token in collateral contract', async () => {
            // Approve first
            await joeAvaxLP.connect(borrowerFirstDepositor).approve(router.address, max);

            // Deposit
            await router
                .connect(borrowerFirstDepositor)
                .mint(collateral.address, BigInt(1e18), borrowerFirstDepositor._address, max);
        });

        it('Check that totalBalance of collateral is equal to LPToken.balanceOf(collateral)', async () => {
            const lpBalanceCollateral = await joeAvaxLP.balanceOf(collateral.address);

            expect(await collateral.totalBalance()).to.eq(BigInt(1e18));
        });
    });

    describe('Borrower deposits LP Token for CygLP', async () => {
        /*
         *
         *  `Borrower` deposits their LP Token and mints CygLP
         *
         *
         */
        const lpTokenAmount = BigInt(25e18);

        it('Deposits LP Token in collateral before approving router in LP: FAIL', async () => {
            await expect(router.connect(borrower).mint(collateral.address, lpTokenAmount, borrower._address, max)).to.be
                .reverted;
        });

        it('Approves router in LP contract', async () => {
            // Approve first
            await joeAvaxLP.connect(borrower).approve(router.address, max);

            // Check
            expect(await joeAvaxLP.allowance(borrower._address, router.address)).to.eq(max);
        });

        it('Deposits LP Token in collateral, mints CygLP and emits { Mint }', async () => {
            // Mint CygLP
            await expect(router.connect(borrower).mint(collateral.address, lpTokenAmount, borrower._address, max))
                .to.emit(collateral, 'Mint')
                .withArgs(router.address, borrower._address, lpTokenAmount, lpTokenAmount);
        });

        it('Borrower has CygLP in their wallet', async () => {
            // Check DAI balance of borrower
            expect(await collateral.balanceOf(borrower._address)).to.eq(lpTokenAmount);
        });
    });

    describe('Borrower takes out a DAI loan', async () => {
        /**
         *
         *  Borrower interactions with router to borrow
         *
         *
         */
        // Borrow without borrowApprove

        it('Borrows without `borrowApprove` call: FAIL { CygnusBorrowApprove__BorrowNotAllowed }', async () => {
            await expect(
                router.connect(borrower).borrow(borrowable.address, BigInt(10e18), borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        // Approves router and emits event
        it('Borrower allows router with `borrowApprove` and emits { Approval }', async () => {
            await expect(borrowable.connect(borrower).borrowApprove(router.address, max))
                .to.emit(borrowable, 'BorrowApproval')
                .withArgs(borrower._address, router.address, max);
        });

        // Check user's liquidity
        it('Borrower takes out more than his collateral available at 80% debt ratio: FAIL { Insufficient_Liquidity  }', async () => {
            // This users collateral in DAI
            const collateralInDai = await collateral.getAccountLiquidity(borrower._address);

            // Maximum the borrower can take out
            const maxLiquiditySlightlyMore = BigInt(collateralInDai.liquidity) + BigInt(0.01e18);

            // Borrow max liquidity + slighlty more, revert
            await expect(
                router
                    .connect(borrower)
                    .borrow(borrowable.address, maxLiquiditySlightlyMore, borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        // Check user's debt ratio is 0 (no borrows)
        it('Checks users debt ratio is 0', async () => {
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(userDebtRatio).to.be.eq(0);
        });

        // Get user's max liquidity and borrow max limit
        it('Borrower takes out max allowed at 80% debt ratio and emits { Borrow }', async () => {
            // This users collateral in DAI
            const collateralInDai = await collateral.getAccountLiquidity(borrower._address);

            const maxLiquidity = BigInt(collateralInDai.liquidity) - BigInt(0.01e18);

            const lpTokenPrice = await collateral.getLPTokenPrice();

            console.log('LP Token Price: %s', lpTokenPrice);
            console.log('Max Liquidity of borrower: %s', maxLiquidity);

            // Borrow
            await expect(
                router.connect(borrower).borrow(borrowable.address, maxLiquidity, borrower._address, max, '0x'),
            ).to.emit(borrowable, 'Borrow');
        });

        // Check DAI balance of borrower
        it('User has DAI in wallet', async () => {
            // Initial dai balance was 0
            expect(await dai.balanceOf(borrower._address)).to.be.gt(borrowerInitialDaiBalance);
        });

        // Debt ratio of borrower should be max 80%
        it('Borrower debt ratio is < 80% due to compounding of rewards', async () => {
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(userDebtRatio).to.be.lte(BigInt(0.8e18));
        });

        // Check that borrower cannot borrow more
        it('Borrower cant borrow more', async () => {
            // Borrow Min
            await expect(
                router.connect(borrower).borrow(borrowable.address, BigInt(1e18), borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        it('Borrower has 0 liquidity', async () => {
            // This users collateral in DAI
            const collateralInDai = await collateral.getAccountLiquidity(borrower._address);

            const maxLiquidity = collateralInDai.liquidity;

            // Check that the borrower has no liquidity
            expect(maxLiquidity).to.be.within(BigInt(0), BigInt(0.1e18));
        });
    });

    describe('Admin increases debtRatio requirement and allows more borrows', function () {
        /**
         *
         *  Checks interactions after increasing parameters
         *
         *
         */
        // Check again to make sure
        it('Borrower cant borrow any more', async () => {
            // Borrow Min
            await expect(
                router.connect(borrower).borrow(borrowable.address, BigInt(1e18), borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        // Increase debt ratio
        it('Increases debtRatio to 85%', async () => {
            const oldDebtRatio = await collateral.debtRatio();

            const newDebtRatio = BigInt(0.85e18);

            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio))
                .to.emit(collateral, 'NewDebtRatio')
                .withArgs(oldDebtRatio, newDebtRatio);
        });

        // Debt ratio of borrower should be max 80%
        it('Borrower debt ratio is still 80%', async () => {
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            // Check user's debt ratio
            expect(userDebtRatio).to.be.lte(BigInt(0.8e18));

            console.log(userDebtRatio);

            // Check that debtRatio is updated
            expect(await collateral.debtRatio()).to.be.eq(BigInt(0.85e18));
        });

        // Check another event
        it('Borrower takes out another loan and emits { Borrow, AccrueInterest } }', async () => {
            // This users collateral in DAI
            const collateralInDaiV2 = await collateral.getAccountLiquidity(borrower._address);

            const maxLiquidityV2 = BigInt(collateralInDaiV2.liquidity) - BigInt(0.001e18);

            // Borrow
            await expect(
                router.connect(borrower).borrow(borrowable.address, maxLiquidityV2, borrower._address, max, '0x'),
            ).to.emit(borrowable, 'Borrow');
        });

        // Debt ratio of borrower should be ~85%
        it('Borrower debt ratio is 85%', async () => {
            // Static call the debt ratio
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            // Check user's debt ratio
            expect(userDebtRatio).to.be.within(BigInt(0.845e18), BigInt(0.855e18));

            // Check that debtRatio is updated
            expect(await collateral.debtRatio()).to.be.eq(BigInt(0.85e18));
        });

        it('Borrower has 0 liquidity left', async () => {
            // This users collateral in DAI
            const collateralInDai = await collateral.getAccountLiquidity(borrower._address);

            const maxLiquidity = collateralInDai.liquidity;

            // Check that the borrower has no liquidity
            expect(maxLiquidity).to.be.within(BigInt(0), BigInt(0.01e18));
        });
    });

    describe('Checking reserve balances, total borrows etc.', function () {
        it('Check reserves internal', async () => {
            // Have to poke exchangeRate as it is only triggered by another MINT or REDEEM and user
            // has already minted before there were any reserves
            await expect(borrowable.exchangeRate()).to.emit(borrowable, 'Transfer');

            // Check reserves
            const totalReserves = await borrowable.totalReserves();
            const reservesBalance = await borrowable.balanceOf(safeAddress1.address);
            //console.log('Total Reserves: %s', totalReserves);
            //console.log('Reserves Balance 1: %s', reservesBalance);

            // Borrowable's total DAI balance
            const totalBalance = await borrowable.totalBalance();
            //console.log('Total Balance: %s', totalBalance);

            // Exchange Rate
            const exchangeRate = await borrowable.exchangeRate();
            //console.log('ExchangeRate %s', exchangeRate);

            // Total Borrows
            const totalBorrows = await borrowable.totalBorrows();
            //console.log('Total Borrows: %s', totalBorrows);
        });
    });

    describe('Borrower repays loans', function () {
        /**
         *
         *  Checks interactions when repaying loans
         *
         *
         */
        it('Borrower has 85% debt ratio', async () => {
            // Static call the debt ratio
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            // Check user's debt ratio
            expect(userDebtRatio).to.be.within(BigInt(0.845e18), BigInt(0.855e18));
        });

        it('Borrower repays part of his loan back without approving router in DAI: FAIL { InsufficientAllowance }', async () => {
            const loanRepayAmount = BigInt(10e18);

            // Static call the debt ratio
            await expect(router.connect(borrower).repay(borrowable.address, loanRepayAmount, borrower._address, max)).to
                .be.reverted;
        });

        it('Borrower approves router in DAI contract and emits { Approval }', async () => {
            // Approve dDAI
            await expect(dai.connect(borrower).approve(router.address, max)).to.emit(dai, 'Approval');
        });

        it('Borrower repays 50% of his loan back in DAI and emits { Borrow }', async () => {
            const borrowersBalance = await borrowable.getBorrowBalance(borrower._address);

            const loanRepayAmount = (BigInt(borrowersBalance) * BigInt(0.5e18)) / BigInt(1e18);

            // Static call the debt ratio
            await expect(
                router.connect(borrower).repay(borrowable.address, loanRepayAmount, borrower._address, max),
            ).to.emit(borrowable, 'Borrow');
        });

        it('Checks that borrowers Debt Ratio is now 50% less than before (should be 42.5%)', async () => {
            const borrowersDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(borrowersDebtRatio).to.be.within(BigInt(0.4245e18), BigInt(0.4255e18));
        });
    });

    describe('Borrower repays full amount and redeems token', function () {
        it('Borrower repays full loan amount', async () => {
            const borrowersBalance = await borrowable.getBorrowBalance(borrower._address);

            // Whale sends user dai
            await dai.connect(lender).transfer(borrower._address, BigInt(borrowersBalance) + BigInt(100e18));

            const borrowersBalanceUpdated = BigInt(borrowersBalance) + BigInt(50e18);

            await expect(
                router.connect(borrower).repay(borrowable.address, borrowersBalanceUpdated, borrower._address, max),
            ).to.emit(borrowable, 'Borrow');
        });

        it('Checks that borrowers debt ratio is 0%', async () => {
            // Static call the debt ratio
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(userDebtRatio).to.eq(0);
        });
    });

    describe('Debt repayment and auto-compounding rewards', function () {
        let totalBalance;
        let userDebtRatio;

        it('User takes out another DAI loan (50% of their liquidity)', async () => {
            // This users collateral in DAI
            const collateralInDai = await collateral.getAccountLiquidity(borrower._address);

            const maxLiquidity = BigInt(collateralInDai.liquidity) / BigInt(2);

            //console.log(maxLiquidity);

            // Borrow
            await expect(
                router.connect(borrower).borrow(borrowable.address, maxLiquidity, borrower._address, max, '0x'),
            ).to.emit(borrowable, 'Borrow');
        });

        it('Get totalBalance and users debtRatio', async () => {
            totalBalance = await collateral.totalBalance();
            console.log('Total Balance: %s', totalBalance);

            // Static call the debt ratio
            userDebtRatio = await collateral.getDebtRatio(borrower._address);
            console.log('Users debt ratio: %s', userDebtRatio);
        });

        it('Reinvests rewards and emits { ReinvestRewards }', async () => {
            let rewardsTokenC = new ethers.Contract('0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd', daiAbi, safeAddress2);

            let reward = await rewardsTokenC.balanceOf(safeAddress2.address);

            let totalBalance = await collateral.totalBalance();
            let usersDebtRatio = await collateral.getDebtRatio(borrower._address);

            console.log('TOTAL BALANCE OLD: %s', totalBalance);
            console.log('DEBT RATIO OLD: %s', usersDebtRatio);

            console.log('Reward token balance of reinvestor: %s', reward);

            console.log('365 days pass..');

            await time.increase(60 * 60 * 24 * 365);

            console.log('safe address reinvests rewards');

            await expect(collateral.connect(safeAddress2).reinvestRewards()).to.emit(collateral, 'RechargeVoid');

            let reward2 = await rewardsTokenC.balanceOf(safeAddress2.address);

            console.log('New reward token balance of reinvestor: %s', reward2);
        });

        it('Checks that total balance is increased and users debt ratio is lower', async () => {
            let newBalance = await collateral.totalBalance();
            let newDebtRatio = await collateral.getDebtRatio(borrower._address);

            console.log('TOTAL BALANCE NEW: %s', newBalance);
            console.log('DEBT RATIO NEW: %s', newDebtRatio);
        });
    });
});
