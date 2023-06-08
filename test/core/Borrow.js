// JS
const path = require("path");
// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

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

// TODO: `canRedeem` can suffer from small amounts of unlocked tokens due to losing decimal precision
//       since usdc having 6 decimanls and lps 18. Should in theory add an extra check on core. Important
//       for transfers/burns too.
/**
 *  @notice Borrower does a simple borrow
 *  @notice As described in `ModelCollateral.js`
 *
 *      +----------------------------+------------------------------------------------------------+
 *      | Amount Collateral (in USD) | Assets * LP Price                                          |
 *      +----------------------------+------------------------------------------------------------+
 *      | Adjusted Borrowed Amount   | USD Borrows * (liquidationIncentive + liquidationFee)      |
 *      +----------------------------+------------------------------------------------------------+
 *      | Account Liquidity          | (Amount Collateral * debtRatio) - Adjusted Borrowed Amount |
 *      +----------------------------+------------------------------------------------------------+
 *      | Account Shortfall          | Adjusted Borrowed Amount - (Amount Collateral * debtRatio) |
 *      +----------------------------+------------------------------------------------------------+
 *
 *      To calculate max borrow then:
 *      +----------------------------+------------------------------------------------------------+
 *      | Max Borrow                 | (Amount Collateral * Debt Ratio) / Liquidation Penalty     |
 *      +----------------------------+------------------------------------------------------------+
 */
