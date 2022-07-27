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

chai.use(solidity);

/*
 *
 * Run all tests with forked avalanche mainnet.
 *
 */
context('CYGNUS COLLATERAL: DEPOSIT LP TOKEN & REDEEM CYGLP', function () {
    /* ──────────────────────────────────────────── Constants ─────────────────────────────────────────────  */

    // Max digit in a uint256
    const max = ethers.constants.MaxUint256;

    // 0 address
    const addressZero = ethers.constants.AddressZero;

    // DAI
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // NATIVE
    const nativeToken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    // VOID
    let voidx;
    let voidRouter = '0x60ae616a2155ee3d9a68541ba4544862310933d4';
    let masterChef = '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F';
    let rewardToken = '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd';
    let pid = 6;

    /* ─────────────────────────────────────── External Contracts ─────────────────────────────────────────  */

    // dai and JoeAvax LP Token contracts
    let dai, joeAvaxLP;

    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/dai.json')).toString();

    // Abis
    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    // Chainlink V3 Aggregators
    // DAI
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // JOE
    const joeAggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';

    // AVAX
    const avaxAggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    /* ───────────────────────────────────────── Cygnus Contracts ─────────────────────────────────────────  */

    // Cygnus Contracts
    let collateral, borrowable, nebula, factory, router;

    /* ────────────────────────────────────────────── Users ───────────────────────────────────────────────  */

    // Users to account for the min liquidity requirement
    let borrowerFirstDepositor, lenderFirstDepositor;

    // Main accounts that interact with Cygnus
    let borrower, lender;

    // Initial balances of borrower and lender before they interact with Cygnus, check that they get full amount
    let borrowerInitialLPBalance, lenderInitialDaiBalance;

    /* ──────────────────────────────────────────── Addresses ─────────────────────────────────────────────  */

    // Admin, reservesManager, safeAddress2
    let owner, safeAddress1, safeAddress2;

    // Lending pool
    let shuttle;

    /* ────────────────────────────────────────── Lending Pool ────────────────────────────────────────────  */

    // Custom pool rates for the JoeAvax lending pool
    const baseRate = BigInt(0.08e18);

    const kink = BigInt(3);

    const multi = BigInt(0.15e18);

    before(async () => {
        // Admin and ReservesManager
        const [owner, safeAddress1] = await ethers.getSigners();

        // ═══════════════════ ORACLE ═════════════════════════════════════════════════════════

        const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');

        // Deploy with Chainlink's dai Aggregator
        nebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

        //console.log('Nebula Oracle:', nebula.address);

        // Initialize oracle, else the deployment for this lending pool fails
        await nebula.initializeNebula(joeAvaxLPAddress, joeAggregator, avaxAggregator);

        // ════════════ Collateral Deployer ═══════════════════════════════════════════════════

        const Deneb = await ethers.getContractFactory('CygnusDeneb');

        const deneb = await Deneb.deploy();

        //console.log('CollateralDeployer:', deneb.address);

        // ════════════ Borrowable Deployer ═══════════════════════════════════════════════════

        const Albireo = await ethers.getContractFactory('CygnusAlbireo');

        const albireo = await Albireo.deploy();

        //console.log('BorrowDeployer', albireo.address);

        // ══════════════════ Factory ═════════════════════════════════════════════════════════

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

        //console.log('Cygnus Factory:', factory.address);

        // ═══════════════════ Router ════════════════════════════════════════════════════════

        // Router
        const Router = await ethers.getContractFactory('CygnusAltairX');

        router = await Router.deploy(factory.address);

        //console.log('Router:', router.address);

        // ══════════════════ Shuttle ════════════════════════════════════════════════════════

        // Shuttle with LP Token 0x454e67025631c065d3cfad6d71e6892f74487a15
        await factory.deployShuttle(joeAvaxLPAddress, baseRate, multi, kink);

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

        // ═════════════════════ LP TOKEN AND dai ═══════════════════════════════════

        // Connect with borrower
        joeAvaxLP = new ethers.Contract(joeAvaxLPAddress, lpTokenAbi, borrower);

        // Connect with lender
        dai = new ethers.Contract(daiAddress, daiAbi, lender);

        // Balance of Borrower's LP before interactions with Cygnus
        borrowerInitialLPBalance = await joeAvaxLP.balanceOf(borrower._address);

        // Balance of Lender's dai before interactions with Cygnus
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);

        borrowable = await ethers.getContractAt('CygnusBorrow', shuttle.cygnusAlbireo, owner);

        collateral = await ethers.getContractAt('CygnusCollateral', shuttle.cygnusDeneb, owner);

        // ═════════════════════ INITIALIZE VOID ════════════════════════════════════════════════════════════

        // Void
        let Void = await ethers.getContractFactory('CygnusJoeVoid');

        // factory, lpToken + Router + MasterChef + RewardsToken + poolId + swapFee
        voidx = await Void.deploy(factory.address, joeAvaxLPAddress, voidRouter, masterChef, rewardToken, pid, 997);

        // Assign
        await collateral.connect(owner).setCygnusCollateralVoid(voidx.address);
    });

    describe('Deployment of pools from factory', function () {
        // Collateral
        it('Deploys collateral pool', async () => {
            expect(await collateral.name()).to.eq('Cygnus: Collateral');
        });

        // Borrowable
        it('Deploys borrowable pool', async () => {
            expect(await borrowable.name()).to.eq('Cygnus: Borrow');
        });

        // To remove the MINIMUM LIQUIDITY factor for the rest of lenders
        it('Deposits the first dai in borrow contract', async () => {
            await dai.connect(lenderFirstDepositor).approve(router.address, max);

            await router
                .connect(lenderFirstDepositor)
                .mint(borrowable.address, BigInt(10000e18), lenderFirstDepositor._address, max);
        });

        // To remove the MINIMUM LIQUIDITY factor for the rest of lenders
        it('Deposits the first LP Token in collateral contract', async () => {
            await joeAvaxLP.connect(borrowerFirstDepositor).approve(router.address, max);

            await router
                .connect(borrowerFirstDepositor)
                .mintCollateral(collateral.address, BigInt(1e18), borrowerFirstDepositor._address, max, '0x');
        });
    });

    describe('Borrower deposits LP Token for CygLP', function () {
        // Mints without approving router in LP contract
        it('Deposits LP Token in collateral contract before approving router in LP contract: FAIL { LP_CONTRACT }', async () => {
            await expect(
                router
                    .connect(borrower)
                    .mintCollateral(collateral.address, BigInt(10e18), borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        // Approve Router in LP
        it('Approves router in LP contract', async () => {
            await joeAvaxLP.connect(borrower).approve(router.address, max);

            expect(await joeAvaxLP.allowance(borrower._address, router.address)).to.eq(max);
        });

        // Mint tokens
        it('Deposits LP Token in collateral and mints CygLP and emit { Mint }', async () => {
            await expect(
                router
                    .connect(borrower)
                    .mintCollateral(collateral.address, BigInt(10e18), borrower._address, max, '0x'),
            )
                .to.emit(collateral, 'Mint')
                .withArgs(router.address, borrower._address, BigInt(10e18), BigInt(10e18));
        });

        // Has Cyg LP
        it('Borrower has CygLP in wallet', async () => {
            expect(await collateral.balanceOf(borrower._address)).to.eq(BigInt(10e18));
        });

        it('Borrower reinvests rewards in void', async () => {
            await expect(voidx.connect(borrower).chargeVoid()).to.emit(voidx, 'RechargeVoid');
        });
    });

    describe('Borrower redeems CygLP for LP Token without borrowing', function () {
        // Redeems without approving router in collateral contract
        it('Redeems CygLP for deposited amount without approving router in collateral: FAIL { Erc20__InsufficientAllowance }', async () => {
            await expect(
                router.connect(borrower).redeem(collateral.address, BigInt(10e18), borrower._address, max, '0x'),
            ).to.be.reverted;
        });

        // Approve router in collateral contract
        it('Approves router in collateral contract and emits { Approval }', async () => {
            await expect(collateral.connect(borrower).approve(router.address, max))
                .to.emit(collateral, 'Approval')
                .withArgs(borrower._address, router.address, max);

            expect(await collateral.allowance(borrower._address, router.address)).to.eq(max);
        });

        // Redeem tokens
        it('Redeems CygLP for deposited LP Token amount and emits { Redeem }', async () => {
            // Redeem with no permit data
            await expect(
                router.connect(borrower).redeem(collateral.address, BigInt(10e18), borrower._address, max, '0x'),
            ).to.emit(collateral, 'Redeem');
        });

        it('LP Token Balance of borrower is slightly more than before Cygnus due to compounding', async () => {
            // Check that CygLP balance of borrower is 0
            expect(await collateral.balanceOf(borrower._address)).to.be.eq(0);

            // Check that borrower has the same LP Token balance they had before interacting with Cygnus
            expect(await joeAvaxLP.balanceOf(borrower._address)).to.be.gt(borrowerInitialLPBalance);
        });
    });
});
