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

    let lenderInitialDaiBalance; // Balance before depositing and interacting with Cygnus
    let lenderFinalDaiBalance; // Balance after interacting and redeeming
    const lenderDeposit = BigInt(2000e18); // 2000 DAI

    let borrowerInitialDaiBalance; // Balance before depositing and interacting with Cygnus
    let borrowerFinalDaiBalance; // Balance after interacting and redeeming
    const borrowerDeposit = BigInt(10e18); // 10 LP Tokens

    // TraderJoe swapping fee

    before(async () => {
        // Cygnus contracts and underlyings
        [
            oracle,
            factory,
            router,
            borrowable,
            collateral,
            dai,
            lpToken,
            voidRouter,
            masterChef,
            rewardToken,
            pid,
            swapFee,
        ] = await make();

        // Users
        [owner, daoReservesManager, safeAddress2, lender, borrower] = await users();

        // Initial DAI and LP balances for lender and borrower
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);
        borrowerInitialLPBalance = await lpToken.balanceOf(borrower._address);

        console.log('------------------------------------------------------------------------------');

        console.log('Lender   | %s | Balance: %s DAI', lender._address, lenderInitialDaiBalance / 1e18);

        console.log('------------------------------------------------------------------------------');

        console.log('Borrower | %s | Balance: %s LPs', borrower._address, borrowerInitialLPBalance / 1e18);

        console.log('------------------------------------------------------------------------------');

        await collateral.chargeVoid(voidRouter, masterChef, rewardToken, pid, swapFee);

        // Lender deposits 10000 DAI
        await dai.connect(lender).approve(router.address, max);
        await router.connect(lender).mint(borrowable.address, lenderDeposit, lender._address, max);

        // Borrower deposits 10 LP tokens
        await lpToken.connect(borrower).approve(router.address, max);
        await router.connect(borrower).mint(collateral.address, borrowerDeposit, borrower._address, max);

        // Get initial dai balance
        borrowerInitialDaiBalance = (await dai.balanceOf(borrower._address)) / 1e18;
    });

    /*
     *
     *
     *  START TESTS
     *
     *
     */
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
            const liquidity = collateralInDai.liquidity / 1.05;

            // Borrow max liquidity + slighlty more, revert
            await expect(
                router
                    .connect(borrower)
                    .borrow(borrowable.address, BigInt(liquidity + 100000), borrower._address, max, '0x'),
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

            const maxLiquidity = collateralInDai.liquidity / 1.05;

            // Borrow
            await expect(
                router.connect(borrower).borrow(borrowable.address, BigInt(maxLiquidity), borrower._address, max, '0x'),
            ).to.emit(borrowable, 'Borrow');
        });

        // Check DAI balance of borrower
        it('User has DAI in wallet', async () => {
            // Initial dai balance was 0
            expect(await dai.balanceOf(borrower._address)).to.be.gt(borrowerInitialDaiBalance);
        });

        // Debt ratio of borrower should be max 100%
        it('Borrower debt ratio is < 100% due to compounding of rewards', async () => {
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(userDebtRatio).to.be.within(BigInt(0.99e18), BigInt(1.01e18));
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

            const newDebtRatio = BigInt(0.95e18);

            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio))
                .to.emit(collateral, 'NewDebtRatio')
                .withArgs(oldDebtRatio, newDebtRatio);
        });

        // Debt ratio of borrower should be max 100%
        it('Borrower debt ratio is less than before', async () => {
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            // Check user's debt ratio
            expect(userDebtRatio).to.be.within(BigInt(0.85e18), BigInt(1.0e18));

            console.log(userDebtRatio);

            // Check that debtRatio is updated
            expect(await collateral.debtRatio()).to.be.eq(BigInt(0.95e18));
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

        // Debt ratio of borrower should be ~99%
        it('Borrower debt ratio is 99%', async () => {
            // Static call the debt ratio
            const userDebtRatio = await collateral.getDebtRatio(borrower._address);

            // Check user's debt ratio
            expect(userDebtRatio).to.be.within(BigInt(0.99e18), BigInt(1.01e18));

            // Check that debtRatio is updated
            expect(await collateral.debtRatio()).to.be.eq(BigInt(0.95e18));
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
            expect(userDebtRatio).to.be.within(BigInt(0.99e18), BigInt(1.01e18));
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

        it('Checks that borrowers Debt Ratio is now 50% less than before (should be ~50%)', async () => {
            const borrowersDebtRatio = await collateral.getDebtRatio(borrower._address);

            expect(borrowersDebtRatio).to.be.within(BigInt(0.49e18), BigInt(0.51e18));
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

        it('Checks that total balance is increased and users debt ratio is lower', async () => {
            let newBalance = await collateral.totalBalance();
            let newDebtRatio = await collateral.getDebtRatio(borrower._address);

            console.log('TOTAL BALANCE NEW: %s', newBalance);
            console.log('DEBT RATIO NEW: %s', newDebtRatio);
        });
    });
});
