// Node
const fs = require('fs');
const path = require('path');

// Hardhat
const chai = require('chai');
const hre = require('hardhat');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;

// Custom Errors
const { CygnusCollateralErrors } = require('./errors/CygnusCollateralErrors.js');
const { CygnusTerminalErrors } = require('./errors/CygnusTerminalErrors.js');

chai.use(solidity);

/*
 *  Tests for control functions of Cygnus collateral contracts. Checks for:
 *  - Factory admin
 *  - Default CygnusCollateral.sol state params (liq incentive, liq fee, debt ratio)
 *  - Admin only functions
 *  - Min/Max parameters
 *  - Cygnus borrow contract
 *  - Default oracle and oracle updates
 *
 */
describe('CygnusCollateralControl', function () {
    /*  ─────────────────────────────────────────── constants ──────────────────────────────────────────────  */

    // Max digit in a uint256
    const max = ethers.constants.MaxUint256;

    // 0 address
    const addressZero = ethers.constants.AddressZero;

    // DAI
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // NATIVE
    const nativeToken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    /*  ─────────────────────────────────────── External Contracts ─────────────────────────────────────────  */

    // Underlying LP Token - JOE/AVAX
    const joeAvaxLPAddress = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // Chainlink V3 Aggregators
    // DAI
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';
    // Joe
    const joeAggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';
    // Avax
    const avaxAggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    /*  ──────────────────────────────────────────── Defaults ─────────────────────────────────────────────  */

    // Cygnus Collateral Defaults
    const defaultDebtRatio = BigInt(0.8e18);

    const defaultLiquidationIncentive = BigInt(1.05e18);

    const defaultLiquidationFee = BigInt(0);

    /*  ────────────────────────────────────────── Lending Pool ───────────────────────────────────────────  */

    // Cygnus Collateral customs
    const shuttleBaseRate = BigInt(0.05e18);

    const shuttleKinkRate = BigInt(0.75e18);

    const shuttleMultiplier = BigInt(0.15e18);

    /*  ─────────────────────────────────────────── Addresses ─────────────────────────────────────────────  */

    // Price Oracle
    let nebula, newNebula, evenNewerNebula;

    // Admin, reservesManager, factory
    let owner, safeAddress1, factory;

    // Collateral contract
    let collateral, collateralMock;

    // Object containing lending pool info: borrow, collateral, lp token, oracle, id
    let shuttle;

    before(async () => {
        [owner, safeAddress1] = await ethers.getSigners();

        // Borrow
        const Albireo = await ethers.getContractFactory('CygnusAlbireo');
        // Collateral
        const Deneb = await ethers.getContractFactory('CygnusDeneb');

        // Address of Borrow Deployer
        const albireo = await Albireo.deploy();
        // Address of Collateral Deployer
        const deneb = await Deneb.deploy();

        // Oracle
        const Nebula = await ethers.getContractFactory('ChainlinkNebulaOracle');
        // Address of Oracle
        nebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');
        // Address of Oracle V2
        newNebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');
        // Address of Oracle V3
        evenNewerNebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

        // First nebula
        await nebula.initializeNebula(joeAvaxLPAddress, joeAggregator, avaxAggregator);
        // Dummy checks in case need oracle update - Initialize oracle V2 eth/avax pair
        await newNebula.initializeNebula(joeAvaxLPAddress, joeAggregator, avaxAggregator);
        // Initialize oracle V3 eth/avax pair
        await evenNewerNebula.initializeNebula(joeAvaxLPAddress, joeAggregator, avaxAggregator);

        // Factory
        const Factory = await ethers.getContractFactory('CygnusFactory');

        // Address of Factory
        factory = await Factory.deploy(
            owner.address,
            safeAddress1.address,
            daiAddress,
            nativeToken,
            deneb.address,
            albireo.address,
            nebula.address,
        );

        console.log(factory.address);

        // Deploy joe/avax shuttle
        const Shuttle = await factory.deployShuttle(
            joeAvaxLPAddress,
            shuttleBaseRate,
            shuttleMultiplier,
            shuttleKinkRate,
        );

        // Get the shuttle obj
        shuttle = await factory.getShuttles(joeAvaxLPAddress);

        console.log(shuttle);

        const MockC = await ethers.getContractFactory('MockCygnusCollateral');

        collateral = await MockC.deploy(factory.address, joeAvaxLPAddress, shuttle.cygnusAlbireo);

        console.log(collateral.address);
    });

    /* ════════════════════════════ DEFAULT STATE ════════════════════════════ */

    // Default state
    describe('Default Collateral contract state', function () {
        /*
         *  check for default state. receives parameters from the object deployed
         *  by cygnusdeneb.sol and assigns the underlying, borrow contract and
         *  factory address.
         *
         *  no parameters get passed and each shuttle is launched with default
         *  params
         *
         */
        it('Checks Factory admin is owner address', async () => {
            expect(await factory.admin()).to.eq(owner.address);
        });

        // 80% Debt Ratio
        it('Checks debt ratio is set to default', async () => {
            expect(await collateral.debtRatio()).to.eq(defaultDebtRatio);
        });

        // 5% Liquidation Incentive
        it('Checks liquidation incentive is set to default', async () => {
            expect(await collateral.liquidationIncentive()).to.eq(defaultLiquidationIncentive);
        });

        // 0% liquidation fee
        it('Checks liquidation fee is set to default', async () => {
            expect(await collateral.liquidationFee()).to.eq(defaultLiquidationFee);
        });

        // Factory
        it('Sets the factory address', async () => {
            expect(await collateral.hangar18()).to.eq(factory.address);
        });

        it('Sets underlying as LP Token contract', async () => {
            expect(await collateral.underlying()).to.eq(joeAvaxLPAddress);
        });

        // Borrow contract
        it('Sets cygnus borrow contract', async () => {
            expect(await collateral.albireoDAI()).to.eq(await shuttle.cygnusAlbireo);
        });

        // Oracle
        it('Sets default oracle', async () => {
            expect(await collateral.cygnusNebulaOracle()).to.eq(nebula.address);
        });
    });

    /* ════════════════════════════════ ADMIN ════════════════════════════════ */

    // Admin checks
    describe('Sets updatable parameters: ADMIN', function () {
        /*
         *  Admin control - all should succeed
         *
         *  Checks updatable parameters in collateral contracts such as
         *  liquidation incentives and debt ratios.
         *
         *  Also checks for oracle updates, in the case we need to update
         *
         */
        it('Sets a new shuttle oracle and emits {NewPriceOracle} event', async () => {
            // Update oracle in factory first
            await factory.setNewNebulaOracle(newNebula.address);

            // Update oracle in shuttle with factory's new oracle
            await expect(collateral.setNebulaOracle())
                .to.emit(collateral, 'NewPriceOracle')
                .withArgs(nebula.address, newNebula.address);

            expect(await collateral.cygnusNebulaOracle()).to.eq(newNebula.address);
        });

        // ORACLE
        it('Sets a newer shuttle oracle and emits {NewPriceOracle} event', async () => {
            // Update oracle in factory first
            await factory.setNewNebulaOracle(evenNewerNebula.address);

            // Update oracle in shuttle with factory's new oracle
            await expect(collateral.setNebulaOracle())
                .to.emit(collateral, 'NewPriceOracle')
                .withArgs(newNebula.address, evenNewerNebula.address);

            expect(await collateral.cygnusNebulaOracle()).to.eq(evenNewerNebula.address);
        });

        // debtRatio
        it('Sets a new debt ratio and emits {NewDebtRatio} event', async () => {
            const oldDebtRatio = await collateral.debtRatio();

            const newDebtRatio = BigInt(0.86e18);

            await expect(collateral.setDebtRatio(newDebtRatio))
                .to.emit(collateral, 'NewDebtRatio')
                .withArgs(oldDebtRatio, newDebtRatio);

            expect(await collateral.debtRatio()).to.eq(newDebtRatio);
        });

        // liquidationIncentive
        it('Sets a new liquidation incentive and emits {NewLiquidationIncentive} event', async () => {
            const oldLiq = await collateral.liquidationIncentive();

            const newLiq = BigInt(1.15e18);

            await expect(collateral.setLiquidationIncentive(newLiq))
                .to.emit(collateral, 'NewLiquidationIncentive')
                .withArgs(oldLiq, newLiq);

            expect(await collateral.liquidationIncentive()).to.eq(newLiq);
        });

        // liquidationFee
        it('Sets a new liquidationFee and emits {NewLiquidationFee} event', async () => {
            const oldLiquidationFee = await collateral.liquidationFee();

            const newLiquidationFee = BigInt(0.04e18);

            await expect(collateral.setLiquidationFee(newLiquidationFee))
                .to.emit(collateral, 'NewLiquidationFee')
                .withArgs(oldLiquidationFee, newLiquidationFee);

            expect(await collateral.liquidationFee()).to.eq(newLiquidationFee);
        });
    });

    // reverts from Factory and Pool
    describe('Sets updatable parameters: NON-ADMIN', function () {
        /*
         *
         *  Same tests as above but from Non-Admin account, all should revert
         *
         *
         */
        it('Sets a new factory oracle:FAIL {CygnusFactory__CygnusAdminOnly}', async () => {
            // Update oracle in factory first
            await expect(factory.connect(safeAddress1).setNewNebulaOracle(newNebula.address)).to.be.revertedWith(
                CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN_FACTORY + `("${safeAddress1.address}")`,
            );
        });

        it('Sets a new debt ratio:FAIL {CygnusTerminal__CygnusAdminOnly}', async () => {
            const oldDebtRatio = await collateral.debtRatio();

            const newDebtRatio = BigInt(0.81e18);

            await expect(collateral.connect(safeAddress1).setDebtRatio(newDebtRatio)).to.be.revertedWith(
                CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN,
            );

            expect(await collateral.debtRatio()).to.eq(oldDebtRatio);
        });

        it('Sets a new liquidation incentive:FAIL {CygnusTerminal__CygnusAdminOnly}', async () => {
            const oldLiquidationIncentive = await collateral.liquidationIncentive();

            const newLiquidationIncentive = BigInt(1.15e18);

            await expect(
                collateral.connect(safeAddress1).setLiquidationIncentive(newLiquidationIncentive),
            ).to.be.revertedWith(CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN);

            expect(await collateral.liquidationIncentive()).to.eq(oldLiquidationIncentive);
        });

        it('Sets a new liquidation fee:FAIL {CygnusTerminal__CygnusAdminOnly}', async () => {
            const oldLiquidationFee = await collateral.liquidationFee();

            const newLiquidationFee = BigInt(0.1e18);

            await expect(
                (await collateral.connect(safeAddress1)).setLiquidationFee(newLiquidationFee),
            ).to.be.revertedWith(CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN);

            expect(await collateral.liquidationFee()).to.eq(oldLiquidationFee);
        });
    });

    describe('Updates parameters outside of ranges: ADMIN', function () {
        /*
         *
         *  Admin updates parameters outside valid min/max ranges, all revert
         *
         *
         */
        it('Sets a new debt ratio:FAIL { CygnusCollateralControl__ParameterNotInRange }', async () => {
            // collateral debt ratio
            const oldDebtRatio = await collateral.debtRatio();

            const newDebtRatio = BigInt(0.45e18);

            await expect(collateral.setDebtRatio(newDebtRatio)).to.be.revertedWith(
                CygnusCollateralErrors.PARAMETER_NOT_IN_RANGE,
            );

            expect(await collateral.debtRatio()).to.eq(oldDebtRatio);
        });

        it('Sets a new liquidation fee:FAIL', async () => {
            const oldLiquidationFee = await collateral.liquidationFee();

            const newLiquidationFee = BigInt(0.21e18);

            await expect(collateral.setLiquidationFee(newLiquidationFee)).to.be.revertedWith(
                CygnusCollateralErrors.PARAMETER_NOT_IN_RANGE,
            );

            expect(await collateral.liquidationFee()).to.eq(oldLiquidationFee);
        });

        it('Sets a new liquidation incentive:FAIL', async () => {
            const oldLiquidationIncentive = await collateral.liquidationIncentive();

            const newLiquidationIncentive = BigInt(1.21e18);

            await expect(collateral.setLiquidationIncentive(newLiquidationIncentive)).to.be.revertedWith(
                CygnusCollateralErrors.PARAMETER_NOT_IN_RANGE,
            );
        });
    });
});
