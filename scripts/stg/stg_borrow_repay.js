const path = require("path")
// Custom
const Make = require(path.resolve(__dirname, "../test/MakeInch.js"))
const Users = require(path.resolve(__dirname, "../test/Users.js"))
const Strategy = require(path.resolve(__dirname, "../test/Strategy.js"))

const hre = require("hardhat")

const { mine } = require("@nomicfoundation/hardhat-network-helpers")

// Enough
const max = BigInt(1000000e18)

async function leverage() {
    // Cygnus contracts and underlyings
    const [, , router, borrowable, collateral, usdc, lpToken] = await Make()

    // Strateg}
    const [, , , pid] = await Strategy()

    // Users
    const [owner, , , lender, borrower] = await Users()

    // Initialize with pool ID of Sushi
    await collateral.connect(owner).chargeVoid(pid)

    console.log("────────────────────────────────────────────────────────────────────────────────────────────")
    console.log("Borrower deposits 2 LPs, Lender deposits 3000 USD")
    console.log("────────────────────────────────────────────────────────────────────────────────────────────")
    console.log("Price of LP: $ %s", (await collateral.getLPTokenPrice()) / 1e6)
    console.log("────────────────────────────────────────────────────────────────────────────────────────────")

    console.log("Borrower`s LP balance before Cyg    | %s LP", (await lpToken.balanceOf(borrower._address)) / 1e18)
    console.log("Borrower`s USDC balance before Cyg  | %s USDC", (await usdc.balanceOf(borrower._address)) / 1e6)
    console.log("Lender`s USDC balance before Cyg    | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6)

    console.log("--------------> Deposit")

    // Borrower: Approve router in LP and mint CygLP
    await lpToken.connect(borrower).approve(collateral.address, max)
    await collateral.connect(borrower).deposit(BigInt(2e18), borrower._address)

    // Lender: Approve router in usdc and mint Cygusdc
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(3000e6), lender._address)

    const cygLPBalance = await collateral.balanceOf(borrower._address)
    const cygUSDBalance = await borrowable.balanceOf(lender._address)

    console.log("CYG-LP Balance of Borrower: %s", cygLPBalance / 1e18)
    console.log("CYG-USD Balance of Lender: %s", cygUSDBalance / 1e6)

    console.log("Collateral - Total Balance: %s", await collateral.totalBalance())
    console.log("Collateral - Total Supply: %s", await collateral.totalSupply())

    console.log("--------> Borrow: 165 USD")

    console.log("Borrower - USD Bal: %s", await usdc.balanceOf(borrower._address))
    console.log("Borrowable - Total Balance: %s", await borrowable.totalBalance())

    await router.connect(borrower).borrow(borrowable.address, "165000000", borrower._address, max, "0x")

    console.log("Borrower - USD Bal: %s", await usdc.balanceOf(borrower._address))
    console.log("Borrowable - Total Balance: %s", await borrowable.totalBalance())

    console.log("Mine 10000 blocks")
    await mine(10000)

    // Manually to preview
    await borrowable.exchangeRate()

    // Approve and repay usdc (the router does the calculation to Make sure repay amount is never above owed amount)
    await usdc.connect(borrower).approve(router.address, max)
    await router.connect(borrower).repay(borrowable.address, BigInt(400e6), borrower._address, max)

    console.log("Repaid!");

    console.log("Borrower - USD Bal: %s", await usdc.balanceOf(borrower._address))
    console.log("Borrowable - Total Balance: %s", await borrowable.totalBalance())
}

leverage()
