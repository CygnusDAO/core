const hre = require('hardhat');
const ethers = hre.ethers;

const fs = require('fs');
const path = require('path');

// Custom
const make = require('../test/make.js');
const users = require('../test/users.js');

// OE
const { time } = require('@openzeppelin/test-helpers');

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

async function deploy() {
    let lenderDeposit = BigInt(1000e18);

    // Cygnus contracts and underlyings
    let [
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

    // Initial dai Balance
    let lenderInitialDaiBalance = await dai.balanceOf(lender._address);

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, 6, 997);

    /*******************************************************************************************************
   
    
                            Deposit 1 LP Token, 1000 DAI, and borrow 1 DAI
    
     
      ******************************************************************************************************/

    console.log('Price of LP Token                    | %s DAI', (await collateral.getLPTokenPrice()) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower deposits 50 LPs, Lender deposits 1000 DAI');
    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Approve router in LP and mint CygLP
    await lpToken.connect(borrower).approve(router.address, max);
    await router.connect(borrower).mint(collateral.address, BigInt(50e18), borrower._address, max);

    // Lender: Approve router in dai and mint Cygdai
    await dai.connect(lender).approve(router.address, max);
    await router.connect(lender).mint(borrowable.address, BigInt(1000e18), lender._address, max);

    let daiBalanceBorrower = await dai.balanceOf(borrower._address);
    let cygLPBalanceBorrower = await collateral.balanceOf(borrower._address);

    // Check that we have dai
    console.log('Borrower`s DAI balance before borrow | %s DAI', daiBalanceBorrower / 1e18);
    console.log('Borrower`s CygLP bal. before borrow  | %s CygLP', cygLPBalanceBorrower / 1e18);

    // Borrower: Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);
    // Borrower: Borrow
    await router.connect(borrower).borrow(borrowable.address, BigInt(1e18), borrower._address, max, '0x');

    let daiBalanceBorrowerAfter = await dai.balanceOf(borrower._address);
    let cygLPBalanceBorrowerAfter = await collateral.balanceOf(borrower._address);

    // Check that Borrower has dai
    console.log('Borrower`s DAI balance after borrow  | %s DAI', daiBalanceBorrowerAfter / 1e18);
    console.log('Borrower`s CygLP bal. after borrow   | %s CygLP', cygLPBalanceBorrowerAfter / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BEFORE REINVEST REWARDS');
    console.log('----------------------------------------------------------------------------------------------');

    let borrowersDebtRatioBeforeR = await collateral.getDebtRatio(borrower._address);
    let collateralTotalBalanceBeforeR = await collateral.totalBalance();
    let exchangeRateBeforeR = await collateral.exchangeRate();

    // Check users debt ratio
    console.log('Borrowers debt ratio before reinvest | %s %', borrowersDebtRatioBeforeR / 1e16);
    console.log('Total Balance of collateral before   | %s LPs', collateralTotalBalanceBeforeR / 1e18);
    console.log('Exchange Rate of collateral before   | %s LPs', exchangeRateBeforeR / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER REINVEST REWARDS (3 DAYS)');
    console.log('----------------------------------------------------------------------------------------------');

    /////////////// Increase 3 days ///////////////
    await time.increase(60 * 60 * 24 * 3);
    ///////////////////////////////////////////////

    // Reinvest rewards
    await collateral.reinvestRewards_y7b();

    let borrowersDebtRatioAfterR = await collateral.getDebtRatio(borrower._address);
    let collateralTotalBalanceAfterR = await collateral.totalBalance();
    let exchangeRateAfterR = await collateral.exchangeRate();

    console.log('Borrowers debt ratio after reinvest  | %s %', borrowersDebtRatioAfterR / 1e16);
    console.log('Total Balance of collateral after    | %s LPs', collateralTotalBalanceAfterR / 1e18);
    console.log('Exchange Rate of collateral after    | %s', exchangeRateAfterR / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
}

deploy();
/*
module.exports = {
    deploy,
};
*/
