// eslint-disable-next-line
const hre = require("hardhat")
const ethers = hre.ethers

const path = require("path")

// Custom
const Make = require(path.resolve(__dirname, "../test/MakeInch.js"))
const Users = require(path.resolve(__dirname, "../test/Users.js"))
const Strategy = require(path.resolve(__dirname, "../test/Strategy.js"))

// eslint-disable-next-line
const { time } = require("@openzeppelin/test-helpers")

// Ethers
const max = ethers.constants.MaxUint256

async function borrow() {
    // Cygnus contracts and underlyings
    const [, , router, borrowable, collateral, usdc, lpToken] = await Make()

    // Strategy
    const [, , , pid] = await Strategy()

    // Users
    const [owner, , , lender, borrower] = await Users()

    // INITIALIZE VOID
    await collateral.connect(owner).chargeVoid(pid)

    /*****************************************************************************************************
    
                            INTERACTIONS - LIQUIDATE
     
  ******************************************************************************************************/

    // Price of 1 LP Token of joe/avax in usdc
    const oneLPToken = await collateral.getLPTokenPrice()

    console.log("Price of LP Token                          | %s USDC", (await oneLPToken) / 1e6)
    console.log("----------------------------------------------------------------------------------------------")
    console.log("Borrower deposits 100 LPs, Lender deposits 10,000 USDC")
    console.log("----------------------------------------------------------------------------------------------")

    console.log("Borrower`s LP Balance before Cygnus        | %s", (await lpToken.balanceOf(borrower._address)) / 1e18)
    console.log("Lender`s USDC balance before Cygnus         | %s", (await usdc.balanceOf(lender._address)) / 1e6)

    // Borrower: Approve collateral in LP Token
    await lpToken.connect(borrower).approve(collateral.address, max)
    await collateral.connect(borrower).deposit(BigInt(1e18), borrower._address)

    // Lender: Approve borrowable in USDC
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(100000e6), lender._address)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("BEFORE BORROW")
    console.log("----------------------------------------------------------------------------------------------")

    const usdcBeforeBorrow = await usdc.balanceOf(borrower._address)
    console.log("Borrowers USDC Before borrow: %s", usdcBeforeBorrow / 1e6)

    // Max Borrow = accountLiquidity / liquidationIncentive
    const accLiquidity = await collateral.getAccountLiquidity(borrower._address)
    const liqIncentive = await collateral.liquidationIncentive()
    const maxBorrow = (BigInt(accLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentive)

    await router.connect(borrower).borrow(borrowable.address, maxBorrow, borrower._address, max, "0x")

    const usdcAfterBorrow = await usdc.balanceOf(borrower._address)
    console.log("Borrowers USDC After borrow: %s", usdcAfterBorrow / 1e6)
}

borrow()
