// JS
const path = require("path");
// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;
// Shh
ethers;

// Testers
const { expect } = require("chai");
const { describe, it } = require("mocha");

// Fixture
const Make = require(path.resolve(__dirname, "../Make.js"));
const Users = require(path.resolve(__dirname, "../Users.js"));
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

/**
 *  @notice Test the borrowable model for interest rate curve and make sure borrow rate is correct
 */
describe("Cygnus Borrow Model", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    const deployFixure = async () => {
        // Make lending pool and collateral
        const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, , , lender, borrower] = await Users();

        // Charge Borrowbale allowance to deposit in rewarder
        await borrowable.chargeVoid();

        // Charge Collateral allowance to deposit in rewarder
        await collateral.chargeVoid();

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
            chainId, // Chain ID of the network being tested
        };
    };

    describe("Makes Cygnus Core", () => {
        // Load the initial test fixture to use in subsequent tests
        it("Should load fixture", async () => {
            await loadFixture(deployFixure);
        });
    });

    // NOTE: We checked for admin control and ensured params are in value when updating in `ControlBorrow.js` test
    describe("Checks the interest rate curve is correct", () => {
        // Interest rate model
        it("Has correct annualized values stored", async () => {
            // Load the fixture to get the Borrowable contract and its owner
            const { borrowable, owner } = await loadFixture(deployFixure);

            // Set the base interest rate to 1% per year
            const baseRate = BigInt(0.02e18);

            // Set the slope of the interest rate curve to 5% per year
            const slope = BigInt(0.05e18);

            // Set the kink multiplier to 4x
            const kink = BigInt(4);

            // Set the utilization rate to 85%
            const util = BigInt(0.85e18);

            // Set the new interest rate model parameters and check for the NewInterestRateParameters event
            await expect(borrowable.connect(owner).setInterestRateModel(baseRate, slope, kink, util))
                .to.emit(borrowable, "NewInterestRateParameters")
                .withArgs(baseRate, slope, kink, util);

            // The number of seconds per year assumed by the model
            const secondsPerYear = BigInt(24 * 60 * 60 * 365);

            // Get the stored interest rate model variables from Borrowable (they are stored per second)
            const baseRatePerSecond = await borrowable.baseRatePerSecond();
            const multiplierPerSecond = await borrowable.multiplierPerSecond();
            const jumpMultiplierPerSecond = await borrowable.jumpMultiplierPerSecond();
            const kinkMultiplier = await borrowable.kinkMultiplier();
            const utilizationRate = await borrowable.kinkUtilizationRate();

            // Check that the stored interest rate model variables are correct
            expect(baseRatePerSecond).to.equal(baseRate / secondsPerYear);
            expect(multiplierPerSecond).to.equal((slope * BigInt(1e18)) / (secondsPerYear * util));
            expect(jumpMultiplierPerSecond).to.equal((((slope * kink) / secondsPerYear) * BigInt(1e18)) / util);
            expect(kinkMultiplier).to.equal(4);
            expect(util).to.equal(utilizationRate);

            // No borrows or balance
            const currentUtil = await borrowable.utilizationRate();
            expect(currentUtil).to.equal(0);

            // No borrows so interest rate is just base rate atm
            const currentBorrowAPR = await borrowable.borrowRate();
            expect(currentBorrowAPR).to.equal(baseRatePerSecond);
        });
    });
});