describe("Borrow Integration Tests", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    const deployFixure = async () => {
        // Make lending pool and collateral
        const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

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

        await borrowable.connect(borrower).borrowApprove(router.address, ethers.constants.MaxUint256);

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
        await borrowable.connect(owner).deposit(BigInt(100000e6), lender._address, permit, signature);
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
                amount: BigInt(4e18),
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
        await lpToken.connect(borrower).transfer(owner.address, BigInt(4e18));

        // 4. Owner deposits using borrower address
        await collateral.connect(owner).deposit(BigInt(4e18), borrower._address, permit, signature);
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

    // TEST: BORROW
    describe("Borrower borrows stablecoin from borrowable", () => {
        // Check: `borrow()`
        it("Should revert if user has 0 CygLP (== no liquidity)", async () => {
            // Fixture
            const { router, borrowable, collateral, safeAddress1 } = await loadFixture(deployFixure);

            // Shares for safeAddress (should be 0)
            const shares = await collateral.balanceOf(safeAddress1.address); // CygLP
            expect(shares).to.be.equal(0);

            // Should revert with no liquidity error
            await expect(router.connect(safeAddress1).borrow(borrowable.address, BigInt(1), safeAddress1.address, MaxUint256, "0x")).to.be
                .reverted;

            // Should revert with no liquidity error
            await expect(router.connect(safeAddress1).borrow(borrowable.address, BigInt(1000e6), safeAddress1.address, MaxUint256, "0x")).to
                .be.reverted;
        });

        // CHECK: `borrow()`
        it("Should revert if borrowing more than their liquidity", async () => {
            // Fixture
            const { router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            //
            // Make sure calculations hold up
            //
            // Calculate the collateral held by the borrower in USD
            const shares = await collateral.balanceOf(borrower._address); // CygLP
            const exchangeRate = await collateral.exchangeRate(); // Balance / Supply
            const lpPrice = await collateral.getLPTokenPrice(); // Asset Price
            const collateralInUsd = shares.mul(exchangeRate).div(ONE).mul(lpPrice).div(ONE);

            // Get the liquidation incentive and fee for the collateral pool
            const liqIncentive = await collateral.liquidationIncentive();
            const liqFee = await collateral.liquidationFee();
            const liqPenalty = liqIncentive.add(liqFee);
            const debtRatio = await collateral.debtRatio();
            const _liquidity = collateralInUsd.mul(debtRatio).div(ONE).mul(ONE).div(liqPenalty);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(borrower._address);

            // Check that our calculated liquidity matches the actual account liquidity
            expect(_liquidity).to.equal(liquidity);
            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity.add(BigInt(1)), borrower._address, MaxUint256, "0x"))
                .to.be.reverted; // Max Deadline and no permit
        });

        // Check `borrow()`
        it("Should borrow and receive USDC if borrower has enough liquidity", async () => {
            // Fixture
            const { usdc, router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Check there's enough balance first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity); // Expect that the total balance of borrowable is > than borrower's liquidity

            const usdBalBefore = await usdc.balanceOf(borrower._address); // Get the USDC balance of the borrower's account before borrowing

            // Borrow the maximum amount possible from the borrowable token
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow") // Check `Borrow` event was emitted
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0);

            const usdBalAfter = await usdc.balanceOf(borrower._address); // Get the USDC balance of the borrower's account after borrowing
            const { liquidity: _liquidity, shortfall: _shortfall } = await collateral.getAccountLiquidity(borrower._address); // Get the current liquidity and shortfall of the borrower's collateral account

            // Check that the borrower received the correct amount of USDC
            expect(usdBalAfter.sub(usdBalBefore)).to.be.equal(liquidity);

            // Check that the borrower's liquidity and shortfall are now 0
            expect(_liquidity).to.be.equal(0);
            expect(_shortfall).to.be.equal(0);

            // Check that borrowable is storing borrower's borrow correctly
            const borrowBal = await borrowable.getBorrowBalance(borrower._address);
            expect(borrowBal).to.be.equal(liquidity);
        });

        // Checks `debtRatio()`
        it("Borrows full liquidity and has 100% debt ratio", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0); // No repay amount

            // False
            expect(await collateral.getDebtRatio(borrower._address)).to.equal(BigInt(1e18));
        });
    });

    describe("Collateral should be locked from transfers/burns after max borrow", () => {
        // Read the TODO at the top - This is currently subject to precision loss accuracy due to
        // the difference in decimals from borrowable and collateral.
        it("`canRedeem` should return false for any significant amount of shares", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0); // No repay amount

            // False
            expect(await collateral.canRedeem(borrower._address, BigInt(0.000001e18))).to.be.equal(false);
        });

        // Check: `canBorrow()`
        it("`canBorrow` should return false for any new amount + previous borrow", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0); // No repay amount

            const borrowBal = await borrowable.getBorrowBalance(borrower._address);
            expect(borrowBal).to.be.equal(liquidity);

            // False
            expect(await collateral.canBorrow(borrower._address, borrowBal.add(BigInt(1)))).to.be.equal(false);
            expect(await collateral.canBorrow(borrower._address, borrowBal.add(BigInt(2)))).to.be.equal(false);
            expect(await collateral.canBorrow(borrower._address, borrowBal.add(BigInt(100e18)))).to.be.equal(false);
        });

        // Check: `borrow()`
        it("Should revert after borrowing max borrow and attempting to borrow any amount again", async () => {
            // Fixture
            const { usdc, router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Check there's enough balance first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity); // Expect that the total balance of borrowable is > than borrower's liquidity

            const usdBalBefore = await usdc.balanceOf(borrower._address); // Get the USDC balance of the borrower's account before borrowing

            // Borrow the maximum amount possible from the borrowable token
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow") // Check `Borrow` event was emitted
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0);

            const usdBalAfter = await usdc.balanceOf(borrower._address); // Get the USDC balance of the borrower's account after borrowing
            const { liquidity: _liquidity, shortfall: _shortfall } = await collateral.getAccountLiquidity(borrower._address);

            // Check that the borrower received the correct amount of USDC
            expect(usdBalAfter.sub(usdBalBefore)).to.be.equal(liquidity);

            // Check that the borrower's liquidity and shortfall are now 0
            expect(_liquidity).to.be.equal(0);
            expect(_shortfall).to.be.equal(0);

            // Check that borrowable is storing borrower's borrow correctly
            const borrowBal = await borrowable.getBorrowBalance(borrower._address);
            expect(borrowBal).to.be.equal(liquidity);

            //
            // Second borrow
            //
            await expect(router.connect(borrower).borrow(borrowable.address, BigInt(19000e6), borrower._address, MaxUint256, "0x")).to.be
                .reverted;

            // Min USDC unit
            await expect(router.connect(borrower).borrow(borrowable.address, BigInt(1), borrower._address, MaxUint256, "0x")).to.be
                .reverted;
        });

        // Test: `transfer()`
        it("Should not be able to transfer CygLP if it would put their account in shortfall", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower, safeAddress1 } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0);

            // Get debt ratio, should be 100%
            const debtRatio = await collateral.getDebtRatio(borrower._address);
            expect(debtRatio).to.be.equal(BigInt(1e18));

            await expect(collateral.connect(borrower).transfer(safeAddress1.address, BigInt(0.1e18))).to.be.reverted;
            await expect(collateral.connect(borrower).transfer(safeAddress1.address, BigInt(1e18))).to.be.reverted;
            await expect(collateral.connect(borrower).transfer(safeAddress1.address, BigInt(2e18))).to.be.reverted;
            await expect(collateral.connect(borrower).transfer(safeAddress1.address, BigInt(4e18))).to.be.reverted;
        });

        // Test: `transfer()`
        it("Should be able to transfer CygLP if they have 0 borrows", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower, safeAddress1 } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            await expect(collateral.connect(borrower).transfer(safeAddress1.address, liquidity)).to.emit(collateral, "Transfer");
        });

      //Transfer test: transferFrom()
        it("Should be able to give allowance to another address and use `transferFrom` when they have 0 borrows", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower, safeAddress1 } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Approve safe address
            await expect(collateral.connect(borrower).approve(safeAddress1.address, BigInt(1000000e18))).to.emit(collateral, "Approval");

            //
            await expect(collateral.connect(safeAddress1).transferFrom(borrower._address, safeAddress1.address, liquidity)).to.emit(
                collateral,
                "Transfer",
            );
        });

        // Test: `transferFrom()`
        it("Should not be able to give allowance to others to transfer their CygLP through `transferFrom` if it would put their account in shortfall", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower, safeAddress1 } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Approve safe address
            await expect(collateral.connect(borrower).approve(safeAddress1.address, BigInt(1000000e18))).to.emit(collateral, "Approval");

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0);

            // Get debt ratio, should be 100%
            const debtRatio = await collateral.getDebtRatio(borrower._address);
            expect(debtRatio).to.be.equal(BigInt(1e18));

            // Should not be able to do this
            await expect(collateral.connect(safeAddress1).transferFrom(borrower._address, safeAddress1.address, BigInt(0.1e18))).to.be
                .reverted;
        });

        // TEST: redeem()
        it("Should not be able to redeem CygLP for LP if it would put their account in shortfall", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0);

            // Get debt ratio, should be 100%
            const debtRatio = await collateral.getDebtRatio(borrower._address);
            expect(debtRatio).to.be.equal(BigInt(1e18));

            await expect(collateral.connect(borrower).redeem(BigInt(0.0000001e18), borrower._address, borrower._address)).to.be.reverted;
            await expect(collateral.connect(borrower).redeem(BigInt(1e18), borrower._address, borrower._address)).to.be.reverted;

            await expect(collateral.connect(borrower).redeem(BigInt(2e18), borrower._address, borrower._address)).to.be.reverted;

            await expect(collateral.connect(borrower).redeem(BigInt(4e18), borrower._address, borrower._address)).to.be.reverted;
        });

        it("Should accrue interest if there are borrows", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { router, borrowable, collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity } = await collateral.getAccountLiquidity(borrower._address);

            // Should revert
            await expect(router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x"))
                .to.emit(borrowable, "Borrow")
                .withArgs(router.address, borrower._address, borrower._address, liquidity, 0);

            await mine(100);
            await expect(borrowable.connect(borrower).accrueInterest()).to.emit(borrowable, "AccrueInterest");
        });
    });
});
