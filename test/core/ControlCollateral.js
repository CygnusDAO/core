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
describe("CygnusCollateral Admin Controls", function () {
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

    describe("Makes Cygnus Core", () => {
        // Load the initial test fixture to use in subsequent tests
        it("Should load fixture", async () => {
            await loadFixture(deployFixure);
        });
    });

    describe("All control updates revert unless msg.sender is factory admin", () => {
        // Debt ratio
        it("Should revert when non-admin attempts to set a new debt ratio", async () => {
            // Load Fixture
            const { hangar18, collateral, owner, borrower } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // New debt ratio
            const newDebtRatio = BigInt(0.75e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(collateral.connect(borrower).setDebtRatio(newDebtRatio)).to.be.reverted;
        });

        // Liq incentive
        it("Should revert when non-admin attempts to set a new liquidation incentive", async () => {
            // Load Fixture
            const { hangar18, collateral, owner, borrower } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // New liq incentive (10%)
            const newLiqIncentive = BigInt(1.1e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(collateral.connect(borrower).setLiquidationIncentive(newLiqIncentive)).to.be.reverted;
        });

        // Liq fee
        it("Should revert when non-admin attempts to set a new liq fee", async () => {
            // Load Fixture
            const { hangar18, collateral, owner, borrower } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // New liq fee (1%)
            const newLiqFee = BigInt(0.01e18);

            // If msg.sender is not factory admin (the `owner` account) then it should revert
            await expect(collateral.connect(borrower).setLiquidationFee(newLiqFee)).to.be.reverted;
        });
    });

    // TEST: Outside params
    describe("All control updates should revert when set outside params allowed", () => {
        // Max Debt Ratio
        it("Should revert when admin tries to set a debt ratio above range: DEBT RATIO (100%)", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX_DEBT_RATIO = 100%

            // New debt ratio (101%)
            const newDebtRatio = BigInt(1.01e18);

            // Above range
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio)).to.be.reverted;
        });

        // Min Debt Ratio
        it("Should revert when admin tries to set a debt ratio below range: DEBT RATIO (50%)", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MIN_DEBT_RATIO = 50%

            // New debt ratio (49%)
            const newDebtRatio = BigInt(0.49e18);

            // Above range
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio)).to.be.reverted;
        });

        // Max Liquidation Incentive
        it("Should revert when admin tries to set a new liq. incentive above range: LIQ INCENTIVE (15%)", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX_LIQ_INCENTIVE = 15%

            // New liquidation incentive
            const newLiqIncentive = BigInt(1.16e18);

            // Above range
            await expect(collateral.connect(owner).setLiquidationIncentive(newLiqIncentive)).to.be.reverted;
        });

        // Min Liquidation Incentive
        it("Should revert when admin tries to set a new liq. incentive below range: LIQ INCENTIVE (0%)", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MIN_LIQ_INCENTIVE = 0% (1e18)

            // New liquidation incentive
            const newLiqIncentive = BigInt(0.99e17);

            // Above range
            await expect(collateral.connect(owner).setLiquidationIncentive(newLiqIncentive)).to.be.reverted;
        });

        // Max Liquidation Fee 10%
        it("Should revert when admin tries to set a new liq. fee above range: LIQ FEE (10%)", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // MAX_LIQUIDATION_FEE = 10%

            // New liquidation fee
            const newLiqFee = BigInt(0.11e18); // 11%

            // Above range
            await expect(collateral.connect(owner).setLiquidationFee(newLiqFee)).to.be.reverted;
        });
    });

    describe("All control updates succeed when params are within ranges allowed and msg.sender is admin", () => {
        // Debt ratio
        it("Should set a new debt ratio", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Current debt ratio
            const debtRatio = await collateral.debtRatio();
            // New debt ratio (75%)
            const newDebtRatio = BigInt(0.825e18);

            // Above range
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio))
                .to.emit(collateral, "NewDebtRatio") // Check that a 'NewDebtRatio' event was emitted
                .withArgs(debtRatio, newDebtRatio); // Check event log params
        });

        it("Should set a new liquidation incentive", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Current liq incentive
            const liqIncentive = await collateral.liquidationIncentive();
            const newLiqIncentive = BigInt(1.1e18); // 10%

            // Above range
            await expect(collateral.connect(owner).setLiquidationIncentive(newLiqIncentive))
                .to.emit(collateral, "NewLiquidationIncentive") // Check that a 'NewLiquidationIncentive' event was emitted
                .withArgs(liqIncentive, newLiqIncentive); // Verify event log params
        });

        it("Should set a new liquidation fee", async () => {
            // Load Fixture
            const { hangar18, collateral, owner } = await loadFixture(deployFixure);

            // Get current factory admin
            const admin = await hangar18.admin();

            // Check admin is factory admin
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Current liq fee
            const liqFee = await collateral.liquidationFee();
            const newLiqFee = BigInt(0.02e18); // 2%

            // Above range
            await expect(collateral.connect(owner).setLiquidationFee(newLiqFee))
                .to.emit(collateral, "NewLiquidationFee") // Check that a 'NewLiquidationFee' event was emitted
                .withArgs(liqFee, newLiqFee); // Verify event log params
        });
    });

    // Test: New admin
    describe("A new admin is set at the factory and has control over core", () => {
        it("Sets a new hangar18 admin", async () => {
            // Load Fixture
            const { hangar18, safeAddress1, collateral, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Set a new reserve factor for now with current admin

            // Current debt ratio
            const debtRatio = await collateral.debtRatio();

            // Set a new debt raito of 65%
            const newDebtRatio = BigInt(0.9333e18);

            // Update the debt ratio of the collateral contract with the new value.
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio))
                .to.emit(collateral, "NewDebtRatio") // Check that a 'NewReserveFactor' event was emitted.
                .withArgs(debtRatio, newDebtRatio); // Check the parameters of the emitted event.

            // Try to connect with the safe address (which is not yet the admin) and check that it should revert.
            await expect(collateral.connect(safeAddress1).setDebtRatio(newDebtRatio)).to.be.reverted;

            // Set the safe address as the new pending admin of Hangar18.
            await expect(hangar18.connect(owner).setPendingAdmin(safeAddress1.address))
                .to.emit(hangar18, "NewPendingCygnusAdmin") // Check that the NewPendingCygnusAdmin event is emitted.
                .withArgs(ethers.constants.AddressZero, safeAddress1.address); // Check the parameters of the emitted event.

            // Try to connect with the safe address (which is not yet the admin) and check that it should revert.
            await expect(collateral.connect(safeAddress1).setDebtRatio(newDebtRatio)).to.be.reverted;

            // Check that the pending admin of Hangar18 is the safe address.
            expect(await hangar18.pendingAdmin()).to.equal(safeAddress1.address);

            // Set the safe address as the new admin of Hangar18.
            await expect(hangar18.connect(owner).setNewCygnusAdmin())
                .to.emit(hangar18, "NewCygnusAdmin") // Check that the NewCygnusAdmin event is emitted.
                .withArgs(owner.address, safeAddress1.address); // Check the parameters of the emitted event.

            // Try to connect with the previous factory admin (which is not the admin anymore) and check that it should revert.
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio)).to.be.reverted;

            // Previous one is 65%
            const maxDebtRatio = BigInt(1e18);

            // Update the reserve factor of the Borrowable contract with the new admin and the new value.
            await expect(collateral.connect(safeAddress1).setDebtRatio(maxDebtRatio))
                .to.emit(collateral, "NewDebtRatio")
                .withArgs(newDebtRatio, maxDebtRatio);
        });

        it("New admin sets another admin and the admin gives back control", async () => {
            // Load Fixture
            const { hangar18, safeAddress1, collateral, owner } = await loadFixture(deployFixure);

            // Get the current factory admin from Hangar18 contract.
            const admin = await hangar18.admin();

            // Assert that the current admin is the same as the owner of the contract.
            expect(admin.toLowerCase()).to.be.equal(owner.address.toLowerCase());

            // Old debt ratio
            const oldDebtRatio = await collateral.debtRatio();
            // New debt ratio
            const newDebtRatio = BigInt(0.925e18); // 55%

            // 1. Check that it reverts if not admin.
            await expect(collateral.connect(safeAddress1).setDebtRatio(newDebtRatio)).to.be.reverted;

            // Set the safe address as the new pending admin of Hangar18.
            await expect(hangar18.connect(owner).setPendingAdmin(safeAddress1.address))
                .to.emit(hangar18, "NewPendingCygnusAdmin") // Check that the NewPendingCygnusAdmin event is emitted.
                .withArgs(ethers.constants.AddressZero, safeAddress1.address); // Check the parameters of the emitted event.

            // 2. Set new admin. Set the safe address as the new admin of Hangar18.
            await expect(hangar18.connect(owner).setNewCygnusAdmin())
                .to.emit(hangar18, "NewCygnusAdmin") // Check that the NewCygnusAdmin event is emitted.
                .withArgs(owner.address, safeAddress1.address); // Check the parameters of the emitted event.

            // 3. Try to connect with the previous factory admin (which is not the admin anymore) and check that it should revert.
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio)).to.be.reverted;

            // 4. Update the debt ratio of the collateral contract with the new admin and the new value.
            await expect(collateral.connect(safeAddress1).setDebtRatio(newDebtRatio))
                .to.emit(collateral, "NewDebtRatio")
                .withArgs(oldDebtRatio, newDebtRatio);

            // 5. Change admin. Set the owner as the pending admin
            await expect(hangar18.connect(safeAddress1).setPendingAdmin(owner.address))
                .to.emit(hangar18, "NewPendingCygnusAdmin") // Check that the NewPendingCygnusAdmin event is emitted.
                .withArgs(ethers.constants.AddressZero, owner.address); // Check the parameters of the emitted event.

            // Check pending admin cant update yet
            await expect(collateral.connect(owner).setDebtRatio(newDebtRatio)).to.be.reverted;

            // Set new admin
            await expect(hangar18.connect(safeAddress1).setNewCygnusAdmin())
                .to.emit(hangar18, "NewCygnusAdmin") // Check that the NewCygnusAdmin event is emitted.
                .withArgs(safeAddress1.address, owner.address); // Check the parameters of the emitted event.

            const maxDebtRatio = BigInt(0.95e18);
            // 6. Update the reserve factor of the Collateral contract with the new admin and the new value.
            await expect(collateral.connect(owner).setDebtRatio(maxDebtRatio))
                .to.emit(collateral, "NewDebtRatio") // Check event
                .withArgs(newDebtRatio, maxDebtRatio); // The previous debt ratio is `newDebtRatio` and we updated to max
        });
    });
});
