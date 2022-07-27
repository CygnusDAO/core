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

    let lenderInitialDaiBalance;

    let lenderDeposit = BigInt(1000e18);

    before(async () => {
        // Cygnus contracts and underlyings
        [oracle, factory, router, borrowable, collateral, dai, lpToken] = await make();

        // Users
        [owner, daoReservesManager, safeAddress2, lender, borrower] = await users();

        // Initial DAI and LP balances for lender and borrower
        lenderInitialDaiBalance = await dai.balanceOf(lender._address);
        borrowerInitialLPBalance = await lpToken.balanceOf(borrower._address);

        console.log('------------------------------------------------------------------------------');
        console.log('DAI Balance of lender   | %s DAI', lenderInitialDaiBalance / 1e18);
        console.log('------------------------------------------------------------------------------');
        console.log('LP Balance of borrower  | %s LPs', borrowerInitialLPBalance / 1e18);
        console.log('------------------------------------------------------------------------------');
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

    // MINTS
    describe('Lender deposits DAI', function () {
        // Fail before approval
        it('Deposits dai in borrowable and mints CygDAI without approving router in Dai: FAIL { DAI_ERROR }', async () => {
            // DAI error
            await expect(router.connect(lender).mint(borrowable.address, lenderDeposit, lender._address, max)).to.be
                .reverted;
        });

        it('Approves router in dai contract', async () => {
            await dai.connect(lender).approve(router.address, max);

            expect(await dai.allowance(lender._address, router.address)).to.eq(max);
        });

        // Mint and transfer event
        it('Deposits dai in borrowable and mints CygDAI and emits { Mint }', async () => {
            await expect(router.connect(lender).mint(borrowable.address, lenderDeposit, lender._address, max))
                .to.emit(borrowable, 'Mint')
                .withArgs(router.address, lender._address, lenderDeposit, lenderDeposit);
        });

        // Check that user has CygDAI and new dai Balance
        it('Has CygDAI in wallet', async () => {
            // CygDAI amount
            expect(await borrowable.balanceOf(lender._address)).to.eq(lenderDeposit);

            // Has less DAI
            expect(await dai.balanceOf(lender._address)).to.eq(BigInt(lenderInitialDaiBalance) - lenderDeposit);
        });
    });

    // REDEEMS
    describe('Lender redeems CygDAI for dai', function () {
        it('Redeems CygDAI for deposited amount without approving router in borrowable: FAIL { Erc20__InsufficientAllowance }', async () => {
            await expect(router.connect(lender).redeem(borrowable.address, lenderDeposit, lender._address, max, '0x'))
                .to.be.reverted;
        });

        it('Approves router in Borrow contract and emits { Approval }', async () => {
            // Approve router in borrowable
            await expect(borrowable.connect(lender).approve(router.address, max))
                .to.emit(borrowable, 'Approval')
                .withArgs(lender._address, router.address, max);

            expect(await borrowable.allowance(lender._address, router.address)).to.eq(max);
        });

        it('Redeems CygDAI for more than deposited amount: FAIL', async () => {
            // Another Lender: Random DAI
            await network.provider.request({
                method: 'hardhat_impersonateAccount',
                params: ['0xdfd74e3752c187c4ba899756238c76cbeefa954b'],
            });

            // Random Lender
            anotherLender = await ethers.provider.getSigner('0xdfd74e3752c187c4ba899756238c76cbeefa954b');

            await dai.connect(anotherLender).approve(router.address, max);

            await expect(
                router.connect(anotherLender).mint(borrowable.address, BigInt(500e18), anotherLender._address, max),
            )
                .to.emit(borrowable, 'Mint')
                .withArgs(router.address, anotherLender._address, BigInt(500e18), BigInt(500e18));

            await expect(router.redeem(borrowable.address, lenderInitialDaiBalance + BigInt(1e18), lender._address, max, '0x')).to.be.reverted;
        });

        it('Redeems CygDAI for deposited amount and emits { Redeem }', async () => {
            let balance = await borrowable.balanceOf(lender._address);

            // Redeem with no permit data
            await expect(router.connect(lender).redeem(borrowable.address, balance, lender._address, max, '0x'))
                .to.emit(borrowable, 'Redeem')
                .withArgs(router.address, lender._address, balance, balance);
        });

        it('DAI Balance of lender is the same as before interacting wtih Cygnus if no one borrows', async () => {
            // Check that CygDAI balance of lender is 0
            expect(await borrowable.balanceOf(lender._address)).to.be.eq(0);

            // Check that lender has the same dai balance they had before interacting with Cygnus when no borrows
            expect(await dai.balanceOf(lender._address)).to.be.eq(lenderInitialDaiBalance);
        });
    });

    // Shouldn't accrue reserves as no borrows yet
    describe('When there are 0 borrows there are no reserves, borrow rate or exchange rate differences', function () {
        it('Has 0 reserves accrued', async () => {
            expect(await borrowable.totalReserves()).to.eq(0);
        });

        it('Has 0 borrow rate', async () => {
            expect(await borrowable.borrowRate()).to.eq(0);
        });

        it('Has 0 total borrows accrued', async () => {
            expect(await borrowable.totalBorrows()).to.eq(0);
        });

        it('Has no interest accruals', async () => {
            await borrowable.connect(lender).accrueInterest();

            expect(await borrowable.borrowIndex()).to.eq(BigInt(1e18));
        });

        it('Has the same exchange rate as initial', async () => {
            expect(await borrowable.exchangeRateStored()).to.eq(BigInt(1e18));
        });

        it('Has the same exchange rate as initial (static call as borrow exchangeRate() is non-payable)', async () => {
            expect(await borrowable.callStatic.exchangeRate()).to.eq(BigInt(1e18));
        });
    });
});
