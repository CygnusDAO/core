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
    await collateral.connect(borrower).deposit(BigInt(2e18), borrower._address)

    // Lender: Approve router in usdc and mint Cygusdc
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(3000e6), lender._address)

    const cygLPBalance = await collateral.balanceOf(borrower._address)
    const cygUSDBalance = await borrowable.balanceOf(lender._address)

    console.log('CYG-LP Balance of Borrower: %s', cygLPBalance / 1e18)
    console.log('CYG-USD Balance of Lender: %s', cygUSDBalance / 1e6)

    console.log('Collateral - Total Balance: %s', await collateral.totalBalance())
    console.log('Collateral - Total Supply: %s', await collateral.totalSupply())

    console.log('Borrowable - Total Balance: %s', await borrowable.totalBalance())
    console.log('Borrowable - Total Supply: %s', await borrowable.totalSupply())

    console.log('10000 blocks pass, rienvest rewards')
    await mine(10000)

    console.log('Total Balance before: %s', await borrowable.totalBalance())
    console.log('Total Supply before: %s', await borrowable.totalSupply())

    console.log('pending rewards: %s', await borrowable.callStatic.getRewards())

    // Reinvest
    await borrowable.connect(owner).reinvestRewards_y7b()

    console.log('Total Balance before: %s', await borrowable.totalBalance())
    console.log('Total Supply before: %s', await borrowable.totalSupply())
}

leverage()
