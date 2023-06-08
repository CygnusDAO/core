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
// const ONE = ethers.utils.parseUnits("1", 18);

/**
 *  FIXTURE:
 *  -> Lender deposits USD
 *  -> Borrower deposits LP
 *  -> Borrower max borrows putting their debt raito at 100% (not liquidatable yet)
 *  -> We mine blocks and `accrueInterest`, now borrower has shortfall and is over 100% debt ratio
 */
describe("Cygnus Liquidations Integration Test", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    const deployFixure = async () => {
        // Make lending pool and collateral
        const [, factory, router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, , , lender, borrower] = await Users();

        // Set BorrowAPR to 0% first
        await borrowable.connect(owner).setInterestRateModel(BigInt(0.01e18), BigInt(0.15e18), 2, BigInt(0.8e18));

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

        // Approve router
        await factory.connect(borrower).setMasterBorrowApproval(router.address);
        // Get the current liquidity of the borrower's account
        const { liquidity } = await collateral.getAccountLiquidity(borrower._address);
        // Borrow the maximum amount possible from the borrowable token
        await router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, MaxUint256, "0x");

        // Get rewarder address
        const rewarderAddress = await borrowable.cygnusBorrowRewarder();

        const rewarder = await ethers.getContractAt("CygnusComplexRewarder", rewarderAddress);

        // Mine
        await mine(100);

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
            chainId, // Chain ID of the network being tested
            lenderInitialBal, // Initial balance of the lender's USDC before CYG
            borrowerInitialBal, // Initial balance of the borrower's LP tokens before CYG
            permit2, // Permit2 contract instance
            rewarder, // Cyg Rewarder
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
        await collateral.connect(owner).deposit(BigInt(2e18), borrower._address, permit, signature);
    };

    /**
     *  BEGIN TESTS
     */
    describe("------------------- Begin Test -------------------", () => {
        it("...begins...", async () => await loadFixture(deployFixure));
    });

    describe("The Rewarder should be tracking the borrower", () => {
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

        // getUserInfo()
        it("Should track the borrower after borrowing", async () => {
            // Fixture
            const { rewarder, borrower, borrowable } = await loadFixture(deployFixure);

            // User Info struct
            const userInfo = await rewarder.getUserInfo(borrowable.address, borrower._address);

            // Expect user to have shares
            expect(userInfo.shares).to.be.gt(0);
        });

        // pendingCyg()
        it("Should have pending CYG available", async () => {
            // Fixture
            const { rewarder, borrower, borrowable } = await loadFixture(deployFixure);

            const pending = await rewarder.pendingCyg(borrowable.address, borrower._address);

            // Expect user to have shares
            expect(pending).to.be.gt(0);
        });

        // collect()
        it("Should collect CYG and emit {Collect} event", async () => {
            // Fixture
            const { rewarder, borrower, borrowable } = await loadFixture(deployFixure);

            // Collect
            await expect(rewarder.connect(borrower).collect(borrowable.address, borrower._address)).to.emit(
                rewarder,
                "CollectReward",
            );
        });

        // epochRewardsPacing()
        it("Should be at 100% pacing after collecting", async () => {
            // Fixture
            const { rewarder, borrower, borrowable } = await loadFixture(deployFixure);

            await rewarder.accelerateTheUniverse();
            // Collect
            await expect(rewarder.connect(borrower).collect(borrowable.address, borrower._address)).to.emit(
                rewarder,
                "CollectReward",
            );

            const pacing = await rewarder.epochRewardsPacing();
            console.log(pacing);
        });
    });
});
