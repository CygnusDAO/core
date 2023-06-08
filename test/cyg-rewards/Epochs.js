// JS
const path = require("path");
// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;
const { time } = require("@nomicfoundation/hardhat-network-helpers");

// Testers
const { expect } = require("chai");
const { describe, it } = require("mocha");

// Fixture
const Make = require(path.resolve(__dirname, "../Make.js"));
const Users = require(path.resolve(__dirname, "../Users.js"));
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// const ONE = ethers.utils.parseUnits("1", 18);

// CYG Token rewards
describe("Cygnus Rewarder Epochs tests", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    const deployFixure = async () => {
        // Make lending pool and collateral
        const [, , router, borrowable, collateral, usdc, lpToken] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, , , lender, borrower] = await Users();

        // Get rewarder address
        const rewarderAddress = await borrowable.cygnusBorrowRewarder();

        const rewarder = await ethers.getContractAt("CygnusComplexRewarder", rewarderAddress);

        // Update all pools
        await rewarder.accelerateTheUniverse();

        // Return an object containing the various contracts, users, and initial balances for testing
        return {
            router, // Router contract
            borrowable, // Lending pool contract
            collateral, // Collateral contract
            usdc, // USDC contract
            lpToken, // LP token contract
            owner, // Owner (admin) user
            lender, // Lender user
            borrower, // Borrower user
            rewarder, // Cyg Rewarder
        };
    };

    /**
     *  BEGIN TESTS
     */
    describe("------------------- Begin Test -------------------", () => {
        it("...begins...", async () => await loadFixture(deployFixure));
    });

    describe("Initial CYG Complex Rewarder status", () => {
        // calculateEpochRewards()
        it("Should have 3,000,000 total rewards", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const epochs = await rewarder.TOTAL_EPOCHS();

            let totalRewards = ethers.BigNumber.from(0);

            for (let i = 0; i < epochs; i++) {
                const currentRewards = await rewarder.calculateEpochRewards(i);
                totalRewards = totalRewards.add(currentRewards);
            }

            // 3 Million 18 decimals
            expect(totalRewards).to.be.closeTo("3000000000000000000000000", BigInt(100));
        });

        // getCurrrentEpoch()
        it("Should be at epoch 0 after deployment", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const epoch = await rewarder.getCurrentEpoch();

            // Epoch 0
            expect(epoch).to.be.equal(0);
        });

        // currentEpochRewards()
        it("Should have initial epoch rewards of ~176,693.58 CYG and same as epoch struct", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const rewards = await rewarder.currentEpochRewards();
            const epoch = await rewarder.getEpochInfo(0);

            // Close by 0.01 CYG
            expect(rewards).to.be.closeTo(BigInt(176693.582e18), BigInt(0.01e18));
            expect(epoch.totalRewards).to.be.equal(rewards);
        });

        // cygPerBlock()
        it("Should have initial cygPerBlock of 0.067235", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const cygPerBlock = await rewarder.cygPerBlock();
            const epoch = await rewarder.getEpochInfo(0);

            // Close by 0.01 CYG
            expect(cygPerBlock).to.be.closeTo(BigInt(0.067235e18), BigInt(0.00001e18));
            expect(epoch.rewardRate).to.be.equal(cygPerBlock);
        });

        it("Should have a final epoch rewards of ~12374.16139", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const rewards = await rewarder.calculateEpochRewards(47);

            expect(rewards).to.be.closeTo(BigInt(12374.16139e18), BigInt(0.0001e18));
        });

        it("Should have a final cygPerBlock of 0.004708", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const cygPerBlock = await rewarder.calculateCygPerBlock(47);

            expect(cygPerBlock).to.be.closeTo(BigInt(0.004708e18), BigInt(0.00001e18));
        });

        // advance()
        it("Shouldnt advance if we have not passed 30 days", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            const epochBefore = await rewarder.getCurrentEpoch();

            await rewarder.advanceEpoch();

            const epochAfter = await rewarder.getCurrentEpoch();

            // Epoch 0
            expect(epochBefore).to.be.equal(epochAfter);
        });

        // advance()
        // advance()
        it("Shouldn't advance if 29 days have passed", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            // Increase time by 29 days
            await time.increase(2622000);
            const epochBefore = await rewarder.getCurrentEpoch();

            // Try to advance epoch
            await rewarder.advanceEpoch();

            const epochAfter = await rewarder.getCurrentEpoch();

            // Epoch should remain the same (Epoch 0)
            expect(epochBefore).to.be.equal(epochAfter);
        });

        // Time until next epoch
        // blocksUntilNextEpoch()
        it("Should calculate time until next epoch correctly", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            // Get the duration of each epoch
            const duration = await rewarder.BLOCKS_PER_EPOCH();
            const timeUntil = await rewarder.blocksUntilNextEpoch();

            // Time until next epoch should be less than the duration of each epoch
            expect(timeUntil).to.be.lt(duration);
        });

        // advance()
        it("Should advance if enough time has passed", async () => {
            // Fixture
            const { rewarder } = await loadFixture(deployFixure);

            // Get current epoch and cygPerBlock
            const _epoch = await rewarder.getCurrentEpoch();
            const _cygPerBlock = await rewarder.cygPerBlock();

            // Get the time until the next epoch
            const timeUntil = await rewarder.blocksUntilNextEpoch();

            // Increase time by the required duration for the next epoch
            await time.increase(timeUntil);

            // Calculate the new cygPerBlock for the next epoch
            const cygPerBlock_ = await rewarder.calculateCygPerBlock(1);

            // Advance to the next epoch and emit "NewEpoch" event
            await expect(rewarder.advanceEpoch()).to.emit(rewarder, "NewEpoch").withArgs(0, 1, _cygPerBlock, cygPerBlock_);

            const epoch_ = await rewarder.getCurrentEpoch();

            // Current epoch should be greater than the previous epoch
            expect(epoch_).to.be.gt(_epoch);

            // Current epoch should be equal to 1
            expect(await rewarder.getCurrentEpoch()).to.be.equal(1);

            // Verify that the new rewards match the total rewards for the epoch
            const newRewards = await rewarder.currentEpochRewards();

            const epochInfo = await rewarder.getEpochInfo(epoch_);

            expect(newRewards).to.be.equal(epochInfo.totalRewards);
        });
    });
});
