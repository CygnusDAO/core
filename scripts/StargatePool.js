// eslint-disable-next-line
const hre = require("hardhat")
const ethers = hre.ethers
const path = require("path")

// Custom
const Make = require("./test/MakeInch.js")
const Users = require("./test/Users.js")
const Strategy = require("./test/Strategy.js")

const borrowableSwapData = require(path.resolve(__dirname, "./scripts/aggregation-router-v5/OneInchReinvest.js"))
const { mine } = require("@nomicfoundation/hardhat-network-helpers")

// Ethers
const max = ethers.constants.MaxUint256

const makeUser = async (address) => {
    // Lender: Random DAI Whale //
    await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    })

    const user = await ethers.provider.getSigner(address)

    return user
}

async function stargatePool() {
    // Cygnus contracts and underlyings
    const [, , , borrowable, collateral, usdc, , chainId] = await Make()

    // Strateg}
    const [, , , pid, rewardTokenB] = await Strategy()

    // Users
    const [owner, , , lender] = await Users()

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════
    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee

    await collateral.connect(owner).chargeVoid(pid)
    await borrowable.connect(owner).chargeVoid(0)

    const lender2 = "0x5f153a7d31b315167fe41da83acba1ca7f86e91d"
    const lender3 = "0x9b64203878f24eb0cdf55c8c6fa7d08ba0cf77e5"
    const lender4 = "0xb19fe973edd97e971534f6c46d96f2b109d3f1de"

    /*******************************************************************************************************
   
    
                            INTERACTIONS
    
     
  ******************************************************************************************************/

    console.log("----------------------------------------------------------------------------------------------")
    console.log("Lender 1 USDC balance before Cyg     | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6)
    console.log("Lender 2 USDC balance before Cyg     | %s USDC", (await usdc.balanceOf(lender2)) / 1e6)
    console.log("Lender 3 USDC balance before Cyg     | %s USDC", (await usdc.balanceOf(lender3)) / 1e6)
    console.log("----------------------------------------------------------------------------------------------")


    // Borrower: Approve router in LP and mint CygLP
    //  await lpToken.connect(borrower).approve(collateral.address, max);
    //  await collateral.connect(borrower).deposit(BigInt(2e18), borrower._address);
    // Lender: Approve router in usdc and mint Cygusdc
    await usdc.connect(lender).approve(borrowable.address, max)
    await borrowable.connect(lender).deposit(BigInt(3000e6), lender._address)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("0. DEPOSIT - 3000 USDC")
    console.log("----------------------------------------------------------------------------------------------")

    console.log("..............")
    console.log("deposited!")
    console.log("..............")

    console.log("CygUSD balance of Lender             | %s CygUSD", (await borrowable.balanceOf(lender._address)) / 1e6)
    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log("////////////////////////////////")
    console.log("Manually call exchange rate");
    await borrowable.connect(lender).exchangeRate();
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")

    console.log("Reinvesting...")
    await mine(100000)
    const stgAmount3 = (await borrowable.callStatic.getRewards()) * 0.97
    const swapData3 = await borrowableSwapData(
        chainId,
        rewardTokenB,
        usdc.address,
        stgAmount3 * 0.97,
        borrowable.address
    )

    await borrowable.connect(lender).reinvestRewards_y7b(swapData3)

    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")
    console.log("Manually call exchange rate");
    await borrowable.connect(lender).exchangeRate();
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")

    console.log("----------------------------------------------------------------------------------------------")
    console.log("1. THIRD LENDER DEPOSITS 441284 USDC")
    console.log("----------------------------------------------------------------------------------------------")

    const lender_three = await makeUser(lender3)
    await usdc.connect(lender_three).approve(borrowable.address, BigInt(10000000000e6))
    await borrowable.connect(lender_three).deposit(BigInt(91284e6), lender_three._address)

    console.log("deposited!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("USDC Balance second_lender after     | %s USDC", (await usdc.balanceOf(lender_three._address)) / 1e6)
    console.log( "CygUSD balance third_lender after   | %s CygUSD", (await borrowable.balanceOf(lender_three._address)) / 1e6
    )

    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")
    console.log("Manually call exchange rate");
    await borrowable.connect(lender).exchangeRate();
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")

    console.log("----------------------------------------------------------------------------------------------")
    console.log("1. FIRST LENDER REDEEMS ALL")
    console.log("----------------------------------------------------------------------------------------------")

    const lenderBal = await borrowable.balanceOf(lender._address)
    await borrowable.connect(lender).redeem(lenderBal, lender._address, lender._address)

    console.log("redeemed!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")
    console.log("Manually call exchange rate");
    await borrowable.connect(lender).exchangeRate();
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")

    console.log("----------------------------------------------------------------------------------------------")
    console.log("2. DEPOSIT - 2540 USDC")
    console.log("----------------------------------------------------------------------------------------------")

    await borrowable.connect(lender).deposit(BigInt(2540e6), lender._address)

    console.log("deposited!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log("Reinvesting...")
    await mine(100000)
    const stgAmount = (await borrowable.callStatic.getRewards()) * 0.97
    const swapData = await borrowableSwapData(chainId, rewardTokenB, usdc.address, stgAmount * 0.97, borrowable.address)
    await borrowable.connect(lender).reinvestRewards_y7b(swapData)

    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")
    console.log("Manually call exchange rate");
    await borrowable.connect(lender).exchangeRate();
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")

    console.log("----------------------------------------------------------------------------------------------")
    console.log("3. DEPOSIT - SECOND LENDER - 6665 USDC")
    console.log("----------------------------------------------------------------------------------------------")

    const lender_two = await makeUser(lender2)
    console.log("New user!")
    console.log(".......")

    console.log("USDC Balance second_lender before    | %s USDC", (await usdc.balanceOf(lender_two._address)) / 1e6)
    console.log(
        "CygUSD balance second_lender before  | %s CygUSD",
        (await borrowable.balanceOf(lender_two._address)) / 1e6
    )
    console.log(".......")

    await usdc.connect(lender_two).approve(borrowable.address, BigInt(10000000000e6))
    await borrowable.connect(lender_two).deposit(BigInt(6665e6), lender_two._address)

    console.log("deposited!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("USDC Balance second_lender after     | %s USDC", (await usdc.balanceOf(lender_two._address)) / 1e6)
    console.log(
        "CygUSD balance second_lender after   | %s CygUSD",
        (await borrowable.balanceOf(lender_two._address)) / 1e6
    )

    console.log("Reinvesting...")
    await mine(100000)
    const stgAmount2 = (await borrowable.callStatic.getRewards()) * 0.97
    const swapData2 = await borrowableSwapData(
        chainId,
        rewardTokenB,
        usdc.address,
        stgAmount2 * 0.97,
        borrowable.address
    )
    await borrowable.connect(lender).reinvestRewards_y7b(swapData2)
    console.log("Reinvest success")

    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")
    console.log("Manually call exchange rate");
    await borrowable.connect(lender).exchangeRate();
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("////////////////////////////////")
    console.log("----------------------------------------------------------------------------------------------")
    console.log("5. REDEEM - SECOND LENDER - ALL USDC")
    console.log("----------------------------------------------------------------------------------------------")

    let balance_two = await borrowable.balanceOf(lender_two._address)
    await borrowable.connect(lender_two).redeem(balance_two, lender_two._address, lender_two._address)

    console.log("redeemed all!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log("USDC Balance second_lender           | %s USDC", (await usdc.balanceOf(lender_two._address)) / 1e6)
    console.log(
        "CygUSD balance second_lender after   | %s CygUSD",
        (await borrowable.balanceOf(lender_two._address)) / 1e6
    )

    console.log("----------------------------------------------------------------------------------------------")
    console.log("6. REDEEM - THIRD LENDER - ALL USDC")
    console.log("----------------------------------------------------------------------------------------------")

    let balance_three = await borrowable.balanceOf(lender_three._address)
    await borrowable.connect(lender_three).redeem(balance_three, lender_three._address, lender_three._address)

    console.log("redeemed all!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log(
        "CygUSD balance third_lender after   | %s CygUSD",
        (await borrowable.balanceOf(lender_three._address)) / 1e6
    )

    console.log("----------------------------------------------------------------------------------------------")
    console.log("7. REDEEM - FIRST LENDER - ALL")
    console.log("----------------------------------------------------------------------------------------------")

    let balance_first = await borrowable.balanceOf(lender._address)
    console.log("USDC Balance first lender            | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6)
    console.log("CygUSD balance first_lender after    | %s CygUSD", (await borrowable.balanceOf(lender._address)) / 1e6)

    await borrowable.connect(lender).redeem(balance_first, lender._address, lender._address)

    console.log("redeemed all!")
    console.log(".......")

    console.log("Total Supply:                        | %s", (await borrowable.totalSupply()) / 1e6)
    console.log("Total Balance:                       | %s", (await borrowable.totalBalance()) / 1e6)
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())
    console.log("USDC Balance first lender after      | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6)

    console.log("----------------------------------------------------------------------------------------------")
    console.log("Lender 1 USDC balance after Cyg     | %s USDC", (await usdc.balanceOf(lender._address)) / 1e6)
    console.log("Lender 2 USDC balance after Cyg     | %s USDC", (await usdc.balanceOf(lender2)) / 1e6)
    console.log("Lender 3 USDC balance after Cyg     | %s USDC", (await usdc.balanceOf(lender3)) / 1e6)

    //
    console.log("Lender 4 Deposits 85,023 USDC")
    const lender_four = await makeUser(lender4)
    console.log("Lender 4 Balance of USDC Before: %s", await usdc.balanceOf(lender_four._address))
    await usdc.connect(lender_four).approve(borrowable.address, BigInt(1000000000e6))
    await borrowable.connect(lender_four).deposit(BigInt(85023e6), lender_four._address)

    console.log("balance of cygusd:  %s", borrowable.balanceOf(lender_four._address))
    console.log("balance of usd:  %s", usdc.balanceOf(lender_four._address))
    console.log("cyg-usdc total supply: %s", await borrowable.totalSupply())
    console.log("cyg-usdc total balance: %s", await borrowable.totalBalance())
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log("Lender 4 Redeems")
    const balx = await borrowable.balanceOf(lender_four._address)
    await borrowable.connect(lender_four).redeem(balx, lender_four._address, lender_four._address)

    console.log("balance of cygusd:  %s", borrowable.balanceOf(lender_four._address))
    console.log("cyg-usdc total supply: %s", await borrowable.totalSupply())
    console.log("cyg-usdc total balance: %s", await borrowable.totalBalance())
    console.log("Borrowable Exchange Rate:            | %s", await borrowable.callStatic.exchangeRate())

    console.log("Lender 4 USDC balance after Cyg     | %s USDC", (await usdc.balanceOf(lender_four._address)) / 1e6)
}

stargatePool()
