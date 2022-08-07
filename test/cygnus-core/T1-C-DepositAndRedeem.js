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
const Strategy = require('../Strategy.js');

// Matchers
chai.use(solidity);

/*
 *
 *  Simple deposit and redeem for all borrow contracts
 *
 */
context('CYGNUS BORROW: DEPOSIT DAI & REDEEM CYGDAI', function () {
    // dai and LP Token contracts
    let dai, lpToken;

    // Cygnus Contracts
    let oracle, factory, router, borrowable, collateral;

    // Main accounts that interact with Cygnus during this test
    let owner, daoReservesManager, safeAddress2, borrower, lender;

    // Strategy
    let voidRouter, masterChef, rewardToken, pid, swapFee;

    // 100 LPs
    let borrowerDeposit = BigInt(100e18);

    before(async () => {
        // Cygnus contracts and underlyings
        [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

        // Users
        [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

        // Masterchef reward reinvest or other strategy
        [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

        // Initial DAI and LP balances for lender and borrower
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);
        borrowerInitialLPBalance = await lpToken.balanceOf(borrower._address);

        console.log('------------------------------------------------------------------------------');
        console.log('Lender   | %s | Balance: %s DAI', lender._address, lenderInitialDaiBalance / 1e18);
        console.log('------------------------------------------------------------------------------');
        console.log('Borrower | %s | Balance: %s LPs', borrower._address, borrowerInitialLPBalance / 1e18);
        console.log('------------------------------------------------------------------------------');

        await collateral.chargeVoid(voidRouter, masterChef, rewardToken, pid, swapFee);

    });

    describe('When Cygnus factory deploys collateral and borrow contracts', function () {
        describe('When the collateral contract is deployed', function () {
            // Collateral
            it('Sets the name of the collateral pool token', async () => {
                expect(await collateral.name()).to.eq('Cygnus: Collateral');
            });
            it('Has an exchange rate equal to INITIAL_EXCHANGE_RATE (1e18)', async () => {
                expect(await collateral.exchangeRate()).to.eq(BigInt(1e18));
            });

            it('Has a total supply of 0', async () => {
                expect(await collateral.totalSupply()).to.eq(0);
            });

            it('Has a total balance of 0', async () => {
                expect(await collateral.totalBalance()).to.eq(0);
            });

            it('Sets the underlying asset as the LP Token', async () => {
                expect(await collateral.underlying()).to.eq(lpToken.address);
            });
        });

        describe('When the borrow contract is deployed', function () {
            // Borrowable
            it('Sets the name of borrow pool token', async () => {
                expect(await borrowable.name()).to.eq('Cygnus: Borrow');
            });

            it('Has the default exchange rate of 1e18', async () => {
                expect(await borrowable.exchangeRateStored()).to.eq(BigInt(1e18));
            });

            it('Has a total supply of 0', async () => {
                expect(await borrowable.totalSupply()).to.eq(0);
            });

            it('Has a total balance of 0', async () => {
                expect(await borrowable.totalBalance()).to.eq(0);
            });

            it('Sets the underling asset as DAI', async () => {
                expect(await borrowable.underlying()).to.eq(dai.address);
            });
        });
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
    });

    describe('Borrower deposits LP Token for CygLP', function () {
        // Mints without approving router in LP contract
        it('Deposits LP Token in collateral contract before approving router in LP contract: FAIL { LP_CONTRACT }', async () => {
            await expect(
                router
                    .connect(borrower)
                    .mint(collateral.address, BigInt(10e18), borrower._address, max),
            ).to.be.reverted;
        });

        // Approve Router in LP
        it('Approves router in LP contract', async () => {
            await lpToken.connect(borrower).approve(router.address, max);

            expect(await lpToken.allowance(borrower._address, router.address)).to.eq(max);
        });

        // Mint tokens
        it('Deposits LP Token in collateral and mints CygLP and emit { Mint }', async () => {
            await expect(
                router
                    .connect(borrower)
                    .mint(collateral.address, BigInt(10e18), borrower._address, max),
            )
                .to.emit(collateral, 'Mint')
                .withArgs(router.address, borrower._address, BigInt(10e18), BigInt(10e18));
        });

        // Has Cyg LP
        it('Borrower has CygLP in wallet', async () => {
            expect(await collateral.balanceOf(borrower._address)).to.eq(BigInt(10e18));
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
    });
});
