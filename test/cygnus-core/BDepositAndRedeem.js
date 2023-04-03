// JS
const path = require("path")

// Hardhat
const hre = require("hardhat")
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers")
const ethers = hre.ethers
const max = ethers.constants.MaxUint256

// Testers
const { expect } = require("chai")
const { describe, it } = require("mocha")

// Fixture
const Make = require(path.resolve(__dirname, "../MakeInch.js"))
const Users = require(path.resolve(__dirname, "../Users.js"))
const Strategy = require(path.resolve(__dirname, "../Strategy.js"))

describe("Borrowable Deposit and Redeem", function () {
    async function deployFixure() {
    const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make()
    const [, , rewardToken, pid, rewardTokenB] = await Strategy()
    const [owner, , safeAddress2, lender, borrower] = await Users()

        await collateral.connect(owner).chargeVoid(pid)
        await borrowable.connect(owner).chargeVoid(0)

        return { router, borrowable, collateral, usdc, lpToken, owner, lender, borrower, chainId, rewardTokenB }
    }

    describe("Deployment", function () {
        it("Should deploy borrowable pool with USDC underlying", async function () {
            const { borrowable, usdc } = await loadFixture(deployFixure)
            const underlying = await borrowable.underlying()
            expect(underlying.toLowerCase()).to.equal(usdc.address)
        })

        it("Should have 0 total supply", async function () {
            const { borrowable } = await loadFixture(deployFixure)
            expect(await borrowable.totalSupply()).to.equal(0)
        })

        it("Should have 0 total balance", async function () {
            const { borrowable } = await loadFixture(deployFixure)
            expect(await borrowable.totalBalance()).to.equal(0)
        })

        it("Should have 0 total borrows", async function () {
            const { borrowable } = await loadFixture(deployFixure)
            expect(await borrowable.totalBorrows()).to.equal(0)
        })

        it("Should have 0 total reserves", async function () {
            const { borrowable } = await loadFixture(deployFixure)
            expect(await borrowable.totalReserves()).to.equal(0)
        })

        it("Should have the initial exchange rate of one mantissa", async function () {
            const { borrowable } = await loadFixture(deployFixure)
            expect(await borrowable.callStatic.exchangeRate()).to.equal(BigInt(1e18))
        })
    })

    // Deposits
    describe("Lender 1 deposits 3000 USDC", function () {
        it("Should mint the correct amount of shares", async () => {
            const { borrowable, lender, usdc } = await loadFixture(deployFixure)
            await usdc.connect(lender).approve(borrowable.address, max)
            await borrowable.connect(lender).deposit(BigInt(3000e6), lender._address)
            // Take into account stargate rounding and the 1000 shares minted to 0xdead
            expect(await borrowable.balanceOf(lender._address)).to.equal(BigInt(3000e6) - BigInt(1000) - BigInt(1))
        })
    })
})
