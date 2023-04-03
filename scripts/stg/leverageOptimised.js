const path = require("path")
// Custom
const Make = require(path.resolve(__dirname, "../test/MakeInch.js"))
const Users = require(path.resolve(__dirname, "../test/Users.js"))
const Strategy = require(path.resolve(__dirname, "../test/Strategy.js"))
const leverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/OneInchLeverage.js"))
const deleverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/OneInchDeleverage.js"))

// eslint-disable-next-line
const hre = require("hardhat")

const { mine } = require("@nomicfoundation/hardhat-network-helpers")

// Enough
const max = BigInt(1000000e18)

async function leverage() {
    // Cygnus contracts and underlyings
    const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make()

    // Strateg}
    const [, , , pid] = await Strategy()

    // Users
    const [owner, , , lender, borrower] = await Users()

    // Initialize with pool ID of Sushi
    await collateral.connect(owner).chargeVoid(pid)

    const nativeToken = await router.nativeToken()

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
    await collateral.connect(borrower).deposit(BigInt(10e18), borrower._address)

    // Lender: Approve router in usdc and mint Cygusdc
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(300000e6), lender._address)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("BEFORE LEVERAGE")
    console.log("----------------------------------------------------------------------------------------------")

    const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address)
    const albireoBalanceBeforeL = await borrowable.totalBalance()
    const cygLPTotalBalanceBeforeL = await collateral.totalBalance()

    console.log("Borrower`s CygLP balance before leverage   | %s CygLP", cygLPBalanceBeforeL / 1e18)
    console.log("Borrowable`s totalBalance before leverage  | %s USDC", albireoBalanceBeforeL / 1e6)
    console.log("Collateral`s totalBalance before leverage  | %s LP TOKENS", cygLPTotalBalanceBeforeL / 1e18)
    console.log("Borrower's Debt Ratio before leverage: %s", (await collateral.getDebtRatio(borrower._address)) / 1e18)

    const xLeverage = BigInt(10)

    console.log("----------------------------------------------------------------------------------------------")
    console.log(`LEVERAGE ${xLeverage}`)
    console.log("----------------------------------------------------------------------------------------------")


    const accountLiquidity = await collateral.getAccountLiquidity(borrower._address)
    const liqIncentive = await collateral.liquidationIncentive()
    const maxLiquidity = (BigInt(accountLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentive)
    const leverageAmount = maxLiquidity * xLeverage
    console.log("USD Amount being leveraged: %s", leverageAmount / BigInt(1e6))

    // Byte array with data from 1inch 'swap' calls
    const leverageCalls = await leverageSwapData(
        chainId,
        lpToken,
        nativeToken,
        usdc.address,
        router.address,
        leverageAmount
    )

    // Leverage
    await router.connect(borrower).leverage(
        collateral.address, // Cygnus Collateral address
        borrowable.address, // Cygnus Borrowable address
        leverageAmount, // Amount of USDC to borrow from borrowable contract
        0, // Min amount of LP Tokens to receive (frontend using current LP Token price)
        borrower._address, // Receiver of the CygLP
        max, // Deadline
        leverageCalls, // Byte array holding the 1inch swap calls
        "0x" // permit data
    )

    const cygLPBalanceAfterL = await collateral.balanceOf(borrower._address)
    const albireoBalanceAfterL = await borrowable.totalBalance()
    const cygLPTotalBalanceAfterL = await collateral.totalBalance()

    const borrowBalanceAfterL = await borrowable.getBorrowBalance(borrower._address)
    const debtRatioAfterL = await collateral.getDebtRatio(borrower._address)

    console.log("Borrower`s borrow balance after leverage   | %s USDC", borrowBalanceAfterL / 1e6)
    console.log("Borrower`s CygLP balance after leverage    | %s CYG-LP", cygLPBalanceAfterL / 1e18)
    console.log("Borrower`s debt ratio after leverage       | % %s", debtRatioAfterL / 1e16)
    console.log("Borrowable`s totalBalance after leverage   | %s USDC", albireoBalanceAfterL / 1e6)
    console.log("Collateral`s totalBalance after leverage   | %s LPs", cygLPTotalBalanceAfterL / 1e18)

    
    console.log("----------------------------------------------------------------------------------------------")
    console.log("mine 20,000 blocks")
    await mine(20000)

    console.log("----------------------------------------------------------------------------------------------")
    console.log(`DELEVERAGE ${xLeverage}`)
    console.log("----------------------------------------------------------------------------------------------")

    const oneLPToken = await collateral.getLPTokenPrice()

    // Deleverage up to original deposited amount + estimate of swap fees (0.3% for each swap and we're doing 6 swaps max)
    await collateral.connect(borrower).approve(router.address, max)
    const owedDai = await borrowable.getBorrowBalance(borrower._address)
    const deleverageCygLPAmount = BigInt((owedDai / oneLPToken) * 1e18)
    const er = await collateral.exchangeRate()
    const deleverageLPAmount = (deleverageCygLPAmount * BigInt(er)) / BigInt(1e18)

    const deleverageCalls = await deleverageSwapData(
        chainId,
        lpToken,
        nativeToken,
        usdc.address,
        router.address,
        deleverageLPAmount,
        borrower
    )

    // Console.log
    console.log("Deleverage CygLP Amount ---------------->: %s", deleverageCygLPAmount / BigInt(1e18))

    await router
        .connect(borrower)
        .deleverage(collateral.address, borrowable.address, deleverageCygLPAmount, 0, max, deleverageCalls, "0x")

    const finalDenebBalance = await collateral.balanceOf(borrower._address)
    const finalAlbireoBalance = await borrowable.totalBalance()
    const outstandingBalance = await borrowable.getBorrowBalance(borrower._address)
    const totalBalanceD = await collateral.totalBalance()
    const usdcBalanceBorrower = await usdc.balanceOf(borrower._address)
    console.log("Borrower`s borrow balance after deleverage     | %s USDC", outstandingBalance / 1e6)
    console.log("Borrower`s CygLP balance after deleverage      | %s CygLP", finalDenebBalance / 1e18)
    console.log("Borrowable`s totalBalance after deleverage     | %s USDC", finalAlbireoBalance / 1e6)
    console.log("Collateral`s totalBalance after deleverage     | %s LP Tokens", totalBalanceD / 1e18)
    console.log("Borrower`s USDC balance after deleverage       | %s USDC", usdcBalanceBorrower / 1e6)
}

leverage()
