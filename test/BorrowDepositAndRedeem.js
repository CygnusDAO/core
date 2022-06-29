// Hardhat
const chai = require('chai');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;
const hre = require('hardhat');

// Node
const fs = require('fs');
const path = require('path');

// Custom errors
const { CygnusTerminalErrors } = require('./errors/CygnusTerminalErrors.js');
const { CygnusCollateralErrors } = require('./errors/CygnusCollateralErrors.js');

chai.use(solidity);

/*
 *  Runs all tests on forked mainnet. All tests follow the same steps:
 *  1) Deploy the oracle to calculate LP Tokens and initialize pair with Chainlink aggregators
 *  2) Deploy Collateral Deployer contract -> Factory calls this to create the collateral arm
 *  3) Deploy Borrow Deployer contract -> Factory calls this to create the borrow arm
 *  4) Deploy Factory with addresses of step 1/2/3
 *  5) Deploy Router contract with addresses of step 2/3/4
 *  6) Deploy lending pool from factory
 *
 */
context('CygnusBorrow - Deposit DAI and Redeem CygDAI', function () {
    /* ──────────────────────────────────────────── Constants ─────────────────────────────────────────────  */

    const max = ethers.constants.MaxUint256;

    const addressZero = ethers.constants.AddressZero;

    // DAI
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // WAVAX
    const nativeToken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    /* ───────────────────────────────────────── Cygnus Contracts ─────────────────────────────────────────  */

    // Cygnus Contracts
    let collateral, borrowable, nebula, factory, router;

    /* ────────────────────────────────────────────── Users ───────────────────────────────────────────────  */

    // Main accounts that interact with Cygnus
    let borrower, lender;

    // Users to account for the min liquidity requirement
    let borrowerFirstDepositor, lenderFirstDepositor;

    // Initial balances of borrower and lender before they interact with Cygnus, check that they get full amount
    let borrowerInitialLPBalance, lenderInitialDaiBalance;

    /* ──────────────────────────────────────────── Addresses ─────────────────────────────────────────────  */

    /**
     * Admin is the factory/Cygnus admin
     * reservesManager is the address where protocol reserves get minted to
     */
    let owner, safeAddress1;

    // Lending pool object
    let shuttle;

    /* ─────────────────────────────────────── External Contracts ─────────────────────────────────────────  */

    /**
     * Create a lending pool with joe/Avax LP Token for example
     * Before initializing lending pool we have to initialize oracle to return the price of 1 LP Token of joe/avax
     * Create a dai ethers contract for approvals
     */
    let dai, joeAvaxLP;

    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // Abis
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/dai.json')).toString();

    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // Chainlink V3 Aggregators
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    const joeAggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';

    const avaxAggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    before(async () => {
        // Admin and ReservesManager
        const [owner, safeAddress1] = await ethers.getSigners();

        // ════════════ 1. ORACLE ════════════════════════════════════════════════════════════════

        const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

        // Deploy with Chainlink's dai Aggregator
        nebula = await Nebula.deploy(daiAggregator);

        console.log('Nebula Oracle:', nebula.address);

        // Initialize oracle, else the deployment for this lending pool fails
        await nebula.initializeNebula(joeAvaxLPAddress, joeAggregator, avaxAggregator);

        // ════════════ 2. COLLATERAL DEPLOYER ═══════════════════════════════════════════════════

        const Deneb = await ethers.getContractFactory('CygnusDeneb');

        const deneb = await Deneb.deploy();

        console.log('CollateralDeployer:', deneb.address);

        // ════════════ 3. BORROW DEPLOYER ═══════════════════════════════════════════════════════

        const Albireo = await ethers.getContractFactory('CygnusAlbireo');

        const albireo = await Albireo.deploy();

        console.log('BorrowDeployer', albireo.address);

        // ════════════ 4. FACTORY ═══════════════════════════════════════════════════════════════

        // Factory
        const Factory = await ethers.getContractFactory('CygnusFactory');

        const reservesManager = safeAddress1;

        factory = await Factory.deploy(
            owner.address,
            reservesManager.address,
            daiAddress,
            nativeToken,
            deneb.address,
            albireo.address,
            nebula.address,
        );

        console.log('Cygnus Factory:', factory.address);

        // ════════════ 5. ROUTER ════════════════════════════════════════════════════════════════

        // Router
        const Router = await ethers.getContractFactory('CygnusAltair');

        router = await Router.deploy(
            factory.address,
            deneb.address,
            albireo.address,
            // WAVAX
            '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
        );

        console.log('Router:', router.address);

        // ════════════ 6. DEPLOY SHUTTLE ════════════════════════════════════════════════════════

        // Custom pool rates for the JoeAvax lending pool
        const shuttleBaseRate = BigInt(0.08e18);

        const shuttleKinkRate = BigInt(0.75e18);

        const shuttleMultiplier = BigInt(0.15e18);

        // Shuttle with LP Token 0x454e67025631c065d3cfad6d71e6892f74487a15
        await factory.deployShuttle(joeAvaxLPAddress, shuttleBaseRate, shuttleMultiplier, shuttleKinkRate);

        shuttle = await factory.getShuttles(joeAvaxLPAddress);

        // ═══════════════════ ACCOUNTS ════════════════════════════════════════════════════════════

        /**
         *  Impersonate random accounts for borrowing/lending interactions
         */

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

        // ═════════════════════ LP TOKEN AND DAI ═════════════════════════════════════════════

        // Connect with borrower
        joeAvaxLP = new ethers.Contract(joeAvaxLPAddress, lpTokenAbi, borrower);

        // Connect with lender
        dai = new ethers.Contract(daiAddress, daiAbi, lender);

        // Balance of Borrower's LP before interactions with Cygnus
        borrowerInitialLPBalance = await joeAvaxLP.balanceOf(borrower._address);

        // Balance of Lender's dai before interactions with Cygnus
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);

        // ═════════════════════ CONTRACTS ════════════════════════════════════════════════════

        borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, owner);

        collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, owner);

        // Initialize VOID for compounding masterChef rewards ( OPTIONAL )
        // TRADERJOE ROUTER / MiniChefV3 JOE / JOE TOKEN / pool id / swapfee
        await collateral
            .connect(owner)
            .initializeVoid(
                '0x60ae616a2155ee3d9a68541ba4544862310933d4',
                '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F',
                '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd',
                6,
                997,
            );
    });

    describe('Deployment of pools from factory', function () {
        /**
         * Deployment sanity checks
         * - Check for collateral pool, collateral exchange rate, borrow pool, borrow exchange rate
         * - Approve Cygnus router in DAI contract and deposit DAI in Cygnus borrow pool
         */
        // Collateral
        it('Deploys collateral pool', async () => {
            expect(await collateral.name()).to.eq('Cygnus: Collateral');
        });

        it('Collateral exchange rate is INITIAL_EXCHANGE_RATE (1e18)', async () => {
            let exchangeRateC = await collateral.callStatic.exchangeRate();

            expect(await exchangeRateC).to.eq(BigInt(1e18));
        });

        // Borrowable
        it('Deploys borrowable pool', async () => {
            expect(await borrowable.name()).to.eq('Cygnus: Borrow');
        });

        it('Borrowable exchange rate is INITIAL_EXCHANGE_RATE (1e18)', async () => {
            expect(await borrowable.exchangeRateStored()).to.eq(BigInt(1e18));
        });

        // Deposit DAI with first lender to remove minimum liquidity annoyance
        it('First lender depositor, to account for the MINIMUM_LIQUIDITY factor', async () => {
            await dai.connect(lenderFirstDepositor).approve(router.address, max);

            await expect(
                router
                    .connect(lenderFirstDepositor)
                    .mint(borrowable.address, BigInt(500e18), lenderFirstDepositor._address, max),
            ).to.emit(borrowable, 'Mint');
        });
    });

    // MINTS
    describe('Lender deposits dai for CygDAI', function () {
        // Fail before approval
        it('Deposits dai in borrowable and mints CygDAI without approving router in Dai: FAIL { DAI_ERROR }', async () => {
            router = await router.connect(lender);

            borrowable = await borrowable.connect(lender);

            // DAI error
            await expect(router.mint(borrowable.address, BigInt(1000e18), lender._address, max)).to.be.reverted;
        });

        // Approve router
        it('Approves router in dai contract', async () => {
            await dai.approve(router.address, max);

            expect(await dai.allowance(lender._address, router.address)).to.eq(max);
        });

        // Mint and transfer event
        it('Deposits dai in borrowable and mints CygDAI and emits { Mint }', async () => {
            await expect(router.mint(borrowable.address, BigInt(1000e18), lender._address, max))
                .to.emit(borrowable, 'Mint')
                .withArgs(router.address, lender._address, BigInt(1000e18), BigInt(1000e18));
        });

        // Check that user has CygDAI and the pool holds DAI
        it('Lender has CygDAI', async () => {
            // CygDAI amount
            expect(await borrowable.balanceOf(lender._address)).to.eq(BigInt(1000e18));

            // Has less DAI
            expect(await dai.balanceOf(lender._address)).to.eq(BigInt(lenderInitialDaiBalance) - BigInt(1000e18));
        });
    });

    // REDEEMS
    describe('Lender redeems CygDAI for dai', function () {
        it('Redeems CygDAI for deposited amount without approving router in borrowable: FAIL { Erc20__InsufficientAllowance }', async () => {
            borrowable = await borrowable.connect(lender);

            router = await router.connect(lender);

            await expect(router.redeem(borrowable.address, BigInt(1000e18), lender._address, max, '0x')).to.be.reverted;
        });

        it('Approves router in Borrow contract and emits { Approval }', async () => {
            // Approve router in borrowable
            await expect(borrowable.approve(router.address, max))
                .to.emit(borrowable, 'Approval')
                .withArgs(lender._address, router.address, max);

            expect(await borrowable.allowance(lender._address, router.address)).to.eq(max);
        });

        it('Redeems CygDAI for deposited amount and emits { Redeem }', async () => {
            // Redeem with no permit data
            await expect(router.redeem(borrowable.address, BigInt(1000e18), lender._address, max, '0x'))
                .to.emit(borrowable, 'Redeem')
                .withArgs(router.address, lender._address, BigInt(1000e18), BigInt(1000e18));
        });

        it('dai Balance of lender is the same as before interacting wtih Cygnus if no one borrows', async () => {
            // Check that CygDAI balance of lender is 0
            expect(await borrowable.balanceOf(lender._address)).to.be.eq(0);

            // Check that lender has the same dai balance they had before interacting with Cygnus when no borrows
            expect(await dai.balanceOf(lender._address)).to.be.eq(lenderInitialDaiBalance);
        });
    });

    // Shouldn't accrue reserves as no borrows yet
    describe('Check side effects if no borrows', function () {
        it('Total reserves are 0 before any borrows', async () => {
            expect(await borrowable.totalReserves()).to.eq(0);
        });

        it('BorrowRate is 0', async () => {
            expect(await borrowable.borrowRate()).to.eq(0);
        });
    });
});
