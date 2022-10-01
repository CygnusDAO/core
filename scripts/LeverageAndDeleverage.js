const hre = require("hardhat");
const ethers = hre.ethers;

// Custom
const Make = require("../test/Make.js");
const Users = require("../test/Users.js");
const Strategy = require("../test/Strategy.js");

// OE
const { time } = require("@openzeppelin/test-helpers");

// JS
const fs = require("fs");
const path = require("path");

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

async function deploy() {
  // Cygnus contracts and underlyings
  let [oracle, factory, router, borrowable, collateral, usdc, lpToken] = await Make();

  let [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

  // Users
  let [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

  // INITIALIZE VOID

  // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
  await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, pid, swapFee);

  /***********************************************************************************************************
   
    
     CYGNUS INTERACTIONS - Connect to the router and leverage position by `_x`
    
     
     ********************************************************************************************************/

  const _x = BigInt(3);

  // Price of 1 LP Token of joe/avax in usdc
  const oneLPToken = await collateral.getLPTokenPrice();

  console.log("----------------------------------------------------------------------------------------------");
  console.log("PRICE OF 1 LP TOKEN                            | %s USDC", oneLPToken / 1e6);
  console.log("----------------------------------------------------------------------------------------------");

  let lpBalance = await lpToken.balanceOf(borrower._address);

  //    let lpTokenBalanceBeforeDeposit = (await lpToken.balanceOf(borrower._address)) / 1e18;
  //    console.log('Borrower`s LP balance before deposit           | %s LP Tokens', lpTokenBalanceBeforeDeposit);
  //
  let usdcBalanceBeforeDeposit = (await usdc.balanceOf(lender._address)) / 1e6;
  console.log("Lender`s USDC balance before deposit           | %s USDC", usdcBalanceBeforeDeposit);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("Borrower deposits 100 LPs in CygnusCollateral, Lender deposits 30,000 USDC in CygnusBorrow");
  console.log("----------------------------------------------------------------------------------------------");

  // Borrower: Approve collateral in LP Token
  await lpToken.connect(borrower).approve(collateral.address, max);
  await collateral.connect(borrower).deposit(BigInt(lpBalance), borrower._address);

  // Lender: Approve borrowable in USDC
  await usdc.connect(lender).approve(borrowable.address, max);
  await borrowable.connect(lender).deposit(BigInt(30000e6), lender._address);

  console.log("BEFORE LEVERAGE");
  console.log("----------------------------------------------------------------------------------------------");

  const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address);
  console.log("Borrower`s CygLP balance before leverage       | %s CygLP", cygLPBalanceBeforeL / 1e18);

  const albireoBalanceBeforeL = await borrowable.totalBalance();
  console.log("Borrowable`s totalBalance before leverage      | %s USDC", albireoBalanceBeforeL / 1e6);

  const cygLPTotalBalanceBeforeL = await collateral.totalBalance();
  console.log("Collateral`s total LP Tokens before leverage   | %s LP Tokens", cygLPTotalBalanceBeforeL / 1e18);

  // const usdcBalanceBeforeL = await usdc.balanceOf(borrower._address);
  // console.log('Borrower`s USDC balance before leverage         | %s USDC', usdcBalanceBeforeL / 1e18);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("13x LEVERAGE (MAX ALLOWED)");
  console.log("----------------------------------------------------------------------------------------------");

  // Borrower: Approve borrow
  await borrowable.connect(borrower).borrowApprove(router.address, max);

  let accountLiquidity = await collateral.getAccountLiquidity(borrower._address);
  let liqIncentive = await collateral.liquidationIncentive();
  let maxLiquidity = (BigInt(accountLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentive);
  console.log(maxLiquidity);

  // Borrower
  await lpToken.connect(borrower).approve(router.address, max);
  await usdc.connect(borrower).approve(router.address, max);

  // leverage by _x
  await router
    .connect(borrower)
    .leverage(collateral.address, maxLiquidity * _x, borrower._address, max, "0x", { gasLimit: 9000000 });

  // Borrower`s borrow balance
  const borrowBalanceAfter = await borrowable.getBorrowBalance(borrower._address);
  console.log("Borrower`s USDC debt after x13 leverage         | %s USDC", borrowBalanceAfter / 1e6);

  // Debt Ratio of borrower
  console.log(
    "Borrower`s debt ratio after x13 leverage       | % %s",
    (await collateral.getDebtRatio(borrower._address)) / 1e16,
  );

  // CygLP balance of borrower
  const denebBalanceAfterL = await collateral.balanceOf(borrower._address);
  console.log("Borrower`s CygLP balance after x13 leverage    | %s CygLP", denebBalanceAfterL / 1e18);

  // CygUSD totalBalance
  const albireoBalanceAfterL = await borrowable.totalBalance();
  console.log("Borrowable`s USDC balance after x13 leverage    | %s USDC", albireoBalanceAfterL / 1e6);

  // CygLP totalBalance
  const totalBalanceC = await collateral.totalBalance();
  console.log("Collateral`s totalBalance after x13 leverage   | %s LP Tokens", totalBalanceC / 1e18);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("REINVEST REWARDS");
  console.log("----------------------------------------------------------------------------------------------");

  // Create
  const rewardTokenContract = await usdc.attach(rewardToken);

  const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address);
  const balanceBeforeReinvest = await collateral.totalBalance();

  console.log(
    "Borrower`s debt ratio before reinvesting       | % %s",
    (await collateral.getDebtRatio(borrower._address)) / 1e16,
  );
  console.log("Collateral`s totalBalance before reinvesting   | %s LP Tokens", balanceBeforeReinvest / 1e18);
  console.log("Reinvestor`s balanceOf token before reinvest   | %s JOE (or other)", reinvestorBalance / 1e18);

  // Increase 10 days
  await time.increase(60 * 60 * 24 * 10);

  console.log("10 days pass");

  await collateral.connect(safeAddress2).reinvestRewards_y7b();

  const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address);
  const balanceAfterReinvest = await collateral.totalBalance();

  // Debt Ratio of borrower
  console.log(
    "Borrower`s debt ratio after reinvesting        | % %s",
    (await collateral.getDebtRatio(borrower._address)) / 1e16,
  );
  console.log("Collateral`s totalBalance after reinvest       | %s LP Tokens", balanceAfterReinvest / 1e18);
  console.log("Reinvestor`s balanceOf token after reinvest    | %s JOE (or other)", reinvestorBalanceAfter / 1e18);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("AFTER DELEVERAGE");
  console.log("----------------------------------------------------------------------------------------------");

  // Deleverage up to original deposited amount + estimate of swap fees (0.3% for each swap and we're doing 6 swaps max)
  await collateral.connect(borrower).approve(router.address, max);
  const maxBalance = await collateral.balanceOf(borrower._address);
  const owedDai = await borrowable.getBorrowBalance(borrower._address);
  const deleverageAmount = BigInt((owedDai / oneLPToken) * 1e18);

  await router
    .connect(borrower)
    .deleverage(collateral.address, BigInt(deleverageAmount) + BigInt(2e18), max, "0x", { gasLimit: 9000000 });

  const newBalance = await collateral.balanceOf(borrower._address);

  // Redeem CygLP
  // await router.connect(borrower).redeem(collateral.address, newBalance, borrower._address, max, '0x');

  const finalDenebBalance = await collateral.balanceOf(borrower._address);
  const finalAlbireoBalance = await borrowable.totalBalance();
  const outstandingBalance = await borrowable.getBorrowBalance(borrower._address);
  const totalBalanceD = await collateral.totalBalance();

  const usdcBalanceBorrower = await usdc.balanceOf(borrower._address);

  console.log("Borrower`s borrow balance after deleverage     | %s USDC", outstandingBalance / 1e6);
  console.log("Borrower`s CygLP balance after deleverage      | %s CygLP", finalDenebBalance / 1e18);
  console.log("Borrowable`s totalBalance after deleverage     | %s USDC", finalAlbireoBalance / 1e6);
  console.log("Collateral`s totalBalance after deleverage     | %s LP Tokens", totalBalanceD / 1e18);

  console.log("Borrower`s USDC balance after deleverage       | %s USDC", usdcBalanceBorrower / 1e6);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("REDEEM AND LEAVE CYGNUS FOREVER");
  console.log("----------------------------------------------------------------------------------------------");

  // Redeem CygLP
  const balanceCygLPBorrower = await collateral.balanceOf(borrower._address);
  await collateral.connect(borrower).redeem(balanceCygLPBorrower, borrower._address, borrower._address);

  // Redeem CygUSDC
  const balanceCygDaiLender = await borrowable.balanceOf(lender._address);
  await borrowable.connect(lender).redeem(balanceCygDaiLender, lender._address, lender._address);

  const finalLPBalance = await lpToken.balanceOf(borrower._address);
  const finalUsdcBalance = await usdc.balanceOf(lender._address);
  const usdcBalanceAfter = await usdc.balanceOf(borrower._address);

  // If doing a full deleverage the router converts eveyrthing to USDC, sends back owed amount to borrowable and
  // transfers remaining USDC to borrower. It is best to not deleverage 100% of the position, instead calc balance
  console.log("Borrower`s USDC balance after de-leverage      | %s USDC", usdcBalanceAfter / 1e6);
  console.log("Lender`s USDC balance after redeem and exit    | %s USDC", finalUsdcBalance / 1e6);
  console.log("Borrower`s LP balance after redeem and exit    | %s", finalLPBalance / 1e18);

  // Collateral balance and supply
  console.log("totalBalance of collateral after full redeem   | %s LPs", (await collateral.totalBalance()) / 1e18);
  console.log("totalSupply of collateral after full redeem    | %s CygLP", (await collateral.totalSupply()) / 1e18);

  // Borrowables balance and supply
  // Only USDC left and CygUSD are dao reserves
  let totalSupply = (await borrowable.totalSupply()) / 1e6;
  console.log("totalBalance of borrowable after full redeem   | %s USDC ", (await borrowable.totalBalance()) / 1e6);
  console.log("totalSupply of borrowable after full redeem    | %s CygUSD", totalSupply / 1e6);

  // await borrowable.exchangeRate();
  // let reserves = (await borrowable.balanceOf(daoReservesManager.address)) / 1e6;
  // console.log("CygnusDAOReserves` balanceOf CygUSD            | %s CygUSD", reserves);
}

deploy();
/*
module.exports = {
    deploy,
};
*/
