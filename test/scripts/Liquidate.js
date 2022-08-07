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
    let lenderDeposit = BigInt(1000e18);

    // Cygnus contracts and underlyings
    let [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

    // Strategy
    let [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

    // Users to interact with contracts
    let [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

    // Initial dai Balance
    let lenderInitialDaiBalance = await dai.balanceOf(lender._address);

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, 6, 997);

    /*******************************************************************************************************
   
    
                            INTERACTIONS
    
     
      ******************************************************************************************************/

    // Price of 1 LP Token of joe/avax in dai
    const oneLPToken = await collateral.getLPTokenPrice();

    console.log('Price of LP Token                          | %s DAI', (await oneLPToken) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower deposits 100 LPs, Lender deposits 10,000 DAI');
    console.log('----------------------------------------------------------------------------------------------');

    console.log('Borrower`s LP Balance before Cygnus        | %s', (await lpToken.balanceOf(borrower._address)) / 1e18);
    console.log('Lender`s DAI balance before Cygnus         | %s', (await dai.balanceOf(lender._address)) / 1e18);

    // Borrower: Deposits 100 LP Token = ~740 usd
    await lpToken.connect(borrower).approve(router.address, max);
    await router.connect(borrower).mint(collateral.address, BigInt(100e18), borrower._address, max);

    // Lender: Deposits 10000 dai
    await dai.connect(lender).approve(router.address, max);
    await router.connect(lender).mint(borrowable.address, BigInt(13000e18), lender._address, max);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('BEFORE LEVERAGE');
    console.log('----------------------------------------------------------------------------------------------');

    const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address);
    const CygDaiBalanceBeforeL = await borrowable.balanceOf(lender._address);
    const albireoBalanceBeforeL = await borrowable.totalBalance();
    const cygLPTotalBalanceBeforeL = await collateral.totalBalance();
    const daiBalanceBeforeL = await dai.balanceOf(borrower._address);

    console.log('Borrower`s CygLP balance before leverage   | %s CygLP', cygLPBalanceBeforeL / 1e18);
    console.log('Borrowable`s totalBalance before leverage  | %s DAI', albireoBalanceBeforeL / 1e18);
    console.log('Collateral`s totalBalance before leverage  | %s LP TOKENS', cygLPTotalBalanceBeforeL / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER LEVERAGE');
    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);

    const accLiquidity = await collateral.getAccountLiquidity(borrower._address);
    const liqIncentivex = await collateral.liquidationIncentive();

    // Max liq
    const maxBorrow = (BigInt(accLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentivex);
    console.log(maxBorrow);

    // Borrower max leverage (borrows dai equivalent to all acc liquidity)
    await router
        .connect(borrower)
        .leverage(collateral.address, BigInt(maxBorrow) * BigInt(10), borrower._address, max, '0x');

    const cygLPBalanceAfterL = await collateral.balanceOf(borrower._address);
    const CygDaiBalanceAfterL = await borrowable.balanceOf(lender._address);
    const albireoBalanceAfterL = await borrowable.totalBalance();
    const cygLPTotalBalanceAfterL = await collateral.totalBalance();

    const borrowBalanceAfterL = await borrowable.getBorrowBalance(borrower._address);
    const debtRatioAfterL = await collateral.getDebtRatio(borrower._address);

    console.log('Borrower`s borrow balance after leverage   | %s DAI', borrowBalanceAfterL / 1e18);
    console.log('Borrower`s CygLP balance after leverage    | %s CYG-LP', cygLPBalanceAfterL / 1e18);
    console.log('Borrower`s debt ratio after leverage       | % %s', debtRatioAfterL / 1e16);
    console.log('Borrowable`s totalBalance after leverage   | %s DAI', albireoBalanceAfterL / 1e18);
    console.log('Collateral`s totalBalance after leverage   | %s LPs', cygLPTotalBalanceAfterL / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('REINVEST REWARDS');
    console.log('----------------------------------------------------------------------------------------------');

    const balanceBeforeReinvest = await collateral.totalBalance();

    // Create
    const rewardTokenContract = await dai.attach(rewardToken);
    const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address);

    console.log('Collateral`s totalBalance before reinvest  | %s LPs', balanceBeforeReinvest / 1e18);
    console.log('Reinvestor`s totalBalance before reinvest  | %s JOE (or reward token)', reinvestorBalance / 1e18);

    // Increase 7 days
    await time.increase(60 * 60 * 24 * 60);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('60 Days pass...');
    console.log('----------------------------------------------------------------------------------------------');

    await collateral.connect(safeAddress2).reinvestRewards_y7b();

    const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address);
    const balanceAfterReinvest = await collateral.totalBalance();

    console.log('Collateral`s totalBalance after reinvest   | %s LPs', balanceAfterReinvest / 1e18);
    console.log('Reinvestor`s balance of rewardToken after  | %s JOE (or rewardToken)', reinvestorBalanceAfter / 1e18);
    console.log(
        'Borrower`s debt ratio after leverage       | % %s',
        (await collateral.getDebtRatio(borrower._address)) / 1e16,
    );

    console.log('----------------------------------------------------------------------------------------------');
    console.log('LIQUIDATE');
    console.log('----------------------------------------------------------------------------------------------');

    await borrowable.accrueInterest();

    console.log('New borrow balance: %s', (await borrowable.getBorrowBalance(borrower._address)) / 1e18);
    console.log('Balance of DAI liquidator: %s DAI', (await dai.balanceOf(lender._address)) / 1e18);
    console.log('Debt ratio new: % %s', (await collateral.getDebtRatio(borrower._address)) / 1e16);
    console.log('CygLP total balance protocol: %s LPs', (await collateral.totalBalance()) / 1e18);
    console.log('CygLP total balance borrower: %s CygLP', (await collateral.balanceOf(borrower._address)) / 1e18);
    console.log('CygLP total Supply: %s CygLP', (await collateral.totalSupply()) / 1e18);
    console.log('Exchange Rate current: %s', (await collateral.exchangeRate()) / 1e18);

    // Checks that liquidate amount is never above borrowed balance in router (ie if user borrowed 20 dai, router will repay 20 dai, not 5000)
    await router
        .connect(lender)
        .liquidate(borrowable.address, BigInt(10000e18), borrower._address, lender._address, max);

    let borrowerBalanceCollAfterLiq = await collateral.balanceOf(borrower._address);
    let lenderBalanceCollAfterLiq = await collateral.balanceOf(lender._address);
    let borrowBalanceAfterLiq = await borrowable.getBorrowBalance(borrower._address);

    console.log('Borrower balance of collateral             | %s CygLP', borrowerBalanceCollAfterLiq / 1e18);
    console.log('Liquidator balance of collateral           | %s CygLP', lenderBalanceCollAfterLiq / 1e18);
    console.log('Borrow Balance of borrower                 | %s DAI', borrowBalanceAfterLiq / 1e18);
}

deploy();
/*
module.exports = {
    deploy,
};
*/
