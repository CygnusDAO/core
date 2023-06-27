// JS
const path = require("path");
// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;
// const { mine } = require("@nomicfoundation/hardhat-network-helpers")

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

/**
 *  Borrow Allowance
 */
describe("BorrowAllowance Tests", function () {
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

        // Return an object containing the various contracts, users, and initial balances for testing
        return {
            factory, // Factory
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
        await collateral.connect(owner).deposit(BigInt(2e18), owner.address, permit, signature);
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
            const { owner, collateral, lpToken, borrowerInitialBal } = await loadFixture(deployFixure);

            // Check balance of CygLP
            expect(await collateral.balanceOf(owner.address)).to.be.gt(0);

            // Check balance of LP
            expect(await lpToken.balanceOf(owner.address)).to.be.lt(borrowerInitialBal);
        });
    });

    // TEST: BORROW
    describe("Borrower borrows stablecoin from borrowable", () => {
        // Check borrow() at the router
        it("Should revert if borrowing with the router without borrow allowance", async () => {
            // Fixture
            const { router, borrowable, collateral, owner } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(owner.address);

            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            // Should revert
            await expect(router.connect(owner).borrow(borrowable.address, liquidity, owner.address, MaxUint256, "0x")).to.be.reverted;
        });

        // Check borrow() at the router
        it("Should revert if someone else is borrowing other than borrower without borrow allowance", async () => {
            // Fixture
            const { router, borrowable, collateral, owner, lender } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(owner.address);

            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            await expect(router.connect(lender).borrow(borrowable.address, liquidity, owner.address, MaxUint256, "0x")).to.be.reverted;
            await expect(router.connect(lender).borrow(borrowable.address, liquidity, lender._address, MaxUint256, "0x")).to.be.reverted;
            await expect(borrowable.connect(lender).borrow(owner.address, owner.address, liquidity, "0x")).to.be.reverted;
        });

        // Check borrow() in core
        it("Should succeed if owner borrows from the core contract without borrow approval set", async () => {
            // Fixture
            const { borrowable, collateral, owner } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(owner.address);

            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            // Should revert
            await expect(borrowable.connect(owner).borrow(owner.address, owner.address, liquidity, "0x")).to.emit(borrowable, "Borrow");
        });

        // borrowApprove()
        it("Should succeed when borrowing with the router having borrow allowance", async () => {
            // Fixture
            const { router, borrowable, collateral, owner } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(owner.address);

            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            await borrowable.connect(owner).approve(router.address, MaxUint256);

            // Should succeed
            await expect(router.connect(owner).borrow(borrowable.address, liquidity, owner.address, MaxUint256, "0x")).to.emit(
                borrowable,
                "Borrow",
            );
        });

        // borrowApprove()
        it("Should increase allowance with `borrowApprove`", async () => {
            // Fixture
            const { router, borrowable, owner } = await loadFixture(deployFixure);

            const allowanceBefore = await borrowable.allowance(owner.address, router.address);

            await borrowable.connect(owner).approve(router.address, MaxUint256);

            expect(await borrowable.allowance(owner.address, router.address)).to.be.gt(allowanceBefore);
        });

        // borrowPermit()
        it("Should increase allowance with `borrowPermit` ", async () => {
            // Fixture
            const { router, borrowable, collateral, owner } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(owner.address);

            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            const allowanceBefore = await borrowable.allowance(owner.address, router.address);

            // DOMAIN
            const _name = await borrowable.name();
            const _chainId = await owner.getChainId();
            const _verifyingContract = await borrowable.address;

            const domain = {
                name: _name,
                version: "1",
                chainId: _chainId,
                verifyingContract: _verifyingContract,
            };

            // TYPES
            const types = {
                Permit: [
                    { name: "owner", type: "address" },
                    { name: "spender", type: "address" },
                    { name: "value", type: "uint256" },
                    { name: "nonce", type: "uint256" },
                    { name: "deadline", type: "uint256" },
                ],
            };

            // VALUES
            const _nonce = await borrowable.nonces(owner.address);

            const values = {
                owner: owner.address,
                spender: router.address,
                value: liquidity,
                nonce: _nonce,
                deadline: MaxUint256,
            };

            const signature = await owner._signTypedData(domain, types, values);

            const { v, r, s } = await ethers.utils.splitSignature(signature);

            await borrowable.connect(owner).permit(owner.address, router.address, liquidity, MaxUint256, v, r, s);

            const allowanceAfter = await borrowable.allowance(owner.address, router.address);

            expect(allowanceAfter).to.be.gt(allowanceBefore);
        });

        // borrowPermit()
        it("Should revert when attempting to give ourselves borrow allowance over another borrower ", async () => {
            // Fixture
            const { borrower, borrowable, collateral, owner } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(owner.address);

            // No shortfall
            expect(shortfall).to.equal(0);

            // Check there's enough balance in borrowable first
            const usdBal = await borrowable.totalBalance();
            expect(usdBal).to.be.gt(liquidity);

            // DOMAIN
            const _name = await borrowable.name();
            const _chainId = await owner.getChainId();
            const _verifyingContract = await borrowable.address;
            const domain = {
                name: _name,
                version: "1",
                chainId: _chainId,
                verifyingContract: _verifyingContract,
            };

            // TYPES
            const types = {
                Permit: [
                    { name: "owner", type: "address" },
                    { name: "spender", type: "address" },
                    { name: "value", type: "uint256" },
                    { name: "nonce", type: "uint256" },
                    { name: "deadline", type: "uint256" },
                ],
            };

            // VALUES
            const _nonce = await borrowable.nonces(owner.address);
            const values = {
                owner: borrower._address,
                spender: owner.address,
                value: liquidity,
                nonce: _nonce,
                deadline: MaxUint256,
            };

            // Sign
            const signature = await owner._signTypedData(domain, types, values);

            const { v, r, s } = await ethers.utils.splitSignature(signature);

            await expect(borrowable.connect(owner).permit(borrower._address, owner.address, liquidity, MaxUint256, v, r, s)).to.be
                .reverted;
        });
    });
});
