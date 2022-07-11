// Node
const fs = require('fs');
const path = require('path');

// Hardhat
const chai = require('chai');
const hre = require('hardhat');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;

// Custom Errors
const { CygnusBorrowErrors } = require('./errors/CygnusBorrowErrors.js');
const { CygnusTerminalErrors } = require('./errors/CygnusTerminalErrors.js');

chai.use(solidity);

/*
 *  Tests for control functions of Cygnus borrow contracts. Checks for:
 *  - Factory admin
 *  - Default CygnusBorrow.sol state params (shuttleMultiplier, kink, base rate, etc.)
 *  - Admin only functions
 *  - Min/Max parameters
 *  - Cygnus collateral contract
 *  - Reserves manager contract
 *
 */
describe('CYGNUS BORROW: ADMIN CONTROLS', function () {
    /*  ───────────────────────────────────────────── Ethers ───────────────────────────────────────────────  */

    // Max digit in a uint256
    const max = ethers.constants.MaxUint256;

    // 0 address
    const addressZero = ethers.constants.AddressZero;

    // DAI
    const daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    // NATIVE
    const nativeToken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    /*  ─────────────────────────────────────── External Contracts ─────────────────────────────────────────  */

    // Underlying LP Token - ETH/AVAX
    const ethAvaxLPAddress = '0xFE15c2695F1F920da45C30AAE47d11dE51007AF9';

    // Chainlink V3 Aggregators
    // DAI
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // ETH
    const ethAggregator = '0x976B3D034E162d8bD72D6b9C989d545b839003b0';

    // AVAX
    const avaxAggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    /*  ────────────────────────────────────────── Lending Pool ───────────────────────────────────────────  */

    // Cygnus Borrow customs
    const shuttleBaseRate = BigInt(0.05e18);

    const shuttleKinkRate = BigInt(0.75e18);

    const shuttleMultiplier = BigInt(0.1e18);

    /*  ─────────────────────────────────────────── Addresses ─────────────────────────────────────────────  */

    // Admin, reservesManager, factory
    let owner, user, reservesManager, reservesManagerNew, factory;

    // Borrow contract
    let borrowable, borrowableMock;

    // shuttle obj
    let shuttle;

    before(async () => {
        [owner, user, reservesManager, reservesManagerNew] = await ethers.getSigners();

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

        // Address of Oracle deployed with DAI
        const nebula = await Nebula.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

        // ETH-_AVAX
        await nebula.initializeNebula(ethAvaxLPAddress, ethAggregator, avaxAggregator);

        // Factory
        const Factory = await ethers.getContractFactory('CygnusFactory');

        // Address of Factory
        factory = await Factory.deploy(
            owner.address,
            reservesManager.address,
            daiAddress,
            nativeToken,
            deneb.address,
            albireo.address,
            nebula.address,
        );

        // Deploy 1 borrow contract with DAI as underlying and 1 collateral contract wtih ETH/AVAX LP as underlying
        const Shuttle = await factory.deployShuttle(
            ethAvaxLPAddress,
            shuttleBaseRate,
            shuttleMultiplier,
            shuttleKinkRate,
        );

        // Get the shuttle
        shuttle = await factory.getShuttles(ethAvaxLPAddress);

        /*
         *
         *  Attach mock for custom reverts, else cant see errors from create2
         *
         */
        const MockB = await ethers.getContractFactory('MockCygnusBorrow');

        borrowable = await MockB.deploy(
            factory.address,
            daiAddress,
            shuttle.cygnusDeneb,
            shuttleBaseRate,
            shuttleMultiplier,
            shuttleKinkRate,
            reservesManager.address,
        );
    });

    /* ════════════════════════════ DEFAULT STATE ════════════════════════════ */

    // Default state
    describe('Default Borrow contract state after deployment', function () {
        /*
         *  Check for default state. Receives parameters from the object deployed
         *  by cygnusalbireo.sol and assigns the underlying DAI, collateral contract,
         *  factory address along with the interest rate parameters unique to this pool:
         *
         *  - Multiplier
         *  - Jump Mulitplier
         *  - Base Rate
         *  - Kink
         *
         */
        it('Checks factory admin is owner address', async () => {
            expect(await factory.admin()).to.eq(owner.address);
        });

        // Exchange rate
        it('Checks initial exchange rate stored is 1 after deployment', async () => {
            expect(await borrowable.exchangeRateStored()).to.eq(BigInt(1e18));
        });

        // Reserve factor
        it('Checks reserve factor is set to default', async () => {
            expect(await borrowable.reserveFactor()).to.eq(BigInt(0.05e18));
        });

        // Factory address
        it('Sets the factory address', async () => {
            expect(await borrowable.hangar18()).to.eq(factory.address);
        });

        // Borrowable underlying
        it('Sets underlying as DAI.e contract', async () => {
            expect(await borrowable.underlying()).to.eq(daiAddress);
        });

        // Collateral contract
        it('Sets cygnus collateral contract', async () => {
            expect(await borrowable.collateral()).to.eq(await shuttle.cygnusDeneb);
        });

        // Factory address
        it('Sets the borrow tracker contract', async () => {
            expect(await borrowable.cygnusBorrowTracker()).to.eq(reservesManager.address);
        });

        // Multiplier
        it('Sets shuttleMultiplier per year as the same as deployment argument', async () => {
            expect(await borrowable.multiplierPerYear()).to.eq(shuttleMultiplier);
        });

        // Base rate
        it('Sets base rate per year as the same as deployment argument', async () => {
            expect(await borrowable.baseRatePerYear()).to.eq(shuttleBaseRate);
        });

        // Util
        it('Sets kink as the same as deployment argument', async () => {
            expect(await borrowable.kink()).to.eq(shuttleKinkRate);
        });
    });

    describe('Sets updatable parameters: ADMIN', async () => {
        /*
         *  Admin control - all should succeed
         *
         *  Checks updatable parameters in borrow contracts such as
         *  multiplier, jump, kink rate, reserves manager, reserves factor, etc.
         *
         *  Also checks for oracle updates, in the case we need to update
         *
         */
        it('Sets a new borrow tracker and emits { NewCygnusBorrowTracker }', async () => {
            await expect(borrowable.setCygnusBorrowTracker(reservesManagerNew.address))
                .to.emit(borrowable, 'NewCygnusBorrowTracker')
                .withArgs(reservesManager.address, reservesManagerNew.address);

            expect(await borrowable.cygnusBorrowTracker()).to.be.eq(reservesManagerNew.address);
        });

        it('Sets a new reserve factor with value between 0% and 20% and emits { NewReserveFactor }', async () => {
            const oldReserveFactor = await borrowable.reserveFactor();

            const newReserveFactor = BigInt(0.12e18);

            await expect(borrowable.setReserveFactor(newReserveFactor))
                .to.emit(borrowable, 'NewReserveFactor')
                .withArgs(oldReserveFactor, newReserveFactor);

            expect(await borrowable.reserveFactor()).to.eq(newReserveFactor);
        });

        it('Sets a new kink rate parameter between min and max and emits { NewKinkUtilizationRate }', async () => {
            const newKinkRate = BigInt(0.83e18);

            await expect(borrowable.setKinkUtilizationRate(newKinkRate))
                .to.emit(borrowable, 'NewKinkUtilizationRate')
                .withArgs(shuttleKinkRate, newKinkRate);

            expect(await borrowable.kink()).to.eq(newKinkRate);
        });

        it('Sets a new Kink Multiplier between 0 and KINK_RATE_MAX and emits { NewKinkMultiplier }', async () => {
            const newKinkMultiplier = 3;
            const oldKinkMultiplier = await borrowable.kinkMultiplier();

            await expect(borrowable.setKinkMultiplier(newKinkMultiplier))
                .to.emit(borrowable, 'NewKinkMultiplier')
                .withArgs(oldKinkMultiplier, newKinkMultiplier);

            expect(await borrowable.kinkMultiplier()).to.eq(newKinkMultiplier);
        });
    });

    describe('Sets updatable parameters: NON-ADMIN', async () => {
        /*
         *  Non-Admin - should all revert with same error message { MsgSenderNotAdmin }
         *
         */
        it('Sets a new borrow tracker: FAIL { MsgSenderNotAdmin }', async () => {
            await expect(
                borrowable.connect(user).setCygnusBorrowTracker(reservesManagerNew.address),
            ).to.be.revertedWith(CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN);

            expect(await borrowable.cygnusBorrowTracker()).to.be.eq(reservesManagerNew.address);
        });

        it('Sets a new reserve factor: FAIL { MsgSenderNotAdmin }', async () => {
            const reserveF = await borrowable.reserveFactor();

            await expect(borrowable.connect(user).setReserveFactor(BigInt(0.04e18))).to.be.revertedWith(
                CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN,
            );

            expect(await borrowable.reserveFactor()).to.be.eq(reserveF);
        });

        it('Sets a new kink rate: FAIL { MsgSenderNotAdmin }', async () => {
            const newKinkRate = BigInt(0.64e18);

            await expect(borrowable.connect(user).setKinkUtilizationRate(BigInt(0.64e18))).to.be.revertedWith(
                CygnusTerminalErrors.MSG_SENDER_NOT_ADMIN,
            );

            expect(await borrowable.kink()).to.be.eq(BigInt(0.83e18));
        });
    });
    describe('Sets updatable parameters outside of ranges: ADMIN', async () => {
        it('Sets a new reserve factor with value > max: FAIL { ParameterNotInRange }', async () => {
            const reserveFactorx = await borrowable.reserveFactor();

            await expect(borrowable.setReserveFactor(BigInt(1e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            await expect(borrowable.setReserveFactor(BigInt(0.201e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );
            await expect(borrowable.setReserveFactor(BigInt(max))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            // Default is 5%
            expect(await borrowable.reserveFactor()).to.eq(reserveFactorx);
        });

        it('Sets a new kink rate parameter > KINK_RATE_MIN: FAIL { ParameterNotInRange }', async () => {
            const kinkx = await borrowable.kink();

            await expect(borrowable.setKinkUtilizationRate(BigInt(0.99e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            await expect(borrowable.setKinkUtilizationRate(BigInt(0.96e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            await expect(borrowable.setKinkUtilizationRate(BigInt(max))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            // To previously updated in this test
            expect(await borrowable.kink()).to.eq(kinkx);
        });

        it('Sets a new kink rate parameter < KINK_RATE_MIN: FAIL { ParameterNotInRange }', async () => {
            const kinky = await borrowable.kink();

            await expect(borrowable.setKinkUtilizationRate(BigInt(0.01e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            await expect(borrowable.setKinkUtilizationRate(BigInt(0.45e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            await expect(borrowable.setKinkUtilizationRate(BigInt(0.49e18))).to.be.revertedWith(
                CygnusBorrowErrors.PARAMETER_NOT_IN_RANGE,
            );

            // To previously updated in this test
            expect(await borrowable.kink()).to.eq(kinky);
        });
    });
});
