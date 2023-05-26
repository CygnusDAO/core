// JS
const path = require("path");
// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

// Testers
const { expect } = require("chai");
const { describe, it } = require("mocha");

// Fixture
const Make = require(path.resolve(__dirname, "../Make.js"));
const Users = require(path.resolve(__dirname, "../Users.js"));
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

/**
 *  @notice Admin controls for core pools
 */
describe("CgynusBorrow Admin Controls", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    async function deployFixure() {
        // Make lending pool and collateral
        const [, hangar18, router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, , safeAddress1, lender, borrower] = await Users();

        // Charge Borrowbale allowance to deposit in rewarder
        await borrowable.chargeVoid();

        // Charge Collateral allowance to deposit in rewarder
        await collateral.chargeVoid();

        return {
            hangar18, // Factory-like contract
            router, // Router contract
            borrowable, // Lending pool contract
            collateral, // Collateral contract
            usdc, // USDC contract
            lpToken, // LP token contract
            owner, // Owner (admin) user
            safeAddress1, // Signer representing a trusted party
            lender, // Lender user before CYG
            borrower, // Borrower user before CYG
            chainId, // Chain ID of the network being tested
        };
    }

    describe("------------------- Begin Test -------------------", () => {
        // Load the initial test fixture to use in subsequent tests
        it("Should load fixture", async () => {
            await loadFixture(deployFixure);
        });
    });

    describe("All control updates revert unless msg.sender is factory admin", () => {
        // Interest Rate
        it("Should revert when non-admin attempts to set a new interest rate curve", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner, lender } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(
                borrowable
                    .connect(lender)
                    .setInterestRateModel(BigInt(0.05e18), BigInt(0.05e18), BigInt(2), BigInt(0.75e18)),
            ).to.be.reverted;
        });

        // Reserve Factor
        it("Should revert when non-admin attempts to set a new reserve factor", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner, lender } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(lender).setReserveFactor(BigInt(0.05e18))).to.be.reverted;
        });

        // Borrow Rewarder
        it("Should revert when non-admin attempts to set a new borrow rewarder", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner, lender } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(lender).setCygnusBorrowRewarder(lender._address)).to.be.reverted;
        });
    });

    /**
     *  Tests the behavior of the `setInterestRateModel` function of a Borrowable contract, when the function is called with
     *  invalid parameters. This function should revert when the new interest rate parameters are outside the allowed ranges.
     *  1. When the new base rate is greater than the maximum allowed value of 10%.
     *  2. When the new kink multiplier is greater than the maximum allowed value of 10.
     *  3. When the new kink multiplier is less than the minimum allowed value of 1.
     *  4. When the new util rate is more than the max allowed value of 95%
     *  5. When the new util rate is less than the min allowed value of 50%
     *  6. When the reserve factor is more than the max allowed value of 20%
     */
    describe("All control updates should revert when set outside params allowed", () => {
        // Interest Rate - BASE RATE
        it("Should revert when admin tries to set a new interest rate param above range: BASE RATE (10%)", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX BASE RATE = 10%;

            // New base
            const baseRate = BigInt(0.101e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(owner).setInterestRateModel(baseRate, 0, 2, BigInt(0.75e18))).to.be
                .reverted;
        });

        // Interest Rate - KINK MUTLIPLIER
        it("Should revert when admin tries to set a new interest rate param above range: KINK MULTIPLIER (10)", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX KINK MULTIPLIER = 10;

            // New base
            const kink = 11;

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, kink, BigInt(0.75e18))).to.be.reverted;
        });

        // Interest Rate - KINK MUTLIPLIER
        it("Should revert when admin tries to set a new interest rate param below range: KINK MULTIPLIER (1)", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MIN KINK MULTIPLIER = 1;

            // New kink
            const kink = 0;

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, kink, BigInt(0.75e18))).to.be.reverted;
        });

        // Interest Rate - UTILIZATION RATE
        it("Should revert when admin tries to set a new interest rate param above range: UTILIZATION RATE (95%)", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX UTIL = 95%;

            // New kink
            const util = BigInt(0.96e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, 2, util)).to.be.reverted;
        });

        // Interest Rate - UTILIZATION RATE
        it("Should revert when admin tries to set a new interest rate param below range: UTILIZATION RATE (50%)", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MIN UTIL = 49%;

            // New kink
            const util = BigInt(0.49e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, 2, util)).to.be.reverted;
        });

        // Reserve factor
        it("Should revert when admin tries to set a new reserve factor above range: RESERVE FACTOR (20%)", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX RESERVE FACTOR = 20%;

            // New kink
            const newReserveFactor = BigInt(0.20001e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(borrowable.connect(owner).setReserveFactor(newReserveFactor)).to.be.reverted;
        });
    });
    describe("All control updates succeed when params are within ranges allowed", () => {
        // Interest Rate - BASE RATE
        it("Should set a new interest rate param: Base Rate", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Ensure that the admin is the factory owner
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // The maximum base rate is 10%
            const maxBaseRate = BigInt(0.1e18);

            // Set a new base rate
            const newBaseRate = BigInt(0.01e18);
            await expect(borrowable.connect(owner).setInterestRateModel(newBaseRate, 0, 2, BigInt(0.75e18)))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(newBaseRate, 0, 2, BigInt(0.75e18)); // Verify event log params with baseRate, multiplier, kinkMultiplier and util

            // Set another new base rate
            const noBaseRate = 0;
            await expect(borrowable.connect(owner).setInterestRateModel(noBaseRate, 0, 2, BigInt(0.75e18)))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(noBaseRate, 0, 2, BigInt(0.75e18)); // Verify event log params

            // Set a base rate at the maximum limit
            await expect(borrowable.connect(owner).setInterestRateModel(maxBaseRate, 0, 2, BigInt(0.75e18)))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(maxBaseRate, 0, 2, BigInt(0.75e18)); // Verify event log params
        });

        it("Should set a new interest rate param: Kink Multiplier", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MIN KINK MULTIPLIER = 1
            // MAX KINK MULTIPLIER = 10

            // Mid kink multiplier
            const kink = 6;

            // Update new kink multiplier
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, kink, BigInt(0.75e18)))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(0, 0, kink, BigInt(0.75e18)); // Check event log params for base rate, multiplier, kinkMultiplier and util

            // Max kink multiplier
            const newKink = 10;

            // Update with new kink multiplier
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, newKink, BigInt(0.75e18)))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(0, 0, newKink, BigInt(0.75e18)); // Verify event log params

            // No kink multiplier
            const noKink = 1;

            // Update with no kink multiplier
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, noKink, BigInt(0.75e18)))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(0, 0, noKink, BigInt(0.75e18)); // Verify event log params
        });

        it("Should set a new interest rate param: Util Rate", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MIN KINK UTILIZATION = 50%;
            // MAX KINK UTILIZATION = 95%;

            // New Util (82%)
            const util = BigInt(0.82e18);

            // Update interest rate model with new utilization rate
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, 2, util))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(0, 0, 2, util); // Verify event log params

            // Max Util (95%)
            const maxUtil = BigInt(0.95e18);

            // Update interest rate model with maximum utilization rate
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, 2, maxUtil))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(0, 0, 2, maxUtil); // Ensure correct params in event log

            // Min Util (50%)
            const minUtil = BigInt(0.5e18);

            // Update interest rate model with minimum utilization rate
            await expect(borrowable.connect(owner).setInterestRateModel(0, 0, 2, minUtil))
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(0, 0, 2, minUtil); // Verify event log params
        });

        it("Should set a new reserve factor", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check that the admin is the factory owner
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX RESERVE FACTOR = 20%;

            // Get the current reserve factor
            const oldReserveFactor = await borrowable.reserveFactor();

            // Set a new reserve factor (20% - max)
            const newReserveFactor = BigInt(0.2e18);

            // Update the reserve factor with the new value
            await expect(borrowable.connect(owner).setReserveFactor(newReserveFactor))
                .to.emit(borrowable, "NewReserveFactor") // Check that a 'NewReserveFactor' event was emitted
                .withArgs(oldReserveFactor, newReserveFactor); // Verify event log params

            // Set reserve factor to 0% (no reserve factor)
            const noReserveFactor = 0;

            // Update the reserve factor to 0%
            await expect(borrowable.connect(owner).setReserveFactor(noReserveFactor))
                .to.emit(borrowable, "NewReserveFactor") // Check that a 'NewReserveFactor' event was emitted
                .withArgs(newReserveFactor, 0); // Verify event log params

            // Set reserve factor to a mid-range value (10%)
            const midReserveFactor = BigInt(0.1e18);

            // Update the reserve factor to the mid-range value
            await expect(borrowable.connect(owner).setReserveFactor(midReserveFactor))
                .to.emit(borrowable, "NewReserveFactor") // Check that a 'NewReserveFactor' event was emitted
                .withArgs(0, midReserveFactor); // Verify event log params
        });
    });

    // Test: New admin
    describe("A new admin is set at the factory and has control over core", () => {
        it("Sets a new hangar18 admin", async () => {
            // Load Fixture
            const { hangar18, safeAddress1, borrowable, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Set a new reserve factor for now with current admin

            // Get the old reserve factor of the Borrowable contract.
            const oldReserveFactor = await borrowable.reserveFactor();

            // Set the new reserve factor to 20% (maximum).
            const newReserveFactor = BigInt(0.2e18);

            // Update the reserve factor of the Borrowable contract with the new value.
            await expect(borrowable.connect(owner).setReserveFactor(newReserveFactor))
                .to.emit(borrowable, "NewReserveFactor") // Check that the NewReserveFactor event is emitted.
                .withArgs(oldReserveFactor, newReserveFactor); // Check the parameters of the emitted event.

            // Try to connect with the safe address (which is not yet the admin) and check that it should revert.
            await expect(borrowable.connect(safeAddress1).setReserveFactor(newReserveFactor)).to.be.reverted;

            // Set the safe address as the new pending admin of Hangar18.
            await expect(hangar18.connect(owner).setPendingAdmin(safeAddress1.address))
                .to.emit(hangar18, "NewPendingCygnusAdmin") // Check that the NewPendingCygnusAdmin event is emitted.
                .withArgs(ethers.constants.AddressZero, safeAddress1.address); // Check the parameters of the emitted event.

            // Try to connect with the safe address (which is not yet the admin) and check that it should revert.
            await expect(borrowable.connect(safeAddress1).setReserveFactor(newReserveFactor)).to.be.reverted;

            // Check that the pending admin of Hangar18 is the safe address.
            expect(await hangar18.pendingAdmin()).to.equal(safeAddress1.address);

            // Set the safe address as the new admin of Hangar18.
            await expect(hangar18.connect(owner).setNewCygnusAdmin())
                .to.emit(hangar18, "NewCygnusAdmin") // Check that the NewCygnusAdmin event is emitted.
                .withArgs(owner.address, safeAddress1.address); // Check the parameters of the emitted event.

            // Try to connect with the previous factory admin (which is not the admin anymore) and check that it should revert.
            await expect(borrowable.connect(owner).setReserveFactor(newReserveFactor)).to.be.reverted;

            // Previous one is 20%
            const _newReserveFactor = BigInt(0.075e18);

            // Update the reserve factor of the Borrowable contract with the new admin and the new value.
            await expect(borrowable.connect(safeAddress1).setReserveFactor(_newReserveFactor))
                .to.emit(borrowable, "NewReserveFactor")
                .withArgs(newReserveFactor, _newReserveFactor);
        });

        it("New admin sets another admin and the admin gives back control", async () => {
            // Load Fixture
            const { hangar18, safeAddress1, borrowable, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Old reserve factor
            const oldReserveFactor = await borrowable.reserveFactor();
            // New reserve factor
            const newReserveFactor = BigInt(0.075e18);

            // 1. Check that it reverts if not admin.
            await expect(borrowable.connect(safeAddress1).setReserveFactor(newReserveFactor)).to.be.reverted;

            // Set the safe address as the new pending admin of Hangar18.
            await expect(hangar18.connect(owner).setPendingAdmin(safeAddress1.address))
                .to.emit(hangar18, "NewPendingCygnusAdmin") // Check that the NewPendingCygnusAdmin event is emitted.
                .withArgs(ethers.constants.AddressZero, safeAddress1.address); // Check the parameters of the emitted event.

            // 2. Set new admin. Set the safe address as the new admin of Hangar18.
            await expect(hangar18.connect(owner).setNewCygnusAdmin())
                .to.emit(hangar18, "NewCygnusAdmin") // Check that the NewCygnusAdmin event is emitted.
                .withArgs(owner.address, safeAddress1.address); // Check the parameters of the emitted event.

            // 3. Try to connect with the previous factory admin (which is not the admin anymore) and check that it should revert.
            await expect(borrowable.connect(owner).setReserveFactor(newReserveFactor)).to.be.reverted;

            // 4. Update the reserve factor of the Borrowable contract with the new admin and the new value.
            await expect(borrowable.connect(safeAddress1).setReserveFactor(newReserveFactor))
                .to.emit(borrowable, "NewReserveFactor")
                .withArgs(oldReserveFactor, newReserveFactor);

            // 5. Change admin. Set the owner as the pending admin
            await expect(hangar18.connect(safeAddress1).setPendingAdmin(owner.address))
                .to.emit(hangar18, "NewPendingCygnusAdmin") // Check that the NewPendingCygnusAdmin event is emitted.
                .withArgs(ethers.constants.AddressZero, owner.address); // Check the parameters of the emitted event.

            // Check pending admin cant update yet
            await expect(borrowable.connect(owner).setReserveFactor(newReserveFactor)).to.be.reverted;

            // Set new admin
            await expect(hangar18.connect(safeAddress1).setNewCygnusAdmin())
                .to.emit(hangar18, "NewCygnusAdmin") // Check that the NewCygnusAdmin event is emitted.
                .withArgs(safeAddress1.address, owner.address); // Check the parameters of the emitted event.

            const maxReserveFactor = BigInt(0.2e18);
            // 6. Update the reserve factor of the Borrowable contract with the new admin and the new value.
            await expect(borrowable.connect(owner).setReserveFactor(maxReserveFactor))
                .to.emit(borrowable, "NewReserveFactor") // Check event
                .withArgs(newReserveFactor, maxReserveFactor); // The previous reserve factor is `newReserveFactor` and we updated to max
        });
    });

    // Test: Complex Rewarder
    describe("Complex Rewarder can be upgraded and/or set to zero address", () => {
        it("Should revert when not called by admin", async () => {
            // Load Fixture
            const { hangar18, safeAddress1, borrowable, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            await expect(borrowable.connect(safeAddress1).setCygnusBorrowRewarder(ethers.constants.AddressZero)).to.be
                .reverted;
        });

        it("Should update when called by admin", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Get old rewarder
            const oldRewarder = await borrowable.cygnusBorrowRewarder();

            // Use dummy address for new rewarder
            await expect(borrowable.connect(owner).setCygnusBorrowRewarder(owner.address))
                .to.emit(borrowable, "NewCygnusBorrowRewarder") // Check that the NewCygnusBorrowRewarder event is emitted.
                .withArgs(oldRewarder, owner.address); // Check event params
        });

        it("Should allow to be set to zero address when called by admin", async () => {
            // Load Fixture
            const { hangar18, borrowable, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Get old rewarder
            const oldRewarder = await borrowable.cygnusBorrowRewarder();

            // Use dummy address for new rewarder
            await expect(borrowable.connect(owner).setCygnusBorrowRewarder(ethers.constants.AddressZero))
                .to.emit(borrowable, "NewCygnusBorrowRewarder") // Check that the NewCygnusBorrowRewarder event is emitted.
                .withArgs(oldRewarder, ethers.constants.AddressZero); // Check event params
        });
    });
});
