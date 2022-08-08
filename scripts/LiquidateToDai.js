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
    let [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

    // Users
    let [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

    // Strategy
    let [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

    // Initial dai Balance
    let lenderInitialDaiBalance = await dai.balanceOf(lender._address);

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, pid, swapFee);

    /*******************************************************************************************************
   
    
                            INTERACTIONS
    
     
      ******************************************************************************************************/

    // Set debt ratio to 1, leaving only liquidationIncentive to take effect (5% default)
    await collateral.connect(owner).setDebtRatio(BigInt(1e18));

    // Price of 1 LP Token of joe/avax in dai
    const oneLPToken = await collateral.getLPTokenPrice();

    console.log('Price of LP Token                          | %s DAI', (await oneLPToken) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower deposits 100 LPs, Lender deposits 5000 DAI');
    console.log('----------------------------------------------------------------------------------------------');

    console.log('Borrower`s LP Balance before Cygnus        | %s', (await lpToken.balanceOf(borrower._address)) / 1e18);
    console.log('Lender`s DAI balance before Cygnus         | %s', (await dai.balanceOf(lender._address)) / 1e18);

    // Borrower: Approve collateral in LP Token
    await lpToken.connect(borrower).approve(collateral.address, max);
    await collateral.connect(borrower).deposit(BigInt(100e18), borrower._address);

    // Lender: Approve borrowable in DAI
    await dai.connect(lender).approve(borrowable.address, max);
    await borrowable.connect(lender).deposit(BigInt(15000e18), lender._address);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BEFORE LEVERAGE');
    console.log('----------------------------------------------------------------------------------------------');

    const cygLPBalanceOfBorrowerBeforeL = await collateral.balanceOf(borrower._address);
    const albireoBalanceBeforeL = await borrowable.totalBalance();
    const cygLPTotalBalanceBeforeL = await collateral.totalBalance();
    const exchangeRateBeforeL = await collateral.exchangeRate();

    console.log('Borrower`s CygLP balance before leverage   | %s CygLP', cygLPBalanceOfBorrowerBeforeL / 1e18);
    console.log('Borrowable`s totalBalance before leverage  | %s DAI', albireoBalanceBeforeL / 1e18);
    console.log('Collateral`s totalBalance before leverage  | %s LP TOKENS', cygLPTotalBalanceBeforeL / 1e18);
    console.log('Collateral`s CygLP to LP exchangeRate      | %s', exchangeRateBeforeL / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER LEVERAGE');
    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);

    // Borrower 5x leverage (borrows dai equivalent to 400 LP Tokens)
    await router
        .connect(borrower)
        .leverage(collateral.address, BigInt(oneLPToken) * BigInt(400), borrower._address, max, '0x');

    const cygLPBalanceOfBorrowerAfterL = await collateral.balanceOf(borrower._address);
    const albireoBalanceAfterL = await borrowable.totalBalance();
    const cygLPTotalBalanceAfterL = await collateral.totalBalance();
    const exchangeRateAfterL = await collateral.exchangeRate();

    console.log('Borrower`s CygLP balance after leverage    | %s CygLP', cygLPBalanceOfBorrowerAfterL / 1e18);
    console.log('Borrowable`s totalBalance after leverage   | %s DAI', albireoBalanceAfterL / 1e18);
    console.log('Collateral`s totalBalance after leverage   | %s LPs', cygLPTotalBalanceAfterL / 1e18);
    console.log('Collateral`s CygLP to LP exchangeRate      | %s', exchangeRateAfterL / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('REINVEST REWARDS');
    console.log('----------------------------------------------------------------------------------------------');

    const balanceBeforeReinvest = await collateral.totalBalance();

    // Creates new contract for rewardToken -> Attach rewardtoken address to dai ABI as same for balanceOf
    const rewardTokenContract = await dai.attach(rewardToken);
    const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address);

    console.log('Collateral`s totalBalance before reinvest  | %s LPs', balanceBeforeReinvest / 1e18);
    console.log('Reinvestor`s totalBalance before reinvest  | %s JOE (or reward token)', reinvestorBalance / 1e18);

    // Increase 7 days
    await time.increase(60 * 60 * 24 * 7);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('7 Days pass...');
    console.log('----------------------------------------------------------------------------------------------');

    await collateral.connect(safeAddress2).reinvestRewards_y7b();

    const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address);
    const balanceAfterReinvest = await collateral.totalBalance();

    console.log('Collateral`s totalBalance after reinvest   | %s LPs', balanceAfterReinvest / 1e18);
    console.log('Reinvestor`s balance of rewardToken after  | %s JOE (or rewardToken)', reinvestorBalanceAfter / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BEFORE LIQUIDATING TO DAI');
    console.log('----------------------------------------------------------------------------------------------');

    // Reduce debt ratio to simulate liquidation -> This should only be allowed during emergencies
    await collateral.connect(owner).setDebtRatio(BigInt(0.8e18));

    // Approve
    await collateral.connect(lender).approve(router.address, max);
    await lpToken.connect(lender).approve(router.address, max);

    const collateralTotalBalanceBeforeLiqui = await collateral.totalBalance();
    const cygLPBalanceOfBorrowerBeforeLiqui = await collateral.balanceOf(borrower._address);
    const cygLPBalanceOfLiquidatorBeforeLiqui = await collateral.balanceOf(lender._address);
    const daiBalanceOfLiquidatorBeforeLiqui = await dai.balanceOf(lender._address);

    console.log('Collateral`s totalBalance before liq       | %s LPs', collateralTotalBalanceBeforeLiqui / 1e18);
    console.log('Borrower`s CygLP balance before liq        | %s CygLP', cygLPBalanceOfBorrowerBeforeLiqui / 1e18);
    console.log('Liquidator CygLP balance before liq        | %s CygLP', cygLPBalanceOfLiquidatorBeforeLiqui / 1e18);
    console.log('Liquidator DAI balance before liq          | %s DAI', daiBalanceOfLiquidatorBeforeLiqui / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER LIQUIDATING TO DAI');
    console.log('----------------------------------------------------------------------------------------------');

    await router
        .connect(lender)
        .liquidateToDai(borrowable.address, BigInt(5000e18), borrower._address, lender._address, max);

    const collateralTotalBalanceAfterLiqui = await collateral.totalBalance();
    const cygLPBalanceOfBorrowerAfterLiqui = await collateral.balanceOf(borrower._address);
    const cygLPBalanceOfLiquidatorAfterLiqui = await collateral.balanceOf(lender._address);
    const daiBalanceOfLiquidatorAfterLiqui = await dai.balanceOf(lender._address);

    console.log('Collateral`s totalBalance after liq        | %s LPs', collateralTotalBalanceAfterLiqui / 1e18);
    console.log('Borrower`s CygLP balance after liq         | %s CygLP', cygLPBalanceOfBorrowerAfterLiqui / 1e18);
    console.log('Liquidator balance of collateral after liq | %s CygLP', cygLPBalanceOfLiquidatorAfterLiqui / 1e18);
    console.log('Liquidator DAI balance after liq           | %s DAI', daiBalanceOfLiquidatorAfterLiqui / 1e18);
}

deploy();
/*
module.exports = {
    deploy,
};
*/
