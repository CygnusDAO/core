const hre = require("hardhat")
const ethers = hre.ethers
const path = require("path")

// Custom
const Make = require(path.resolve(__dirname, "../test/MakeInch.js"))
const Users = require(path.resolve(__dirname, "../test/Users.js"))
const Strategy = require(path.resolve(__dirname, "../test/Strategy.js"))
const leverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/OneInchLeverage.js"))
const deleverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/OneInchDeleverage.js"))
const borrowableSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/OneInchReinvest.js"))

// Helpers
const { mine } = require("@nomicfoundation/hardhat-network-helpers")

// Max Uint256
const max = ethers.constants.MaxUint256

async function deploy() {
    // Cygnus contracts and underlyings
    const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make()

    // Strategy
    const [, , rewardToken, pid, rewardTokenB] = await Strategy()

    // Users
    const [owner, , safeAddress2, lender, borrower] = await Users()

    const nativeToken = await router.nativeToken()

    // INITIALIZE VOID
    await collateral.connect(owner).chargeVoid(pid)
    await borrowable.connect(owner).chargeVoid(0)

    /********************************************************************************************************
   
    
     CYGNUS INTERACTIONS - Connect to the router and test mint functions for borrow and collateral contracts.
    
     
     ********************************************************************************************************/

    // Price of 1 LP Token of joe/avax in usdc
    const oneLPToken = await collateral.getLPTokenPrice()

    // Leverage
    const xLeverage = BigInt(10)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("PRICE OF 1 LP TOKEN                            | %s USDC", oneLPToken / 1e6)
    console.log("----------------------------------------------------------------------------------------------")

    const lpTokenBalanceBeforeDeposit = await lpToken.balanceOf(borrower._address)
    const usdcBalanceBeforeDeposit = await usdc.balanceOf(lender._address)

    console.log("Borrower`s LP balance before deposit           | %s LP Tokens", lpTokenBalanceBeforeDeposit / 1e18)
    console.log("Lender`s USDC balance before deposit           | %s USDC", usdcBalanceBeforeDeposit / 1e6)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("Borrower deposits 100 LPs in CygnusCollateral, Lender deposits 30,000 USDC in CygnusBorrow")
    console.log("----------------------------------------------------------------------------------------------")

    // Borrower: Approve collateral in LP Token
    await lpToken.connect(borrower).approve(collateral.address, max)
    await collateral.connect(borrower).deposit(BigInt(10e18), borrower._address)

    // Lender: Approve borrowable in USDC
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(250000e6), lender._address)

    console.log("BEFORE LEVERAGE")
    console.log("----------------------------------------------------------------------------------------------")

    const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address)
    const albireoBalanceBeforeL = await borrowable.totalBalance()
    const cygLPTotalBalanceBeforeL = await collateral.totalBalance()

    console.log("Borrower`s CygLP balance before leverage       | %s CygLP", cygLPBalanceBeforeL / 1e18)
    console.log("Borrowable`s totalBalance before leverage      | %s USDC", albireoBalanceBeforeL / 1e6)
    console.log("Collateral`s total LP Tokens before leverage   | %s LP Tokens", cygLPTotalBalanceBeforeL / 1e18)

    console.log("----------------------------------------------------------------------------------------------")
    console.log(`${Number(xLeverage)}x LEVERAGE`)
    console.log("----------------------------------------------------------------------------------------------")

    // Borrower: Approve borrow
    // await borrowable.connect(borrower).borrowApprove(router.address, max);
    const accountLiquidity = await collateral.getAccountLiquidity(borrower._address)
    const liqIncentive = await collateral.liquidationIncentive()
    const maxLiquidity = (BigInt(accountLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentive)
    const leverageAmount = maxLiquidity * xLeverage

    // Console.log
    console.log("Leverage USDC Amount ---------------->: %s", leverageAmount)

    // Borrower
    // await usdc.connect(borrower).approve(router.address, max);

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
        "0x"
    )

    // Borrower`s borrow balance
    const borrowBalanceAfter = await borrowable.getBorrowBalance(borrower._address)
    // CygLP balance of borrower
    const denebBalanceAfterL = await collateral.balanceOf(borrower._address)
    // CygUSD totalBalance
    const albireoBalanceAfterL = await borrowable.totalBalance()
    // CygLP totalBalance
    const totalBalanceC = await collateral.totalBalance()

    console.log(`Borrowers USDC debt after ${Number(xLeverage)} leverage        | %s USDC`, borrowBalanceAfter / 1e6)
    console.log(
        `Borrowers debt ratio after ${Number(xLeverage)} leverage       | % %s`,
        (await collateral.getDebtRatio(borrower._address)) / 1e16
    )

    console.log(`Borrowers CygLP balance after ${Number(xLeverage)} leverage    | %s CygLP`, denebBalanceAfterL / 1e18)
    console.log(`Borrowables USDC balance after ${Number(xLeverage)} leverage   | %s USDC`, albireoBalanceAfterL / 1e6)
    console.log(`Collaterals totalBalance after ${Number(xLeverage)} leverage   | %s LP Tokens`, totalBalanceC / 1e18)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("REINVEST REWARDS - COLLATERAL")
    console.log("----------------------------------------------------------------------------------------------")

    // Create
    const rewardTokenContract = await usdc.attach(rewardToken)
    const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address)
    const balanceBeforeReinvest = await collateral.totalBalance()

    console.log(
        "Borrower`s debt ratio before reinvesting       | % %s",
        (await collateral.getDebtRatio(borrower._address)) / 1e16
    )
    console.log("Collateral`s totalBalance before reinvesting   | %s LP Tokens", balanceBeforeReinvest / 1e18)
    console.log("Reinvestor`s balanceOf token before reinvest   | %s JOE (or other)", reinvestorBalance / 1e18)

    await mine(100000)
    console.log("Mined 100000 blocks")

    await collateral.connect(safeAddress2).reinvestRewards_y7b()

    const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address)
    const balanceAfterReinvest = await collateral.totalBalance()
    const debtRatioAfterReinvest = await collateral.getDebtRatio(borrower._address)

    console.log("Borrower`s debt ratio after reinvesting        | % %s", debtRatioAfterReinvest / 1e16)
    console.log("Collateral`s totalBalance after reinvest       | %s LP Tokens", balanceAfterReinvest / 1e18)
    console.log("Reinvestor`s balanceOf token after reinvest    | %s JOE (or other)", reinvestorBalanceAfter / 1e18)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("REINVEST REWARDS - BORROWABLE")
    console.log("----------------------------------------------------------------------------------------------")

    // Create
    const rewardB = await ethers.getContractAt("CygnusCollateral", rewardTokenB)
    const utilBefore = (await borrowable.utilizationRate()) / 1e16
    const balanceBeforeReinvestB = await borrowable.totalBalance()
    const reinvestorBalanceB = await rewardB.balanceOf(safeAddress2.address)
    const stgAmount = (await borrowable.callStatic.getRewards()) * 0.97

    console.log("Borrowable's Utilization Rate before Reinvesting       | % %s", utilBefore)
    console.log("Borrowable`s totalBalance before reinvesting           | %s USD", balanceBeforeReinvestB / 1e6)
    console.log("Reinvestor`s balanceOf token before reinvest           | %s STG", reinvestorBalanceB / 1e18)
    console.log("STG Amount to reinvest:                                | %s STG", stgAmount)

    // Remove DAO and reinvestor reward, the final amount gets updated on the swap anyways
    const swapData = await borrowableSwapData(chainId, rewardTokenB, usdc.address, stgAmount * 0.97, borrowable.address)

    await borrowable.connect(safeAddress2).reinvestRewards_y7b(swapData)

    const utilAfter = (await borrowable.utilizationRate()) / 1e16
    const balanceAfterReinvestB = await borrowable.totalBalance()
    const reinvestorBalanceBAfter = await rewardB.balanceOf(safeAddress2.address)

    console.log("Borrowable's Utilization Rate after Reinvesting        | % %s", utilAfter)
    console.log("Borrowable`s totalBalance after reinvesting            | %s USD", balanceAfterReinvestB / 1e6)
    console.log(
        "Reinvestor`s balanceOf token after reinvest            | %s STG (or other)",
        reinvestorBalanceBAfter / 1e18
    )

    console.log("----------------------------------------------------------------------------------------------")
    console.log("AFTER DELEVERAGE")
    console.log("----------------------------------------------------------------------------------------------")

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
    console.log("Deleverage CygLP Amount ---------------->: %s", deleverageCygLPAmount)

    await router
        .connect(borrower)
        .deleverage(collateral.address, borrowable.address, deleverageCygLPAmount, 0, max, deleverageCalls, "0x", {
            gasLimit: 12000000,
        })

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

    console.log("----------------------------------------------------------------------------------------------")
    console.log("REDEEM AND LEAVE CYGNUS FOREVER")
    console.log("----------------------------------------------------------------------------------------------")

    // Redeem CygLP
    const balanceCygLPBorrower = await collateral.balanceOf(borrower._address)
    await collateral.connect(borrower).redeem(balanceCygLPBorrower, borrower._address, borrower._address)

    // Redeem CygUSDC
    const balanceCygDaiLender = await borrowable.balanceOf(lender._address)
    await borrowable.connect(lender).redeem(balanceCygDaiLender, lender._address, lender._address)

    const finalLPBalance = await lpToken.balanceOf(borrower._address)
    const finalUsdcBalance = await usdc.balanceOf(lender._address)
    const usdcBalanceAfter = await usdc.balanceOf(borrower._address)

    // If doing a full deleverage the router converts eveyrthing to USDC, sends back owed amount to borrowable and
    // transfers remaining USDC to borrower. It is best to not deleverage 100% of the position, instead calc balance
    console.log("Borrower`s USDC balance after de-leverage      | %s USDC", usdcBalanceAfter / 1e6)
    console.log("Lender`s USDC balance after redeem and exit    | %s USDC", finalUsdcBalance / 1e6)
    console.log("Borrower`s LP balance after redeem and exit    | %s", finalLPBalance / 1e18)

    // Collateral balance and supply
    console.log("totalBalance of collateral after full redeem   | %s LPs", (await collateral.totalBalance()) / 1e18)
    console.log("totalSupply of collateral after full redeem    | %s CygLP", (await collateral.totalSupply()) / 1e18)

    // Borrowables balance and supply
    // Only USDC left and CygUSD are dao reserves
    const totalSupply = (await borrowable.totalSupply()) / 1e6
    console.log("totalBalance of borrowable after full redeem   | %s USDC ", (await borrowable.totalBalance()) / 1e6)
    console.log("totalSupply of borrowable after full redeem    | %s CygUSD", totalSupply)
}

deploy()
/*
module.exports = {
    deploy,
};
*/
