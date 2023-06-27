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

// Constants
const { MaxUint256 } = ethers.constants;

// Permit2
const {
    PERMIT2_ADDRESS,
    AllowanceTransfer,
    SignatureTransfer,
    MaxAllowanceExpiration,
} = require("@uniswap/permit2-sdk");

const permit2Abi = require(path.resolve(__dirname, "../../scripts/abis/permit2.json"));

/**
 *  FIXTURE:
 *  -> Lender deposits USD
 *  -> Borrower deposits LP
 *  -> Borrower approves router in factory
 *  -> Borrower takes out max loan putting their debt ratio at 100%
 *  -> Borrower repays loan with:
 *       - Repays borrow with permit2 signature
 *       - Repays borrow with permit2 allowance
 *       - Repays borrow wihtout permit2
 *       - Repays full loan and updates correctly
 *       - Repays half the loan and updates correctly
 */
describe("Repay loans", function () {
    // Deploy fixture
    const deployFixure = async () => {
        // Make lending pool and collateral
        const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, daoReserves, , lender, borrower] = await Users();

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

        const baseRate = BigInt(0.01e18); // 1%;
        const multiplier = BigInt(0.14e18); // 14%;
        const kinkMultiplier = 2;

        await borrowable.connect(owner).setInterestRateModel(baseRate, multiplier, kinkMultiplier, BigInt(0.75e18));
        await borrowable.sync();

        await borrowable.connect(owner).borrowApprove(router.address, ethers.constants.MaxUint256);

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
            daoReserves, // DAO Reserves (address we mint reserves to)
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

    describe("User has taken out a USDC loan and repays it back after 1 year", () => {
        // Test: accrue()
        it("Should accrue interest and emit {AccrueInterest}", async () => {
            // Load fixture data
            const { borrowable } = await loadFixture(deployFixure);

            // Get total protocol borrows
            const totalBorrowsBefore = await borrowable.totalBorrows();

            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            const totalBorrowsAfter = await borrowable.totalBorrows();

            expect(totalBorrowsAfter).to.be.gt(totalBorrowsBefore);
        });

        // test: accrue()
        it("Should increase time by 1 day and accrue interest and emit {AccrueInterest}", async () => {
            // Load fixture data
            const { borrowable } = await loadFixture(deployFixure);

            // Get total protocol borrows
            const totalBorrowsBefore = await borrowable.totalBorrows();

            // Increase 1 day
            await time.increase(60 * 60 * 24);

            // Accrue
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            // Borrows after
            const totalBorrowsAfter = await borrowable.totalBorrows();

            expect(totalBorrowsAfter).to.be.gt(totalBorrowsBefore);
        });

        // test: accrue()
        it("Should increase time by 7 days and accrue interest and emit {AccrueInterest}", async () => {
            // Load fixture data
            const { borrowable } = await loadFixture(deployFixure);

            // Get total protocol borrows
            const totalBorrowsBefore = await borrowable.totalBorrows();

            // Increase 1 day
            await time.increase(60 * 60 * 24 * 7);

            // Accrue
            await expect(borrowable.accrueInterest()).to.emit(borrowable, "AccrueInterest");

            // Borrows after
            const totalBorrowsAfter = await borrowable.totalBorrows();

            expect(totalBorrowsAfter).to.be.gt(totalBorrowsBefore);
        });

        // Test: repay()
        it("Should have no leftover borrow balance", async () => {
            // Fixture
            const { lender, usdc, router, borrower, borrowable } = await loadFixture(deployFixure);

            // approve first
            await usdc.connect(borrower).approve(router.address, MaxUint256);

            // Max repay we set at 4k to test but router should never use the 4k if amount owed is less than this
            const repayAmount = BigInt(4000e6);

            // Transfer 10,000 USDC to borrower to be able to repay loan
            await usdc.connect(lender).transfer(borrower._address, BigInt(10000e6));

            // Repay - The repay function accrues interest before repaying so actualRepayAmount in the event emitted should always be a bit more
            await expect(
                router.connect(borrower).repay(borrowable.address, repayAmount, borrower._address, MaxUint256),
            ).to.emit(borrowable, "Borrow");

            // Expect no borrow balance left over
            expect(await borrowable.getBorrowBalance(borrower._address)).to.be.equal(0);
        });

        // Test: repay()
        it("Should have USDC balance decreased only by repaid amount (borrow balance)", async () => {
            // Fixture
            const { lender, usdc, router, borrower, borrowable } = await loadFixture(deployFixure);

            // approve first
            await usdc.connect(borrower).approve(router.address, MaxUint256);

            // Transfer 10,000 USDC to borrower to be able to repay loan
            await usdc.connect(lender).transfer(borrower._address, BigInt(10000e6));

            const usdBalanceBeforeRepay = await usdc.balanceOf(borrower._address);

            // Max repay we set at 4k to test but router should never use the 4k if amount owed is less than this
            const repayAmount = BigInt(4000e6);

            // Get borrow balance before repay
            const borrowBalance = await borrowable.getBorrowBalance(borrower._address);

            // Repay - The repay function accrues interest before repaying so actualRepayAmount in the event emitted should always be a bit more
            await expect(router.connect(borrower).repay(borrowable.address, repayAmount, borrower._address, MaxUint256))
                .to.emit(borrowable, "Borrow")
                .to.emit(borrowable, "AccrueInterest")
                .to.emit(borrowable, "Sync");

            const usdBalanceAfterRepay = await usdc.balanceOf(borrower._address);

            // New USD bal = usdBalanceBeforeRepay - borrowBalance
            // Account for interest accrued during the repay transaction
            expect(usdBalanceAfterRepay).to.be.closeTo(usdBalanceBeforeRepay.sub(borrowBalance), BigInt(0.00001e6));
        });

        // Test: repay()
        it("Should be able to repay only part of the borrowed amount", async () => {
            // Fixture
            const { lender, usdc, router, borrower, borrowable } = await loadFixture(deployFixure);

            // approve first
            await usdc.connect(borrower).approve(router.address, MaxUint256);

            await borrowable.accrueInterest();

            // Get borrow balance before repay
            const borrowBalance = await borrowable.getBorrowBalance(borrower._address);

            const half = await ethers.BigNumber.from(2);

            // Repays 50% of the debt
            const repayAmount = borrowBalance.div(half);

            // Transfer 10,000 USDC to borrower to be able to repay loan
            await usdc.connect(lender).transfer(borrower._address, BigInt(10000e6));

            // Repay - The repay function accrues interest before repaying so actualRepayAmount in the event emitted should always be a bit more
            await expect(router.connect(borrower).repay(borrowable.address, repayAmount, borrower._address, MaxUint256))
                .to.emit(borrowable, "Borrow")
                .to.emit(borrowable, "AccrueInterest")
                .to.emit(borrowable, "Sync");

            // Get borrow balance before repay
            const newBorrowBalance = await borrowable.getBorrowBalance(borrower._address);

            // Repay amount is 50% of preivous borrowBalance
            expect(newBorrowBalance).to.be.closeTo(repayAmount, BigInt(0.00001e6));
        });

        // Test: repay()
        it("Should repay half and accrue interest rate, sync, mint reserves", async () => {
            // Fixture
            const { lender, daoReserves, usdc, router, borrower, borrowable } = await loadFixture(deployFixure);

            // approve first
            await usdc.connect(borrower).approve(router.address, MaxUint256);

            // 1 year...
            await time.increase(24 * 60 * 60 * 365);

            await borrowable.accrueInterest();

            // Get borrow balance before repay
            const borrowBalance = await borrowable.getBorrowBalance(borrower._address);

            const half = await ethers.BigNumber.from(2);

            // Repays 50% of the debt
            const repayAmount = borrowBalance.div(half);

            // Transfer 10,000 USDC to borrower to be able to repay loan
            await usdc.connect(lender).transfer(borrower._address, BigInt(10000e6));

            // Get CygUSD balance of dao reserves before repay
            const reservesPrior = await borrowable.balanceOf(daoReserves.address);

            // Repay - The repay function accrues interest before repaying so actualRepayAmount in the event emitted should always be a bit more
            await expect(router.connect(borrower).repay(borrowable.address, repayAmount, borrower._address, MaxUint256))
                .to.emit(borrowable, "Borrow")
                .to.emit(borrowable, "AccrueInterest")
                .to.emit(borrowable, "Sync");

            // Syncing borrowable checks exchange rate and checks for shares to mint
            await borrowable.sync();

            // Get new CygUSD balance of dao reserves
            const reservesNew = await borrowable.balanceOf(daoReserves.address);

            // Expect new reserves to be minted
            expect(reservesNew).to.be.gt(reservesPrior);
        });

        // TEST: Repays with Permit2 Allowance
        it("Repays full amount with permit2 Allowance Transfer", async () => {
            // Load fixture data
            const { lender, owner, usdc, router, borrower, borrowable, permit2 } = await loadFixture(deployFixure);

            // Transfer 10,000 USDC to borrower to be able to repay loan
            await usdc.connect(lender).transfer(borrower._address, BigInt(10000e6));

            // Get the chain ID
            const _chainId = await owner.getChainId();

            // Repays full amount of 4k but not whole is used
            const repayAmount = BigInt(4000e6);

            // 1. Get the nonce for (owner -> usdc -> spender)
            const { nonce } = await permit2.allowance(owner.address, usdc.address, router.address);

            // 2. Build the permit
            const permit = {
                details: {
                    token: usdc.address,
                    amount: repayAmount, // Specify the amount to repay
                    expiration: MaxAllowanceExpiration, // Set the permit expiration
                    nonce: nonce, // Set the nonce obtained from step 1
                },
                spender: router.address, // Set the permit spender
                sigDeadline: MaxUint256, // Set the permit signature deadline
            };

            // 3. Sign the permit
            const permitData = AllowanceTransfer.getPermitData(permit, PERMIT2_ADDRESS, _chainId); // Get the permit data
            const signature = await owner._signTypedData(permitData.domain, permitData.types, permitData.values); // Sign the permit

            // 4. Repay with permit
            await expect(
                router
                    .connect(owner)
                    .repayPermit2Allowance(
                        borrowable.address,
                        repayAmount,
                        borrower._address,
                        MaxUint256,
                        permit,
                        signature,
                    ),
            )
                .to.emit(borrowable, "Borrow") // Check for borrow event
                .to.emit(borrowable, "AccrueInterest") // Check for accrue interest event
                .to.emit(borrowable, "Sync"); // Check for sync event

            // Check the borrower's new borrow balance
            const newBorrowBal = await borrowable.getBorrowBalance(borrower._address);
            expect(newBorrowBal).to.be.equal(0); // Expect 0 borrow balance
        });

        // TEST: Repays with Permit2 Signature
        it("Repays with permit2 Signature Transfer", async () => {
            // Load fixture data
            const { lender, owner, usdc, router, borrower, borrowable } = await loadFixture(deployFixure);

            // Transfer 10,000 USDC to borrower to be able to repay loan
            await usdc.connect(lender).transfer(borrower._address, BigInt(10000e6));

            // Get the chain ID
            const _chainId = await owner.getChainId();

            // Repays full amount of 4k but not whole is used
            const repayAmount = BigInt(4000e6);

            // 2. Build permit
            const permit = {
                permitted: {
                    token: usdc.address,
                    amount: repayAmount,
                },
                spender: router.address,
                nonce: 0,
                deadline: MaxUint256,
            };

            // 3. Sign the permit
            const permitData = SignatureTransfer.getPermitData(permit, PERMIT2_ADDRESS, _chainId); // Get the permit data
            const signature = await owner._signTypedData(permitData.domain, permitData.types, permitData.values); // Sign the permit

            await borrowable.sync();

            // 4. Repay with permit
            await expect(
                router
                    .connect(owner)
                    .repayPermit2Signature(
                        borrowable.address,
                        repayAmount,
                        borrower._address,
                        MaxUint256,
                        permit,
                        signature,
                    ),
            )
                .to.emit(borrowable, "Borrow") // Check for borrow event
                .to.emit(borrowable, "AccrueInterest") // Check for accrue interest event
                .to.emit(borrowable, "Sync"); // Check for sync event

            await borrowable.sync();

            // Check the borrower's new borrow balance
            const newBorrowBal = await borrowable.getBorrowBalance(borrower._address);
            expect(newBorrowBal).to.be.equal(0); // Expect 0 borrow balance
        });
    });
});
