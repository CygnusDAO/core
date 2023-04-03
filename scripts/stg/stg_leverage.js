const path = require('path')
// Custom
const Make = require(path.resolve(__dirname, '../test/MakeInch.js'))
const Users = require(path.resolve(__dirname, '../test/Users.js'))
const Strategy = require(path.resolve(__dirname, '../test/Strategy.js'))
const leverageSwapData = require(path.resolve(__dirname, './aggregation-router-v5/OneInchLeverage.js'))

const hre = require('hardhat')

const { mine } = require('@nomicfoundation/hardhat-network-helpers')

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

    console.log('────────────────────────────────────────────────────────────────────────────────────────────')
    console.log('Borrower deposits 2 LPs, Lender deposits 3000 USD')
    console.log('────────────────────────────────────────────────────────────────────────────────────────────')
    console.log('Price of LP: $ %s', (await collateral.getLPTokenPrice()) / 1e6)
    console.log('────────────────────────────────────────────────────────────────────────────────────────────')

    console.log('Borrower`s LP balance before Cyg    | %s LP', (await lpToken.balanceOf(borrower._address)) / 1e18)
    console.log('Borrower`s USDC balance before Cyg  | %s USDC', (await usdc.balanceOf(borrower._address)) / 1e6)
    console.log('Lender`s USDC balance before Cyg    | %s USDC', (await usdc.balanceOf(lender._address)) / 1e6)

    console.log('--------------> Deposit')

    // Borrower: Approve router in LP and mint CygLP
    await lpToken.connect(borrower).approve(collateral.address, max)
    await collateral.connect(borrower).deposit(BigInt(10e18), borrower._address)

    // Lender: Approve router in usdc and mint Cygusdc
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(300000e6), lender._address)

    const cygLPBalance = await collateral.balanceOf(borrower._address)
    const cygUSDBalance = await borrowable.balanceOf(lender._address)

    console.log('CYG-LP Balance of Borrower: %s', cygLPBalance / 1e18)
    console.log('CYG-USD Balance of Lender: %s', cygUSDBalance / 1e6)

    console.log('Collateral - Total Balance: %s', await collateral.totalBalance())
    console.log('Collateral - Total Supply: %s', await collateral.totalSupply())

    console.log('Borrowable - Total Balance: %s', await borrowable.totalBalance())
    console.log('Borrowable - Total Supply: %s', await borrowable.totalSupply())

    const xLeverage = BigInt(10)

    console.log(`--------------> Leverage x${xLeverage}`)

    console.log("Borrower's Debt Ratio before leverage: %s", (await collateral.getDebtRatio(borrower._address)) / 1e18)

    console.log('Borrowable variables')
    console.log('Util: %s', await borrowable.utilizationRate())
    console.log('Borrow Rate: %s', (await borrowable.borrowRate()) * 31536000)
    console.log('Supply Rate: %s', await borrowable.supplyRate())
    console.log('Multiplier: %s', (await borrowable.multiplierPerSecond()) * 31536000)
    console.log('Jump Multiplier: %s', (await borrowable.jumpMultiplierPerSecond()) * 31536000)
    console.log('Base Rate: %s', (await borrowable.baseRatePerSecond()) * 31536000)
    console.log('Exchange Rate: %s', await borrowable.callStatic.exchangeRate())

    const accountLiquidity = await collateral.getAccountLiquidity(borrower._address)
    const liqIncentive = await collateral.liquidationIncentive()
    const maxLiquidity = (BigInt(accountLiquidity.liquidity) * BigInt(1e18)) / BigInt(liqIncentive)
    const leverageAmount = maxLiquidity * xLeverage

    // Byte array with data from 1inch 'swap' calls
    const leverageCalls = await leverageSwapData(chainId, lpToken, nativeToken, usdc.address, router.address, leverageAmount)

    console.log('USD Amount being leveraged: %s', leverageAmount / BigInt(1e6))

    // Leverage
    await router.connect(borrower).leverage(
        collateral.address, // Cygnus Collateral address
        borrowable.address, // Cygnus Borrowable address
        leverageAmount, // Amount of USDC to borrow from borrowable contract
        0, // Min amount of LP Tokens to receive (frontend using current LP Token price)
        borrower._address, // Receiver of the CygLP
        max, // Deadline
        leverageCalls, // Byte array holding the 1inch swap calls
        '0x' // permit data
    )

    console.log("Borrower's Debt Ratio after leverage: %s", (await collateral.getDebtRatio(borrower._address)) / 1e18)

    console.log('CYG-LP Balance of Borrower: %s', cygLPBalance / 1e18)
    console.log('Collateral - Total Balance: %s', await collateral.totalBalance())
    console.log('Collateral - Total Supply: %s', await collateral.totalSupply())

    console.log('Borrowable - Total Balance: %s', await borrowable.totalBalance())
    console.log('Borrowable - Total Supply: %s', await borrowable.totalSupply())
    console.log('Exchange Rate: %s', await borrowable.callStatic.exchangeRate())

    console.log(`--------------> Reinvest Borrowable`)
    await borrowable.exchangeRate();

    console.log('mine 10,000 blocks')
    await mine(10000)
    console.log("Borrower's Debt Ratio after mining 10,000 blocks: %s", (await collateral.getDebtRatio(borrower._address)) / 1e18)

    await borrowable.exchangeRate();
    console.log('Borrowable - Util: %s', await borrowable.utilizationRate())
    console.log('Borrowable - Borrow Rate: %s', (await borrowable.borrowRate()) * 31536000)
    console.log('Borrowable - Supply Rate: %s', await borrowable.supplyRate())
    console.log('Borrowable - Total Balance: %s', await borrowable.totalBalance())
    console.log('Borrowable - Total Supply: %s', await borrowable.totalSupply())

    console.log('Reinvesting..')
    console.log('Pending STG Rewards: %s', await borrowable.callStatic.getRewards() / 1e18)

    // Reinvest
    await borrowable.connect(owner).reinvestRewards_y7b()


    await borrowable.exchangeRate();
    // Util and borrow rate should decrease
    console.log("Borrower's Debt Ratio after reinvest: %s", (await collateral.getDebtRatio(borrower._address)) / 1e18)

    console.log('Borrowable - Util: %s', await borrowable.utilizationRate())
    console.log('Borrowable - Borrow Rate: %s', (await borrowable.borrowRate()) * 31536000)
    console.log('Borrowable - Supply Rate: %s', await borrowable.supplyRate())
    console.log('Borrowable - Total Balance: %s', await borrowable.totalBalance())
    console.log('Borrowable - Total Supply: %s', await borrowable.totalSupply())
}

leverage()
