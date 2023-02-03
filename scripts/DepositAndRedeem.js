// eslint-disable-next-line
const hre = require("hardhat");
const ethers = hre.ethers;

// Custom
const Make = require("../test/MakeInch.js");
const Users = require("../test/Users.js");
const Strategy = require("../test/Strategy.js");

// eslint-disable-next-line
const { time } = require("@openzeppelin/test-helpers");

// Ethers
const max = ethers.constants.MaxUint256;

async function deploy() {
  // Cygnus contracts and underlyings
  const [, , router, borrowable, collateral, usdc, lpToken] = await Make();

  // Strateg}
  const [voidRouter, masterChef, rewardToken, pid] = await Strategy();

  // Users
  const [owner, , , lender, borrower] = await Users();

  // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

  // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
  await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, pid);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("Price of LP Token                    | %s USDC", (await collateral.getLPTokenPrice()) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");
  console.log("INITIAL BALANCES OF LENDER/BORROWER");
  console.log("----------------------------------------------------------------------------------------------");
  console.log("Borrower`s LP balance before Cyg     | %s LPs", (await lpToken.balanceOf(borrower._address)) / 1e18);
  console.log("Borrower`s USDC balance before Cyg    | %s USDC", (await usdc.balanceOf(borrower._address)) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");
  console.log("Lender`s LP balance before Cyg       | %s LPs", (await lpToken.balanceOf(lender._address)) / 1e18);
  console.log("Lender`s USDC balance before Cyg      | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");

  /*******************************************************************************************************
   
    
                            INTERACTIONS
    
     
  ******************************************************************************************************/

  console.log("------------------------------------------------------------------------------");
  console.log("Borrower deposits 100 LPs, Lender deposits 4000 USDC");
  console.log("------------------------------------------------------------------------------");

  console.log("Total Balance of borrowable before   | %s USDC", (await borrowable.totalBalance()) / 1e6);
  console.log("Total Balance of collateral before   | %s USDC", (await borrowable.totalBalance()) / 1e18);

  // Borrower: Approve router in LP and mint CygLP
  await lpToken.connect(borrower).approve(collateral.address, max);
  await collateral.connect(borrower).deposit(BigInt(2e18), borrower._address);

  // Lender: Approve router in usdc and mint Cygusdc
  await usdc.connect(lender).approve(borrowable.address, max);
  await borrowable.connect(lender).deposit(BigInt(3000e6), lender._address);

  const usdcBalanceBorrower = await usdc.balanceOf(borrower._address);
  const cygLPBalanceBorrower = await collateral.balanceOf(borrower._address);

  console.log("Total Balance of borrowable after    | %s USDC", (await borrowable.totalBalance()) / 1e6);
  console.log("Total Balance of collateral after    | %s LPs", (await collateral.totalBalance()) / 1e18);
  console.log("CygUSDC balanceOf Lender             | %s CygUSDC", usdcBalanceBorrower / 1e6);
  console.log("CygLP balanceOf Borrower             | %s CygLP", cygLPBalanceBorrower / 1e18);

  // Borrow
  await router.connect(borrower).borrow(borrowable.address, BigInt(50e6), borrower._address, max, "0x");

  console.log("Borrower`s USDC balance after borrow  | %s USDC", (await usdc.balanceOf(borrower._address)) / 1e6);
  console.log("Lenders`s USDC balance after deposit  | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6);

  console.log("------------------------------------------------------------------------------");
  console.log("Reinvest rewards");
  console.log("------------------------------------------------------------------------------");

  console.log("Total Balance of collateral before   | %s LPs", (await collateral.totalBalance()) / 1e18);
  console.log("Exchange Rate of CygLP to collateral | %s", (await collateral.exchangeRate()) / 1e18);

  console.log("------------------------------------------------------------------------------");
  console.log("7 days.... ");
  console.log("------------------------------------------------------------------------------");

  await time.increase(60 * 60 * 24 * 7);

  await collateral.reinvestRewards_y7b();

  console.log("Total Balance of collateral after    | %s LPs", (await collateral.totalBalance()) / 1e18);
  console.log("Exchange Rate of CygLP to collateral | %s", (await collateral.exchangeRate()) / 1e18);

  console.log("------------------------------------------------------------------------------");
  console.log("Repay loan and redeem");
  console.log("------------------------------------------------------------------------------");

  // To repay just send borrower some usdc
  // Impersonate a random usdc holder
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: ["0xc882b111a75c0c657fc507c04fbfcd2cc984f071"],
  });

  const lender2 = await ethers.provider.getSigner("0xc882b111a75c0c657fc507c04fbfcd2cc984f071");
  await usdc.connect(lender2).transfer(borrower._address, BigInt(400e6));

  await borrowable.accrueInterest();
  const borrowBalance = await borrowable.getBorrowBalance(borrower._address);
  console.log("Borrower`s amount to repay           | %s USDC", borrowBalance / 1e6);

  // Approve and repay usdc (the router does the calculation to Make sure repay amount is never above owed amount)
  await usdc.connect(borrower).approve(router.address, max);
  await router.connect(borrower).repay(borrowable.address, BigInt(400e6), borrower._address, max);

  // Redeem borrower
  const balanceBorrower = await collateral.balanceOf(borrower._address);
  await collateral.connect(borrower).redeem(balanceBorrower, borrower._address, borrower._address);
  // await collateral.connect(borrower).approve(router.address, max);
  // await router.connect(borrower).redeem(collateral.address, balanceBorrower, borrower._address, max, '0x');

  // Redeem lender
  const balanceLender = await borrowable.balanceOf(lender._address);
  await borrowable.connect(lender).redeem(balanceLender, lender._address, lender._address);

  // Should be a bit higher due to reinvest rewards
  console.log("Borrower`s LP balance after redeem   | %s LPs", (await lpToken.balanceOf(borrower._address)) / 1e18);
  console.log("Lender`s USDC balance after redeem   | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6);
  console.log("------------------------------------------------------------------------------");
}

deploy();
/*
module.exports = {
    deploy,
};
*/
