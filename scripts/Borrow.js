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
    let [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

    // Users
    let [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

    // Strategy
    let [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, 6, 997);

    // ═════════════════════ BALANCES ══════════════════════════════════════════════════════════════════════

    console.log('Borrower`s LP balance before Cyg     | %s LPs', (await lpToken.balanceOf(borrower._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower`s DAI balance before Cyg    | %s DAI', (await dai.balanceOf(borrower._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Lender`s LP balance before Cyg       | %s LPs', (await lpToken.balanceOf(lender._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Lender`s DAI balance before Cyg      | %s DAI', (await dai.balanceOf(lender._address)) / 1e18);

    /*════════════════════════════════════════════════════════════════════════════════════════════════════
    
                                   - Borrower Deposits 50 LP Tokens, 
                                   - Lender deposits 1000 DAI,
                                   - Borrower borrows 100 DAI
     
     ════════════════════════════════════════════════════════════════════════════════════════════════════*/

    console.log('----------------------------------------------------------------------------------------------');
    console.log('Price of LP Token                    | %s DAI', (await collateral.getLPTokenPrice()) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower deposits 100 LPs, Lender deposits 1600 DAI');
    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Approve collateral in LP Token
    await lpToken.connect(borrower).approve(collateral.address, max);
    await collateral.connect(borrower).deposit(BigInt(100e18), borrower._address);

    // Lender: Approve borrowable in DAI
    await dai.connect(lender).approve(borrowable.address, max);
    await borrowable.connect(lender).deposit(BigInt(1600e18), lender._address);

    let cygDaiBalanceLender = await borrowable.balanceOf(lender._address);
    let cygLPBalanceBorrower = await collateral.balanceOf(borrower._address);

    console.log('Total Balance of borrowable after    | %s DAI', (await borrowable.totalBalance()) / 1e18);
    console.log('Total Balance of collateral after    | %s LPs', (await collateral.totalBalance()) / 1e18);
    console.log('CygDai balanceOf Lender              | %s CygDai', cygDaiBalanceLender / 1e18);
    console.log('CygLP balanceOf Borrower             | %s CygLP', cygLPBalanceBorrower / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BORROW MAX AMOUNT DAI');
    console.log('----------------------------------------------------------------------------------------------');

    // Max Borrow = accountLiquidity / liquidationIncentive
    const accLiquidity = await collateral.getAccountLiquidity(borrower._address);
    const liqIncentivex = await collateral.liquidationIncentive();
    const maxBorrow = (BigInt(accLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentivex);

    // Approve borrow and borrow max
    await borrowable.connect(borrower).borrowApprove(router.address, max);
    await router.connect(borrower).borrow(borrowable.address, BigInt(maxBorrow), borrower._address, max, '0x');

    let daiBalanceBorrowerAfter = await dai.balanceOf(borrower._address);
    let borrowablesDAIBalanceAfter = await borrowable.totalBalance();

    // Check that Borrower has dai
    console.log('Borrower`s DAI balance after borrow  | %s DAI', daiBalanceBorrowerAfter / 1e18);
    console.log('Borrowables DAI balance after borrow | %s DAI', borrowablesDAIBalanceAfter / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('REINVEST REWARDS');
    console.log('----------------------------------------------------------------------------------------------');

    // Create
    const rewardTokenContract = await dai.attach(rewardToken);

    const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address);
    const balanceBeforeReinvest = await collateral.totalBalance();

    console.log('Borrower`s debt ratio before reinvesting       | % %s', (await collateral.getDebtRatio(borrower._address)) / 1e16,);
    console.log('Collateral`s totalBalance before reinvesting   | %s LP Tokens', balanceBeforeReinvest / 1e18);
    console.log('Reinvestor`s balanceOf token before reinvest   | %s JOE (or other)', reinvestorBalance / 1e18);

    // Increase 18 days
    await time.increase(60 * 60 * 24 * 3);

    console.log('3 days pass.');

    await collateral.connect(safeAddress2).reinvestRewards_y7b();

    const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address);
    const balanceAfterReinvest = await collateral.totalBalance();

    // Debt Ratio of borrower
    console.log('Borrower`s debt ratio after reinvesting        | % %s', (await collateral.getDebtRatio(borrower._address)) / 1e16,);
    console.log('Collateral`s totalBalance after reinvest       | %s LP Tokens', balanceAfterReinvest / 1e18);
    console.log('Reinvestor`s balanceOf token after reinvest    | %s JOE (or other)', reinvestorBalanceAfter / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
  /*

    let r2 = await lpToken.getReserves();
    console.log('Reserves: %s', r2);

    let token0 = await lpToken.token0();
    let token1 = await lpToken.token1();
    let token0c = await lpToken.attach(token0);
    let token1c = await lpToken.attach(token1);
    console.log('Balance of token0: %s', await token0c.balanceOf(collateral.address));
    console.log('Balance of token1: %s', await token1c.balanceOf(collateral.address));
    */
}

deploy();
/*
module.exports = {
    deploy,
};
*/
