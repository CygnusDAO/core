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
    describe('When the LP holder deposits into Cygnus and doesnt borrow', async () => {
        it('Owns the equivalent of the deposited in CygLP', async () => {
            const cygLPBalance = await collateral.balanceOf(borrower._address);

            expect(cygLPBalance).to.be.eq(borrowerDeposit);
        });

        it('Increases totalSupply of collateral pools', async () => {
            const totalSupplyC = await collateral.totalSupply();

            expect(totalSupplyC).to.be.eq(borrowerDeposit);
        });

        it('Increases totalBalance of collateral pools', async () => {
            const totalBalance = await collateral.totalBalance();

            expect(totalBalance).to.be.eq(borrowerDeposit);
        });

        it('Has account liquidity equal to deposited amount of LP * price of 1 LP in DAI * debtRatio', async () => {
            // User liquidiity measured in DAI
            const accountLiq = await collateral.getAccountLiquidity(borrower._address);
            // Balance of CygLP
            const depositedAmount = BigInt(await collateral.balanceOf(borrower._address));
            // Price of 1 deposited LP Token in DAI
            const lpTokenPrice = BigInt(await collateral.getLPTokenPrice());
            // Debt ratio default at 90%
            const debtRatio = BigInt(await collateral.debtRatio());

            const liquidity = (((depositedAmount * lpTokenPrice) / BigInt(1e18)) * debtRatio) / BigInt(1e18);

            expect(accountLiq.liquidity).to.be.eq(liquidity);
        });

        it('Has 0 debt ratio', async () => {
            expect(await collateral.getDebtRatio(borrower._address)).to.eq(0);
        });
    });

    describe('When the DAI holders deposits into Cygnus', async () => {
        it('Owns the equivalent of the deposited in CygDAI', async () => {
            const cygDaiBalance = await borrowable.balanceOf(lender._address);

            expect(cygDaiBalance).to.be.eq(lenderDeposit);
        });

        it('increases totalsupply of the borrowable pools', async () => {
            const totalSupplyB = await borrowable.totalSupply();

            expect(totalSupplyB).to.be.eq(lenderDeposit);
        });

        it('increases totalBalance of the borrowable pools', async () => {
            const totalBalanceB = await borrowable.totalBalance();

            expect(totalBalanceB).to.be.eq(lenderDeposit);
        });
    });

    describe('When borrower deposited and takes out a loan', async () => {
        describe('When the borrower doesnt call `borrowApprove` in borrowable', async () => {
            it('Reverts the transaction: FAIL { CygnusBorrowApprove__BorrowNotAllowed }', async () => {
                await expect(
                    router.connect(borrower).borrow(borrowable.address, BigInt(10e18), borrower._address, max, '0x'),
                ).to.be.reverted;
            });
        });

        describe('When the borrower approves borrow in borrowable contract', async () => {
            // Approves router and emits event
            it('Allows router to borrow and emits { Approval }', async () => {
                await expect(borrowable.connect(borrower).borrowApprove(router.address, max))
                    .to.emit(borrowable, 'BorrowApproval')
                    .withArgs(borrower._address, router.address, max);
            });

            describe('When the borrower borrows max amount of DAI without leverage', async () => {
                // Formula in CollateralModel.sol
                it('Checks the max borrow amount is equal to { (deposited LP * LP Token Price * DebtRatio) / LiqIncentive }', async () => {
                    // Deposited 10 LP Tokens
                    const depositedAmount = Number(borrowerDeposit) / 1e18;
                    // current LP TokenPrice
                    const lpTokenPrice = (await collateral.getLPTokenPrice()) / 1e18;
                    // Debt Ratio  (90%)
                    const debtRatio = (await collateral.debtRatio()) / 1e18;
                    // Liq incentive (5%);
                    const liqIncentitive = (await collateral.liquidationIncentive()) / 1e18;
                    /// /// MAX AMOUNT /////
                    const maxAmount = (depositedAmount * lpTokenPrice * debtRatio) / liqIncentitive;

                    /// /// USER LIQ /////
                    const userLiquidity = await collateral.getAccountLiquidity(borrower._address);
                    const userLiquidityLiq = userLiquidity.liquidity / 1e18 / liqIncentitive;

                    expect(maxAmount).to.be.within(userLiquidityLiq * 0.999999, userLiquidityLiq * 1.000001);

                    // Assuming the user had 0 dai initial ()
                    // expect(maxAmount).to.be.within(maxAmount - 1, maxAmount + 1);
                });

                // Error in Borrow.sol
                it('Reverts if borrowAmount > totalBalance', async () => {
                    const totalBalanceBorrowable = await borrowable.totalBalance();

                    // Max Borrow and emit `Borrow` event
                    await expect(
                        router
                            .connect(borrower)
                            .borrow(
                                borrowable.address,
                                BigInt(totalBalanceBorrowable + 1),
                                borrower._address,
                                max,
                                '0x',
                            ),
                    ).to.be.reverted;
                });

                it('Borrows max amount and emits { Borrow }', async () => {
                    // MAX = user liquidity / liqIncentive (1.05 = 5%)
                    // LP Deposited * DebtRatio
                    const userLiquidity = await collateral.getAccountLiquidity(borrower._address);
                    const liq = await collateral.liquidationIncentive();

                    // Liq incentive is 5%
                    const maxBorrow = userLiquidity.liquidity / 1.05;

                    console.log(maxBorrow);

                    // Max Borrow and emit `Borrow` event
                    await expect(
                        router
                            .connect(borrower)
                            .borrow(borrowable.address, BigInt(maxBorrow), borrower._address, max, '0x'),
                    ).to.emit(borrowable, 'Borrow');
                });

                // Checks CollateralModel.sol
                it('Has 100% debt ratio', async () => {
                    // Users debt ratio (99.99%)
                    expect(await collateral.getDebtRatio(borrower._address)).to.be.within(
                        BigInt(0.9999e18),
                        BigInt(1.0001e18),
                    );
                });

                // Checks CollateralModel.sol
                it('Has 0 account liquidity', async () => {
                    // Get user's remaining liquidity
                    const userLiquidity = await collateral.getAccountLiquidity(borrower._address);

                    // Account for 4 decimal points rounding errors
                    expect(userLiquidity.liquidity).to.be.within(0, 9000);
                });

                // Because no leverage user has control of DAI
                it('Has DAI in their wallet', async () => {
                    const daiBalance = (await dai.balanceOf(borrower._address)) / 1e18;

                    expect(daiBalance).to.be.gt(borrowerInitialDaiBalance);
                });

                // Check that borrowing mints reserves
                it('Mints DAO reserves on borrows', async () => {
                    const daoReserves = await borrowable.balanceOf(daoReservesManager.address);

                    expect(daoReserves).to.be.gt(0);
                });
            });
        });
    });
});
