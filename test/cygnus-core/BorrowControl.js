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
const make = require('../make.js');
const users = require('../users.js');

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

    // Make Cygnus lending pool and get random users (safe address1, lender, borrower)
    before(async () => {
        // Cygnus contracts and underlyings
        [oracle, factory, router, borrowable, collateral, dai, lpToken] = await make();

        // Users
        [owner, daoReservesManager, safeAddress1, lender, borrower] = await users();

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

    /*
     *
     *  Updates the parameters in CygnusBorrowControl.sol: borrow tracker, reserve factor and kink utilization rate.
     *
     */
    describe('When updating the BorrowControl.sol parameters', async () => {
        describe('When the msg.sender is not factory admin', async () => {
            it('Sets a new borrow tracker: FAIL { MsgSenderNotAdmin }', async () => {
                const borrowTracker = await borrowable.cygnusBorrowTracker();

                await expect(borrowable.connect(safeAddress1).setCygnusBorrowTracker(safeAddress1.address)).to.be
                    .reverted;

                expect(await borrowable.cygnusBorrowTracker()).to.be.eq(borrowTracker);

                expect(await borrowable.cygnusBorrowTracker()).to.be.eq(addressZero);
            });

            it('Sets a new reserve factor: FAIL { MsgSenderNotAdmin }', async () => {
                const reserveFactor = await borrowable.reserveFactor();

                await expect(borrowable.connect(daoReservesManager).setReserveFactor(BigInt(0.09e18))).to.be.reverted;

                expect(await borrowable.reserveFactor()).to.be.eq(reserveFactor);
            });

            it('Sets a new kink rate: FAIL { MsgSenderNotAdmin }', async () => {
                const kinkRatel = await borrowable.kinkUtilizationRate();

                await expect(borrowable.connect(daoReservesManager).setKinkUtilizationRate(BigInt(0.64e18))).to.be
                    .reverted;

                expect(await borrowable.kinkUtilizationRate()).to.be.eq(kinkRatel);
            });
        });

        describe('When the msg.sender is the factory admin', async () => {
            describe('When the updatable parameters are outside of MIN/MAX defined in the contract', async () => {
                it('Sets the borrow tracker as the one already set', async () => {
                    const borrowTrackery = await borrowable.cygnusBorrowTracker();

                    await expect(borrowable.connect(owner).setCygnusBorrowTracker(borrowTrackery)).to.be.reverted;

                    expect(await borrowable.cygnusBorrowTracker()).to.be.eq(borrowTrackery);
                });

                it('Sets a new reserve factor with value > max: FAIL { ParameterNotInRange }', async () => {
                    const reserveFactory = await borrowable.reserveFactor();

                    await expect(borrowable.setReserveFactor(BigInt(1e18))).to.be.reverted;

                    await expect(borrowable.setReserveFactor(BigInt(0.201e18))).to.be.reverted;

                    await expect(borrowable.setReserveFactor(BigInt(max))).to.be.reverted;

                    // Default is 5%
                    expect(await borrowable.reserveFactor()).to.eq(reserveFactory);
                });

                it('Sets a new kink rate parameter > KINK_RATE_MIN: FAIL { ParameterNotInRange }', async () => {
                    const kinky = await borrowable.kinkUtilizationRate();

                    await expect(borrowable.setKinkUtilizationRate(BigInt(0.99e18))).to.be.reverted;

                    await expect(borrowable.setKinkUtilizationRate(BigInt(0.96e18))).to.be.reverted;

                    await expect(borrowable.setKinkUtilizationRate(BigInt(max))).to.be.reverted;

                    // To previously updated in this test
                    expect(await borrowable.kinkUtilizationRate()).to.eq(kinky);
                });

                it('Sets a new kink rate parameter < KINK_RATE_MIN: FAIL { ParameterNotInRange }', async () => {
                    const kinkz = await borrowable.kinkUtilizationRate();

                    await expect(borrowable.setKinkUtilizationRate(BigInt(0.01e18))).to.be.reverted;

                    await expect(borrowable.setKinkUtilizationRate(BigInt(0.45e18))).to.be.reverted;

                    await expect(borrowable.setKinkUtilizationRate(BigInt(0.49e18))).to.be.reverted;

                    // To previously updated in this test
                    expect(await borrowable.kinkUtilizationRate()).to.eq(kinkz);
                });
            });

            describe('When the updatable parameters are within bounds', async () => {
                it('Sets a new borrow tracker and emits { NewCygnusBorrowTracker }', async () => {
                    const oldBorrowTracker = await borrowable.cygnusBorrowTracker();

                    await expect(borrowable.connect(owner).setCygnusBorrowTracker(safeAddress1.address))
                        .to.emit(borrowable, 'NewCygnusBorrowTracker')
                        .withArgs(addressZero, safeAddress1.address);

                    expect(await borrowable.cygnusBorrowTracker()).to.be.eq(safeAddress1.address);
                });

                it('Sets a new reserve factor with value between 0% and 20% and emits { NewReserveFactor }', async () => {
                    const oldReserveFactor = await borrowable.reserveFactor();
                    const newReserveFactor = BigInt(0.12e18);

                    await expect(borrowable.setReserveFactor(newReserveFactor))
                        .to.emit(borrowable, 'NewReserveFactor')
                        .withArgs(oldReserveFactor, newReserveFactor);

                    expect(await borrowable.reserveFactor()).to.eq(newReserveFactor);
                });

                it('Sets a new Utilization Rate between between 50% and 95% and emits { NewKinkUtilizationRate }', async () => {
                    const oldKink = await borrowable.kinkUtilizationRate();
                    const newKink = BigInt(0.85e18);

                    await expect(borrowable.setKinkUtilizationRate(newKink))
                        .to.emit(borrowable, 'NewKinkUtilizationRate')
                        .withArgs(oldKink, newKink);

                    expect(await borrowable.kinkUtilizationRate()).to.eq(newKink);
                });
            });
        });
    });
});
