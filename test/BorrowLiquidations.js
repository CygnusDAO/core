// Hardhat
const chai = require('chai');
const hre = require('hardhat');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;

// Node
const fs = require('fs');
const path = require('path');

// Custom errors
const { CygnusTerminalErrors } = require('./errors/CygnusTerminalErrors.js');
const { CygnusCollateralErrors } = require('./errors/CygnusCollateralErrors.js');
const { CygnusBorrowErrors } = require('./errors/CygnusBorrowErrors.js');

chai.use(solidity);

/*
 *  Simple tests for user taking out a dai loan. 
 *  Runs all tests on forked mainnet and uses the router to simulate interactions with protocol under normal
 *  circmustances.
 *
 *  Impersonates a random DAI whale to deposit in lending contract and a random holder of the AVAX/JOE LP Token
 *  to deposit in the borrow contract.
 *
 *  The test deploys: oracle -> cdeployer, bdeployer -> router -> factory -> collateral, borrowable
 *
 *  Checks for:
 *    - Deployment of Collateral/Borrow shuttle from factory
 *    - Borrower deposits LP Token for `CygLP` in the collateral contract
 *    - Lender deposits DAI for CygDAI in the borrow contract
 *    - Borrower maxes out DAI loan against collateral
 *    - Admin increases protocol settings (max debt ratio)
 *    - Borrower maxes out DAI loan again
 *    - Borrower repays loan
 *    - Reinvests masterchef rewards on every borrow/repay
 *    - User debt ratio lowers as contract reinvests rewards into more LP Tokens
 *
 */
describe('Cygnus Borrower: CygnusCollateral.sol', function () {
    /* ──────────────────────────────────────────── Constants ─────────────────────────────────────────────  */

    const max = ethers.constants.MaxUint256;

    // Address zero
    const addressZero = ethers.constants.AddressZero;

    // WETH / WAVAX / FTM / MATIC
    const nativeToken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    // Addresses
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    /* ─────────────────────────────────────── External Contracts ─────────────────────────────────────────  */

    // dai and JoeAvax LP Token contracts
    let dai, joeAvaxLP;

    // Abis
    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/dai.json')).toString();

    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // Chainlink V3 Aggregators
    //  Dai
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // Joe
    const joeAggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';

    // Avax
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
        console.log('Cygnus Reserves:', await factory.vegaTokenManager());

        // ═══════════════════ 5. ROUTER ══════════════════════════════════════════════════════════

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

        // ═══════════════════ 6. SHUTTLE ══════════════════════════════════════════════════════════

        // custom pool rates for the JoeAvax lending pool
        const shuttleBaseRate = BigInt(0.08e18);

        const shuttleKinkRate = BigInt(0.75e18);

        const shuttleMultiplier = BigInt(0.15e18);

        // Shuttle with LP Token 0x454e67025631c065d3cfad6d71e6892f74487a15
        await factory.deployShuttle(joeAvaxLPAddress, shuttleBaseRate, shuttleMultiplier, shuttleKinkRate);

        shuttle = await factory.getShuttles(joeAvaxLPAddress);

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
                .mint(borrowable.address, BigInt(10000e18), lenderFirstDepositor._address, max);
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
        const lpTokenAmount = BigInt(10e18);

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

    describe('Borrower takes out a DAI loan', function () {
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

            const maxLiquidity = collateralInDai.liquidity;

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
        it('Borrower debt ratio is 80% (a bit less due to reinvest of rewards, 79.99%)', async () => {
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(userDebtRatio).to.be.lt(BigInt(0.8e18));
        });

        // Check that borrower cannot borrow more
        it('Borrower cant borrow more', async () => {
            // Borrow Min
            await expect(
                router.connect(borrower).borrow(borrowable.address, BigInt(0.01e18), borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        it('Borrower has 0 liquidity (same as above, check with static call)', async () => {
            // This users collateral in DAI
            const collateralInDai = await collateral.getAccountLiquidity(borrower._address);

            const maxLiquidity = collateralInDai.liquidity;

            expect(maxLiquidity).to.be.within(BigInt(0), BigInt(0.0001e18));
        });
    });

    describe('Borrowers position is in liquidatable state', function () {
        it('User lowers debt ratio: FAIL { CygnusTerminal__MsgSenderNotAdmin }', async () => {
            const newDebtRatio = BigInt(0.75e18);

            const oldDebtRatio = await collateral.debtRatio();

            await expect(collateral.connect(safeAddress1).setDebtRatio(newDebtRatio)).to.be.reverted;

            expect(await collateral.debtRatio()).to.be.eq(oldDebtRatio);
        });

        it('Admin lowers debt ratio to 75% and emits { NewDebtRatio }', async () => {
            const oldDebtRatio = await collateral.debtRatio();

            const newDebtRatio = BigInt(0.75e18);

            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio))
                .to.emit(collateral, 'NewDebtRatio')
                .withArgs(oldDebtRatio, newDebtRatio);
        });

        it('Checks borrowers position is liquidatable', async () => {
            const debtRatio = await collateral.debtRatio();

            const borrowersDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(borrowersDebtRatio).to.be.gt(debtRatio);
        });
    });

    describe('Liquidating borrowers', function () {
        it('DAI holder liquidates borrower', async () => {
            // Set liquidation incentive
            await collateral.connect(owner).setLiquidationIncentive(BigInt(1.05e18));

            // Collateral Balance of borrower
            const balanceOfBorrowerC = await collateral.balanceOf(borrower._address);
            console.log('Collateral balance of borrower before liquidation: %s', balanceOfBorrowerC);
            // Collateral Balance of lender
            const balanceOfLenderC = await collateral.balanceOf(lender._address);
            console.log('Collateral balance of lender before liquidation: %s', balanceOfLenderC);

            // Get LP Token price
            const lpTokenPrice = await collateral.getLPTokenPrice();
            // Liquidates 1 LP Token's worth in DAI
            const liquidateAmount = lpTokenPrice;

            await dai.connect(lender).approve(router.address, max);

            await router
                .connect(lender)
                .liquidate(borrowable.address, liquidateAmount, borrower._address, lender._address, max);

            const balanceOfBorrowerCNew = await collateral.balanceOf(borrower._address);
            console.log('New collateral balance of borrower: %s', balanceOfBorrowerCNew);
            const balanceOfLenderCNew = await collateral.balanceOf(lender._address);
            console.log('New collateral balance of lender: %s', await collateral.balanceOf(lender._address));
        });
    });
});
