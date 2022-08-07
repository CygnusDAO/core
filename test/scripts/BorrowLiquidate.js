const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');

// Custom
const Make = require('../test/Make.js');
const Users = require('../test/Users.js');
const Strategy = require('../test/Strategy.js');

// OE
const { time } = require('@openzeppelin/test-helpers');

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

async function deploy() {
    // Cygnus contracts and underlyings
    const [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

    // Users
    const [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

    // Strategy
    const [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, 6, 997);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('Price of LP Token                    | %s DAI', (await collateral.getLPTokenPrice()) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('INITIAL BALANCES OF LENDER/BORROWER');
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower`s LP balance before Cyg     | %s LPs', (await lpToken.balanceOf(borrower._address)) / 1e18);
    console.log('Borrower`s DAI balance before Cyg    | %s DAI', (await dai.balanceOf(borrower._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Lender`s LP balance before Cyg       | %s LPs', (await lpToken.balanceOf(lender._address)) / 1e18);
    console.log('Lender`s DAI balance before Cyg      | %s DAI', (await dai.balanceOf(lender._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');

    /* ════════════════════════════════════════════════════════════════════════════════════════════════════
     *
     *              BORROW LIQUIDATION
     *
     *              - Borrower Deposits 100 LP Tokens, 
     *              - Lender deposits 1000 DAI
     *              - Borrower borrows maximum DAI (accountLiquidity / liquidationIncentive)
     *              - User is at 100% debt ratio (not liquidatable)
     *              - Random user reinvests rewards
     *              - User's debt ratio decreases
     *              - We increase liquidation incentive to put them at a liquidatable state
     *              - Some user holding DAI liquidates and receives CygLP equal to:
     *
     *                   (repaidAmount / lpTokenPrice * liqIncentive) / exchangeRate
     *
     ════════════════════════════════════════════════════════════════════════════════════════════════════ */

    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower deposits 100 LPs, Lender deposits 1000 DAI');

    // Borrower: Approve router in LP and mint CygLP
    await lpToken.connect(borrower).approve(router.address, max);
    await router.connect(borrower).mint(collateral.address, BigInt(100e18), borrower._address, max);

    // Lender: Approve router in dai and mint Cygdai
    await dai.connect(lender).approve(router.address, max);
    await router.connect(lender).mint(borrowable.address, BigInt(1000e18), lender._address, max);

    const daiBalanceBorrower = await dai.balanceOf(borrower._address);
    const cygLPBalanceBorrower = await collateral.balanceOf(borrower._address);
    const lpBalanceBorrower = await lpToken.balanceOf(borrower._address);

    // Check that we have dai
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower`s LP bal. after deposit     | %s LPs', lpBalanceBorrower / 1e18);
    console.log('Borrower`s CygLP bal. after deposit  | %s CygLP', cygLPBalanceBorrower / 1e18);
    console.log('----------------------------------------------------------------------------------------------');

    const daiBalanceLender = await dai.balanceOf(lender._address);
    const cygDaiBalanceLender = await borrowable.balanceOf(lender._address);
    const cygLPBalanceLender = await collateral.balanceOf(lender._address);
    const lpBalanceLender = await lpToken.balanceOf(lender._address);

    // Check that we have dai
    console.log('Lender`s DAI balance after deposit   | %s DAI', daiBalanceLender / 1e18);
    console.log('Lender`s CygDAI bal. after deposit   | %s CygDAI', cygDaiBalanceLender / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BORROW 100 DAI');
    console.log('----------------------------------------------------------------------------------------------');

    // Max Borrow = accountLiquidity / liquidationIncentive
    const accLiquidity = await collateral.getAccountLiquidity(borrower._address);
    const liqIncentivex = await collateral.liquidationIncentive();
    const maxBorrow = (BigInt(accLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentivex);

    // Borrower: Approve borrow and borrow max
    await borrowable.connect(borrower).borrowApprove(router.address, max);
    await router.connect(borrower).borrow(borrowable.address, BigInt(maxBorrow), borrower._address, max, '0x');

    const daiBalanceBorrowerAfter = await dai.balanceOf(borrower._address);
    const cygLPBalanceBorrowerAfter = await collateral.balanceOf(borrower._address);

    // Check that Borrower has dai
    console.log('Borrower`s DAI balance after borrow  | %s DAI', daiBalanceBorrowerAfter / 1e18);
    console.log('Borrower`s CygLP bal. after borrow   | %s CygLP', cygLPBalanceBorrowerAfter / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BEFORE REINVEST REWARDS');
    console.log('----------------------------------------------------------------------------------------------');

    const borrowersDebtRatioBeforeR = await collateral.getDebtRatio(borrower._address);
    const collateralTotalBalanceBeforeR = await collateral.totalBalance();
    const exchangeRateBeforeR = await collateral.exchangeRate();

    // Check Users debt ratio
    console.log('Borrowers debt ratio before reinvest | %s %', borrowersDebtRatioBeforeR / 1e16);
    console.log('Total Balance of collateral before   | %s LPs', collateralTotalBalanceBeforeR / 1e18);
    console.log('Exchange Rate of collateral before   | %s LPs', exchangeRateBeforeR / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER REINVEST REWARDS (3 DAYS)');
    console.log('----------------------------------------------------------------------------------------------');

    /// //////////// Increase 3 days ///////////////
    await time.increase(60 * 60 * 24 * 3);
    /// ////////////////////////////////////////////

    // Reinvest rewards
    await collateral.reinvestRewards_y7b();

    const borrowersDebtRatioAfterR = await collateral.getDebtRatio(borrower._address);
    const collateralTotalBalanceAfterR = await collateral.totalBalance();
    const exchangeRateAfterR = await collateral.exchangeRate();

    console.log('Borrowers debt ratio after reinvest  | % %s', borrowersDebtRatioAfterR / 1e16);
    console.log('Total Balance of collateral after    | %s LPs', collateralTotalBalanceAfterR / 1e18);
    console.log('Exchange Rate of collateral after    | %s', exchangeRateAfterR / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('LIQUIDATE');
    console.log('----------------------------------------------------------------------------------------------');

    // Debt ratio is at ~99.99% due to reinvestment of rewards, increase liq incentive to put user in liquidatable state
    await collateral.setLiquidationIncentive(BigInt(1.051e18));
    // Liquidating always accrues interest. We do it manually get to get the accurate borrow amount to check for errors
    await borrowable.accrueInterest();

    const borrowersDebtRatioNew = await collateral.getDebtRatio(borrower._address);
    const borrowersBorrowBal = await borrowable.getBorrowBalance(borrower._address);
    console.log('Borrowers debt ratio after liq inct. | % %s', borrowersDebtRatioNew / 1e16);
    console.log('Borrowers borrow balance             | %s DAI', borrowersBorrowBal / 1e18);


    // Checks that liquidate amount is never above borrowed balance in router (ie if user borrowed 20 dai, router will repay 20 dai, not 5000)
    await router
        .connect(lender)
        .liquidate(borrowable.address, BigInt(5000e18), borrower._address, lender._address, max);

    console.log(
        'Borrower`s CygLP balance after liq   | %s CygLP',
        (await collateral.balanceOf(borrower._address)) / 1e18,
    );
    console.log(
        'Lender`s CygLP balance after liq     | %s CygLP',
        (await collateral.balanceOf(lender._address)) / 1e18,
    );
    console.log('----------------------------------------------------------------------------------------------');
}

deploy();
/*
module.exports = {
    deploy,
};
*/
