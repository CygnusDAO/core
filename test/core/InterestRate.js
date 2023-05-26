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

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");
const permit2Abi = require(path.resolve(__dirname, "../../scripts/abis/permit2.json"));

// Constants
const { MaxUint256 } = ethers.constants;
const ONE = ethers.utils.parseUnits("1", 18);

/**
 *  - Borrower deposits 2 LPs
 *  - Lender deposits 1000 USDC
 *  - Utilization rate ~20%
 *  - Borrower borrows as much USDC as possible
 */
describe("Cygnus Integration Redeem Tests", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    const deployFixure = async () => {
        // Make lending pool and collateral
        const [, factory, router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, , safeAddress1, lender, borrower] = await Users();

        // Charge Borrowbale allowance to deposit in rewarder
        await borrowable.chargeVoid();

        // Charge Collateral allowance to deposit in rewarder
        await collateral.chargeVoid();

        // Load the permit2 contract ABI
        const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

        // Get initial balances of lender and borrower
        const lenderInitialBal = await usdc.balanceOf(lender._address);
        const borrowerInitialBal = await lpToken.balanceOf(borrower._address);

        // Deposit 100,000 USDC into the lending pool
        await lenderDeposit(owner, usdc, lender, borrowable, permit2);

        // Deposit 2 LP tokens into the collateral pool
        await borrowerDeposit(owner, lpToken, borrower, collateral, permit2);

        // Set BorrowAPR to 0% first
        await borrowable.connect(owner).setInterestRateModel(BigInt(0), BigInt(0), 2, BigInt(0.8e18));

        // Approve router
        await factory.connect(borrower).setMasterBorrowApproval(router.address);

        // Borrow max Liquidity
        await borrowUsd(borrower, borrowable, collateral, router);

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
            lenderInitialBal, // Initial balance of the lender's USDC before CYG
            borrowerInitialBal, // Initial balance of the borrower's LP tokens before CYG
            permit2, // Permit2 contract instance
            safeAddress1, // Extra ethers signer
        };
    };

    /**
     *  Deposits stablecoins into the borrowable contract using lender's address with permit2
     *
     *  @param {ethers.Signer} owner - The address that signs the permit and executes the deposit.
     *  @param {ethers.Contract} usdc - The USDC contract instance.
     *  @param {ethers.Signer} lender - The address that will receive the CygUSD.
     *  @param {ethers.Contract} borrowable - The borrowable contract instance.
     *  @param {ethers.Contract} permit2 - The permit2 contract instance.
     */
    const lenderDeposit = async (owner, usdc, lender, borrowable, permit2) => {
        // Get the chain ID for the permit
        const chainId = await owner.getChainId();

        // Get the nonce for the permit
        const { nonce } = await permit2.allowance(owner.address, usdc.address, borrowable.address);

        // Step 1: Approve permit2 in USDC
        await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

        // Step 2: Build the permit
        const permit = {
            details: {
                token: usdc.address,
                amount: BigInt(100000e6), // Deposit amount of 100,000 USDC
                expiration: MaxAllowanceExpiration,
                nonce: nonce,
            },
            spender: borrowable.address,
            sigDeadline: MaxUint256,
        };

        // Sign the permit
        const permitData = AllowanceTransfer.getPermitData(permit, PERMIT2_ADDRESS, chainId);
        const signature = await owner._signTypedData(permitData.domain, permitData.types, permitData.values);

        // Step 3: Transfer USDC to `owner` from `lender`
        await usdc.connect(lender).transfer(owner.address, BigInt(100000e6));

        // Step 4: `owner` deposits the USDC into the `borrowable` contract for `lender`
        await borrowable.connect(owner).deposit(BigInt(1000e6), lender._address, permit, signature);
    };

    /**
     *  Deposits LP tokens into the collateral contract using borrower's address with permit2
     *
     *  @param {ethers.Signer} owner - the signer of the owner (admin) account
     *  @param {ethers.Contract} lpToken - The LP Token contract
     *  @param {ethers.Signer} borrower - The LP Token depositor
     *  @param {ethers.Contract} collateral - The collateral contract instance
     *  @param {ethers.Contract} permit2 - The permit2 contract instance.
     */
    const borrowerDeposit = async (owner, lpToken, borrower, collateral, permit2) => {
        // Get the chain ID
        const _chainId = await owner.getChainId();

        // Get the nonce from the permit2 contract
        const { nonce } = await permit2.allowance(owner.address, lpToken.address, collateral.address);

        // 1. Approve permit2 in LP token
        await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

        // 2. Build permit (increase nonce manually)
        const permit = {
            details: {
                token: lpToken.address,
                amount: BigInt(2e18),
                expiration: MaxAllowanceExpiration,
                nonce: nonce,
            },
            spender: collateral.address,
            sigDeadline: MaxUint256,
        };

        // Sign the permit
        const permitData = AllowanceTransfer.getPermitData(permit, PERMIT2_ADDRESS, _chainId);
        const signature = await owner._signTypedData(permitData.domain, permitData.types, permitData.values);

        // 3. Transfer LP tokens to owner
        await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

        // 4. Owner deposits using borrower address
        await collateral.connect(owner).deposit(BigInt(2e18), borrower._address, permit, signature);
    };

    // Borrower borrows USD
    const borrowUsd = async (borrower, borrowable, collateral, router) => {
        // Get the current liquidity of the borrower's account
        const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

        // Borrow the maximum amount possible from the borrowable token
        await router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x");
    };

    /**
     *  BEGIN TESTS
     */
    describe("------------------- Begin Test -------------------", () => {
        it("...begins...", async () => await loadFixture(deployFixure));
    });

    describe("Checks we have positive balance of CygUSD and CygLP", () => {
        // Check balance CygUSD
        it("Should have positive balance of CygUSD", async () => {
            // Fixture
            const { borrowable, lender, usdc, lenderInitialBal } = await loadFixture(deployFixure);

            // Get balance of CygUSD
            expect(await borrowable.balanceOf(lender._address)).to.be.gt(0);

            // Get balance of USD
            expect(await usdc.balanceOf(lender._address)).to.be.lt(lenderInitialBal);
        });

        // Check balance CygLP
        it("Should have positive balance of CygLP", async () => {
            // Fixture
            const { collateral, borrower, lpToken, borrowerInitialBal } = await loadFixture(deployFixure);

            // Check balance of CygLP
            expect(await collateral.balanceOf(borrower._address)).to.be.gt(0);

            // Check balance of LP
            expect(await lpToken.balanceOf(borrower._address)).to.be.lt(borrowerInitialBal);
        });
    });

    // Test: Collateral Model checks
    describe("After borrowing we check for max debt ratio and account liquidity", () => {
        // Checks `debtRatio()`
        it("Borrower has 100% debt ratio", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower } = await loadFixture(deployFixure);

            // False
            expect(await collateral.getDebtRatio(borrower._address)).to.equal(BigInt(1e18));
        });

        // Checks `accountLiquidity()`
        it("Borrower has 0 account liquidity", async () => {
            // Fixture
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(borrower._address);

            // Check that the borrower's liquidity and shortfall are now 0
            expect(liquidity).to.be.equal(0);
            expect(shortfall).to.be.equal(0);
        });
    });

    describe("Checks default interest rate variables with 0% borrowRate", () => {
        // borrowRate()
        it("Should have 0% borrowAPR", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Check borrow APR is 0
            expect(await borrowable.borrowRate()).to.equal(0);
        });

        // utilizationRate()
        it("Should store the correct utilization rate", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Calculate manually
            const totalBorrows = await borrowable.totalBorrows();
            const totalBalance = await borrowable.totalBalance();
            const util = totalBorrows.mul(ONE).div(totalBalance.add(totalBorrows));

            // Get util
            const utilizationRate = await borrowable.utilizationRate();

            // Check borrow APR is 0
            expect(util).to.equal(utilizationRate);
        });

        // baseRatePerSecond()
        it("Should have 0% baseRatePerSecond", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Check borrow APR is 0
            expect(await borrowable.baseRatePerSecond()).to.equal(0);
        });

        // multiplierPerSecond()
        it("Should have 0% multiplierPerSecond", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Check borrow APR is 0
            expect(await borrowable.multiplierPerSecond()).to.equal(0);
        });

        // jumpMultiplierPerSecond()
        it("Should have 0% jumpMultiplierPerSecond", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Check borrow APR is 0
            expect(await borrowable.jumpMultiplierPerSecond()).to.equal(0);
        });

        // borrowIndex()
        it("Should have initial borrowIndex of 1e18", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Check borrow APR is 0
            expect(await borrowable.borrowIndex()).to.equal(BigInt(1e18));
        });

        // accrueInterest()
        it("Accrues interest and emits an {AccrueInterest} event but does not accrue", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            // Check borrow APR is 0
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");
        });
    });

    // Set interest rate model and accrue
    describe("Sets an interest rate curve and accrues interest rate to lenders", () => {
        // test: setInterestRateModel();
        it("Sets a new interest rate curve and emits {NewInterestRateModel}", async () => {
            // Fixture
            const { owner, borrowable } = await loadFixture(deployFixure);

            const baseRate = BigInt(0.01e18); // 1%;
            const multiplier = BigInt(0.14e18); // 14%;
            const kinkMultiplier = 2;

            await expect(
                borrowable.connect(owner).setInterestRateModel(baseRate, multiplier, kinkMultiplier, BigInt(0.75e18)),
            )
                .to.emit(borrowable, "NewInterestRateParameters") // Check event log
                .withArgs(baseRate, multiplier, 2, BigInt(0.75e18)); // Verify event log params with baseRate, multiplier, kinkMultiplier and util
        });

        // TEST: Accrues interest to totalBorrows
        it("Accrues interest rate to borrows and reserves - increases `totalBorrows` and `borrowIndex`", async () => {
            // Fixture
            const { owner, borrowable } = await loadFixture(deployFixure);

            const baseRate = BigInt(0.01e18); // 1%;
            const multiplier = BigInt(0.14e18); // 14%;
            const kinkMultiplier = 2;
            await borrowable.connect(owner).setInterestRateModel(baseRate, multiplier, kinkMultiplier, BigInt(0.75e18));

            //
            // ACCRUE
            //
            // emit AccrueInterest(cashStored, interestAccumulated, borrowIndexStored, totalBorrowsStored, borrowRateStored);
            const borrowIndex = await borrowable.borrowIndex();
            const totalBorrows = await borrowable.totalBorrows();
            const totalBalance = await borrowable.totalBalance();

            // Accrue
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            expect(await borrowable.totalBorrows()).to.be.gt(totalBorrows);
            expect(await borrowable.borrowIndex()).to.be.gt(borrowIndex);
            expect(await borrowable.totalBalance()).to.be.equal(totalBalance);
        });

        it("Sets a new `borrowRate` on each accrual", async () => {
            // Fixture
            const { owner, borrowable } = await loadFixture(deployFixure);

            const baseRate = BigInt(0.01e18); // 1%;
            const multiplier = BigInt(0.14e18); // 14%;
            const kinkMultiplier = 2;
            await borrowable.connect(owner).setInterestRateModel(baseRate, multiplier, kinkMultiplier, BigInt(0.75e18));

            //
            // ACCRUE
            //
            // BorrowAPR is correc
            const borrowApr = await borrowable.borrowRate();

            // Accrue
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            const borrowAprAfterAccrue = await borrowable.borrowRate();

            // New borrowRate  after accrue
            expect(borrowAprAfterAccrue).to.be.gt(borrowApr);
        });

        // TEST: Accrues interest to totalBorrows
        it("Increases time 1 year and checks that interest accrued to `totalBorrows` is the same as the BorrowAPR", async () => {
            // Fixture
            const { owner, borrowable } = await loadFixture(deployFixure);

            // Initial
            const baseRate = BigInt(0.01e18); // 1%;
            const multiplier = BigInt(0.14e18); // 14%;
            const kinkMultiplier = 2;
            await borrowable.connect(owner).setInterestRateModel(baseRate, multiplier, kinkMultiplier, BigInt(0.75e18));
            // Sync to get new interest rate
            await borrowable.sync();

            // Borrows before 1 year increase
            const borrowsPrior = await borrowable.totalBorrows();

            // Increase time by 1 year
            await time.increase(24 * 60 * 60 * 365);

            // Accrue interest
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            // Borrows before 1 year increase
            const borrowRateAfter = await borrowable.borrowRate();
            const oneYear = ethers.BigNumber.from(24 * 60 * 60 * 365);

            const _after = ethers.BigNumber.from(borrowRateAfter);

            // Total Borrows after 1 year accrue should be equal to:
            // totalBorrowsBeforeAccrue * (1 + borrowAPR)
            expect(await borrowable.totalBorrows()).to.equal(borrowsPrior.mul(ONE.add(_after.mul(oneYear))).div(ONE));
        });

        // TEST: Accrues interest to totalBorrows
        it("Increases time 1 year and checks that borrower's balance increases by borrowAPR", async () => {
            // Fixture
            const { borrower, owner, borrowable } = await loadFixture(deployFixure);

            // Initial
            const baseRate = BigInt(0.01e18); // 1%;
            const multiplier = BigInt(0.14e18); // 14%;
            const kinkMultiplier = 2;
            await borrowable.connect(owner).setInterestRateModel(baseRate, multiplier, kinkMultiplier, BigInt(0.75e18));
            // Sync to get new interest rate
            await borrowable.sync();

            // Borrows before 1 year increase
            const accountBorrows = await borrowable.getBorrowBalance(borrower._address);

            // Increase time by 1 year
            await time.increase(24 * 60 * 60 * 365);

            // Accrue interest
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            const accountBorrowsAfter = await borrowable.getBorrowBalance(borrower._address);

            const borrowRate = await borrowable.borrowRate(); // Why this doesn't work O.o ???????
            const borrowRateBN = ethers.BigNumber.from(borrowRate); // Make BN for some reason
            const oneYear = ethers.BigNumber.from(24 * 60 * 60 * 365);

            // Expect new borrow balance to be gt before
            expect(accountBorrowsAfter).to.be.gt(accountBorrows);

            // Expect the new borrow balance to be equal to prior borrow balance * (1 + borrowAPR)
            expect(accountBorrowsAfter).to.be.closeTo(
                accountBorrows.mul(ONE.add(borrowRateBN.mul(oneYear))).div(ONE),
                BigInt(1),
            );
        });
    });
});
