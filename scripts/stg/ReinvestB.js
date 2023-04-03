// eslint-disable-next-line
const hre = require("hardhat");
const ethers = hre.ethers;
const path = require("path");

// Custom
const Make = require(path.resolve(__dirname, "../../test/MakeInch.js"));
const Users = require(path.resolve(__dirname, "../../test/Users.js"));
const Strategy = require(path.resolve(__dirname, "../../test/Strategy.js"));

const { mine } = require('@nomicfoundation/hardhat-network-helpers')

// Ethers
const max = ethers.constants.MaxUint256;

async function deploy() {
  // Cygnus contracts and underlyings
  const [, , , borrowable, collateral, usdc] = await Make();

  // Strateg}
  const [, , , pid] = await Strategy();

  // Users
  const [owner, , , lender, borrower] = await Users();

  // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

  // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
  await collateral.connect(owner).chargeVoid(pid);

  console.log("----------------------------------------------------------------------------------------------");
  console.log("Price of LP Token                    | %s USDC", (await collateral.getLPTokenPrice()) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");
  console.log("INITIAL BALANCES OF LENDER");
  console.log("----------------------------------------------------------------------------------------------");
  console.log("Borrower`s USDC balance before Cyg    | %s USDC", (await usdc.balanceOf(borrower._address)) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");
  console.log("Lender`s USDC balance before Cyg      | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6);
  console.log("----------------------------------------------------------------------------------------------");

  /*******************************************************************************************************
   
    
                            INTERACTIONS
    
     
  ******************************************************************************************************/

  console.log("Exchange Rate: %s", await borrowable.callStatic.exchangeRate());
  console.log("Exchange Rate Stored: %s", await borrowable.callStatic.exchangeRateStored());

  console.log("Lender deposits");
  // Lender: Approve router in usdc and mint Cygusdc
  await usdc.connect(lender).approve(borrowable.address, max);
  await borrowable.connect(lender).deposit(BigInt(3000e6), lender._address);

  console.log("---Pool After Deposit----");
  console.log("Total Balance: %s", await borrowable.totalBalance() / 1e6);
  console.log("Total Supply: %s", await borrowable.totalSupply() / 1e6);
  console.log("Exchange Rate: %s", await borrowable.callStatic.exchangeRate());
  console.log("Exchange Rate Stored: %s", await borrowable.exchangeRateStored());

  console.log(". Call exchange rate to test...");
  await borrowable.exchangeRate();

  console.log("Total Balance: %s", await borrowable.totalBalance() / 1e6);
  console.log("Total Supply: %s", await borrowable.totalSupply() / 1e6);
  console.log("Exchange Rate: %s", await borrowable.callStatic.exchangeRate());
  console.log("Exchange Rate Stored: %s", await borrowable.exchangeRateStored());

  console.log("---Reinvesting Pool-------------");

  console.log("Mine 100,000 blocks");
  await mine(100000);
  await borrowable.connect(lender).reinvestRewards_y7b();

  console.log("---Pool After Reinvest----");
  console.log("Total Balance: %s", await borrowable.totalBalance() / 1e6);
  console.log("Total Supply: %s", await borrowable.totalSupply() / 1e6);
  console.log("Exchange Rate: %s", await borrowable.callStatic.exchangeRate());
  console.log("Exchange Rate Stored: %s", await borrowable.exchangeRateStored());

  console.log(". Call exchange rate to test...");
  await borrowable.exchangeRate();

  console.log("Total Balance: %s", await borrowable.totalBalance() / 1e6);
  console.log("Total Supply: %s", await borrowable.totalSupply() / 1e6);
  console.log("Exchange Rate: %s", await borrowable.callStatic.exchangeRate());
  console.log("Exchange Rate Stored: %s", await borrowable.exchangeRateStored());

  console.log("---Reinvesting Pool-------------");

  console.log("Mine 160,000 blocks");
  await mine(150000);
  await borrowable.connect(lender).reinvestRewards_y7b();
}

deploy();
