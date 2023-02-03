// eslint-disable-next-line
const hre = require("hardhat");
const ethers = hre.ethers;

const path = require("path");

// Custom
const Make = require(path.resolve(__dirname, "../test/MakeInch.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));
const Strategy = require(path.resolve(__dirname, "../test/Strategy.js"));
const leverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/OneInchLeverage.js"));

// eslint-disable-next-line
const { time } = require("@openzeppelin/test-helpers");

// Ethers
const max = ethers.constants.MaxUint256;

async function liquidate() {
  // Cygnus contracts and underlyings
  const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

  // Strategy
  const [voidRouter, masterChef, rewardToken, pid] = await Strategy();

  // Users to interact with contracts
  const [owner, , safeAddress2, lender, borrower] = await Users();

  // Get native
  const nativeToken = await router.nativeToken();

  // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

  // Initialize with: DEX ROUTER / MiniChefV3  / reward token / pool id
  await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, pid);

  /*****************************************************************************************************
    
                            INTERACTIONS - LIQUIDATE
     
  ******************************************************************************************************/

  // Price of 1 LP Token of joe/avax in usdc
  const oneLPToken = await collateral.getLPTokenPrice();

  console.log("Price of LP Token                          | %s USDC", (await oneLPToken) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");
  console.log("Borrower deposits 100 LPs, Lender deposits 10,000 USDC");
  console.log("----------------------------------------------------------------------------------------------");

  console.log("Borrower`s LP Balance before Cygnus        | %s", (await lpToken.balanceOf(borrower._address)) / 1e18);
  console.log("Lender`s USDC balance before Cygnus         | %s", (await usdc.balanceOf(lender._address)) / 1e6);

  // Borrower: Approve collateral in LP Token
  await lpToken.connect(borrower).approve(collateral.address, max);
  await collateral.connect(borrower).deposit(BigInt(1e18), borrower._address);

  // Lender: Approve borrowable in USDC
  await usdc.connect(lender).approve(borrowable.address, max);
  await borrowable.connect(lender).deposit(BigInt(100000e6), lender._address);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("BEFORE LEVERAGE");
  console.log("----------------------------------------------------------------------------------------------");

  const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address);
  const albireoBalanceBeforeL = await borrowable.totalBalance();
  const cygLPTotalBalanceBeforeL = await collateral.totalBalance();

  console.log("Borrower`s CygLP balance before leverage   | %s CygLP", cygLPBalanceBeforeL / 1e18);
  console.log("Borrowable`s totalBalance before leverage  | %s USDC", albireoBalanceBeforeL / 1e6);
  console.log("Collateral`s totalBalance before leverage  | %s LP TOKENS", cygLPTotalBalanceBeforeL / 1e18);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("AFTER LEVERAGE");
  console.log("----------------------------------------------------------------------------------------------");

  const accLiquidity = await collateral.getAccountLiquidity(borrower._address);
  const liqIncentivex = await collateral.liquidationIncentive();

  // Max liq
  const maxBorrow = (BigInt(accLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentivex);
  console.log("Max Borrow: %s", maxBorrow);

  const leverageAmount = BigInt(maxBorrow) * BigInt(10);

  // Byte array with data from 1inch 'swap' calls
  const leverageCalls = await leverageSwapData(
    chainId,
    lpToken,
    nativeToken,
    usdc.address,
    router.address,
    leverageAmount,
  );

  await usdc.connect(borrower).approve(router.address, max);

  await router.connect(borrower).leverage(
    collateral.address, // Cygnus Collateral address
    borrowable.address, // Cygnus Borrowable address
    leverageAmount, // Amount of USDC to borrow from borrowable contract
    0, // Min amount of LP Tokens to receive (frontend using current LP Token price)
    borrower._address, // Receiver of the CygLP
    max, // Deadline
    leverageCalls, // Byte array holding the 1inch swap calls
    "0x",
  );

  const cygLPBalanceAfterL = await collateral.balanceOf(borrower._address);
  const albireoBalanceAfterL = await borrowable.totalBalance();
  const cygLPTotalBalanceAfterL = await collateral.totalBalance();

  const borrowBalanceAfterL = await borrowable.getBorrowBalance(borrower._address);
  const debtRatioAfterL = await collateral.getDebtRatio(borrower._address);

  console.log("Borrower`s borrow balance after leverage   | %s USDC", borrowBalanceAfterL / 1e6);
  console.log("Borrower`s CygLP balance after leverage    | %s CYG-LP", cygLPBalanceAfterL / 1e18);
  console.log("Borrower`s debt ratio after leverage       | % %s", debtRatioAfterL / 1e16);
  console.log("Borrowable`s totalBalance after leverage   | %s USDC", albireoBalanceAfterL / 1e6);
  console.log("Collateral`s totalBalance after leverage   | %s LPs", cygLPTotalBalanceAfterL / 1e18);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("REINVEST REWARDS");
  console.log("----------------------------------------------------------------------------------------------");

  const balanceBeforeReinvest = await collateral.totalBalance();

  // Create
  const rewardTokenContract = await usdc.attach(rewardToken);
  const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address);

  console.log("Collateral`s totalBalance before reinvest  | %s LPs", balanceBeforeReinvest / 1e18);
  console.log("Reinvestor`s totalBalance before reinvest  | %s JOE (or reward token)", reinvestorBalance / 1e18);

  // Increase 7 days
  await time.increase(60 * 60 * 24 * 110);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("60 Days pass...");
  console.log("----------------------------------------------------------------------------------------------");

  await collateral.connect(safeAddress2).reinvestRewards_y7b();

  const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address);
  const balanceAfterReinvest = await collateral.totalBalance();

  console.log("Collateral`s totalBalance after reinvest   | %s LPs", balanceAfterReinvest / 1e18);
  console.log("Reinvestor`s balance of rewardToken after  | %s JOE (or rewardToken)", reinvestorBalanceAfter / 1e18);
  console.log(
    "Borrower`s debt ratio after leverage       | % %s",
    (await collateral.getDebtRatio(borrower._address)) / 1e16,
  );

  console.log("----------------------------------------------------------------------------------------------");
  console.log("LIQUIDATE");
  console.log("----------------------------------------------------------------------------------------------");

  await borrowable.accrueInterest();

  console.log("New borrow balance: %s", (await borrowable.getBorrowBalance(borrower._address)) / 1e6);
  console.log("Balance of liquidator: %s USDC", (await usdc.balanceOf(lender._address)) / 1e6);
  console.log("Old Debt ratio: % %s", (await collateral.getDebtRatio(borrower._address)) / 1e16);
  console.log("CygLP total balance protocol: %s LPs", (await collateral.totalBalance()) / 1e18);
  console.log("CygLP total balance borrower: %s CygLP", (await collateral.balanceOf(borrower._address)) / 1e18);
  console.log("CygLP total Supply: %s CygLP", (await collateral.totalSupply()) / 1e18);
  console.log("Exchange Rate current: %s", (await collateral.exchangeRate()) / 1e18);

  // Update debt ratio and put borrower in liquidatable state
  await collateral.connect(owner).setDebtRatio(BigInt(0.85e18));
  console.log("Borrowers new Debt Ratio: %s", (await collateral.getDebtRatio(borrower._address)) / 1e16);

  // Checks that liquidate amount is never above borrowed balance in router (ie if user borrowed 20 usdc, router will repay 20 usdc, not 5000)
  await usdc.connect(lender).approve(router.address, max);

  await router.connect(lender).liquidate(borrowable.address, BigInt(10000e18), borrower._address, lender._address, max);

  const borrowerBalanceCollAfterLiq = await collateral.balanceOf(borrower._address);
  const lenderBalanceCollAfterLiq = await collateral.balanceOf(lender._address);
  const borrowBalanceAfterLiq = await borrowable.getBorrowBalance(borrower._address);

  console.log("Borrower balance of collateral             | %s CygLP", borrowerBalanceCollAfterLiq / 1e18);
  console.log("Liquidator balance of collateral           | %s CygLP", lenderBalanceCollAfterLiq / 1e18);
  console.log("Borrow Balance of borrower                 | %s USDC", borrowBalanceAfterLiq / 1e6);

  await collateral.connect(lender).redeem(lenderBalanceCollAfterLiq, lender._address, lender._address);
}

liquidate();
