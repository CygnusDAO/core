// Hardhat
const chai = require('chai');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;
const hre = require('hardhat');

// Node
const fs = require('fs');
const path = require('path');

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

// Custom
const Make = require('../Make.js');
const Users = require('../Users.js');

// Matchers
chai.use(solidity);

/*
 *  Tests for control functions of Cygnus borrow contracts. Checks for:
 *  - Factory admin
 *  - Default CygnusBorrow.sol state params (shuttleMultiplier, kink, base rate, etc.)
 *  - Admin only functions
 *  - Min/Max parameters
 *  - Cygnus collateral contract
 *  - Reserves manager contract
 */
context('CygnusBorrowControl.sol - Admin control and updatable parameters', function () {
    // dai and LP Token contracts
    let dai, lpToken;

    // Cygnus Contracts
    let oracle, factory, router, borrowable, collateral;

    // Main accounts that interact with Cygnus during this test
    let owner, daoReservesManager, safeAddress1, borrower, lender;

    // Make Cygnus lending pool and get random Users (safe address1, lender, borrower)
    before(async () => {
        // Cygnus contracts and underlyings
        [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

        // Users
        [owner, daoReservesManager, safeAddress1, lender, borrower] = await Users();

        // Initial DAI and LP balances for lender and borrower
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);
        borrowerInitialLPBalance = await lpToken.balanceOf(borrower._address);

        console.log('------------------------------------------------------------------------------');
        console.log('  DAI Balance of lender   | %s DAI', lenderInitialDaiBalance / 1e18);
        console.log('------------------------------------------------------------------------------');
        console.log('  LP Balance of borrower  | %s LPs', borrowerInitialLPBalance / 1e18);
        console.log('------------------------------------------------------------------------------');
    });

    describe('When the borrow contract is deployed', function () {
        /*
         *  Check for default state. Receives parameters from the object
         */
        // Exchange rate
        it('Has the default exchangeRateStored', async () => {
            expect(await borrowable.exchangeRateStored()).to.eq(BigInt(1e18));
        });

        // Reserve factor
        it('Has the default reserveFactor', async () => {
            expect(await borrowable.reserveFactor()).to.eq(BigInt(0.05e18));
        });

        // Factory address
        it('Sets the factory address in the constructor', async () => {
            expect(await borrowable.hangar18()).to.eq(factory.address);
        });

        // Borrowable underlying
        it('Sets underlying as DAI.e contract in the constructor', async () => {
            expect(await borrowable.underlying()).to.eq(dai.address);
        });

        // Collateral contract
        it('Sets the Cygnus collateral contract in the constructor', async () => {
            let shuttle = await factory.getShuttles(lpToken.address);

            expect(await borrowable.collateral()).to.eq(shuttle.collateral);
        });
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

        // 5% Liquidation Incentive
        it('Checks liquidation incentive is set to default', async () => {
            expect(await collateral.liquidationIncentive()).to.eq(BigInt(1.05e18));
        });

        // 0% liquidation fee
        it('Checks liquidation fee is set to default', async () => {
            expect(await collateral.liquidationFee()).to.eq(0);
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
            expect(await collateral.cygnusDai()).to.eq(await shuttle.cygnusAlbireo);
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
            await expect(factory.connect(safeAddress1).setNewNebulaOracle(newNebula.address)).to.be.reverted;
        });

        it('Sets a new liquidation incentive:FAIL {CygnusTerminal__CygnusAdminOnly}', async () => {
            const oldLiquidationIncentive = await collateral.liquidationIncentive();

            const newLiquidationIncentive = BigInt(1.15e18);

            await expect(collateral.connect(safeAddress1).setLiquidationIncentive(newLiquidationIncentive)).to.be
                .reverted;

            expect(await collateral.liquidationIncentive()).to.eq(oldLiquidationIncentive);
        });

        it('Sets a new liquidation fee:FAIL {CygnusTerminal__CygnusAdminOnly}', async () => {
            const oldLiquidationFee = await collateral.liquidationFee();

            const newLiquidationFee = BigInt(0.1e18);

            await expect((await collateral.connect(safeAddress1)).setLiquidationFee(newLiquidationFee)).to.be.reverted;

            expect(await collateral.liquidationFee()).to.eq(oldLiquidationFee);
        });
    });

    describe('Updates parameters outside of ranges: ADMIN', function () {
        it('Sets a new liquidation fee:FAIL', async () => {
            const oldLiquidationFee = await collateral.liquidationFee();

            const newLiquidationFee = BigInt(0.21e18);

            await expect(collateral.setLiquidationFee(newLiquidationFee)).to.be.reverted;

            expect(await collateral.liquidationFee()).to.eq(oldLiquidationFee);
        });

        it('Sets a new liquidation incentive:FAIL', async () => {
            const oldLiquidationIncentive = await collateral.liquidationIncentive();

            const newLiquidationIncentive = BigInt(1.21e18);

            await expect(collateral.setLiquidationIncentive(newLiquidationIncentive)).to.be.reverted;
        });
    });
});
