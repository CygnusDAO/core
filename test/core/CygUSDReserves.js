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
        const [, factory, router, borrowable, collateral, usdc, lpToken] = await Make();

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

        // Deposit 100,000 USDC into the lending pool
        await lenderDeposit(owner, usdc, lender, borrowable, permit2);

        // Deposit 2 LP tokens into the collateral pool
        await borrowerDeposit(owner, lpToken, borrower, collateral, permit2);

        // Approve borrow
        await borrowable.connect(borrower).approve(router.address, ethers.constants.MaxUint256);

        // Borrow max Liquidity
        await borrowUsd(borrower, borrowable, collateral, router);

        // Return an object containing the various contracts, users, and initial balances for testing
        return {
            factory,
            router, // Router contract
            borrowable, // Lending pool contract
            collateral, // Collateral contract
            usdc, // USDC contract
            lpToken, // LP token contract
            owner, // Owner (admin) user
            lender, // Lender user
            borrower, // Borrower user
            permit2, // Permit2 contract instance
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
        await borrowable.connect(owner).deposit(BigInt(500e6), lender._address, permit, signature);
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

    describe("The DAO receives CygUSD according to the reserveFactor", () => {
        //        it("Mints CygUSD on `accrueInterest`", async () => {
        //            const { owner, factory, borrowable } = await loadFixture(deployFixure);
        //
        //            const daoReserves = await factory.daoReserves();
        //
        //            const reservesBalance = await borrowable.balanceOf(daoReserves);
        //
        //            await mine(200000);
        //            await expect(borrowable.connect(owner).accrueInterest()).to.emit(borrowable, "AccrueInterest");
        //
        //            const _reservesBalance = await borrowable.balanceOf(daoReserves);
        //
        //            expect(_reservesBalance).to.be.gt(reservesBalance);
        //        });
        //
        //        it("Mints CygUSD on `Sync`", async () => {
        //            const { owner, factory, borrowable } = await loadFixture(deployFixure);
        //
        //            const daoReserves = await factory.daoReserves();
        //
        //            const reservesBalance = await borrowable.balanceOf(daoReserves);
        //
        //            await mine(200000);
        //            await expect(borrowable.connect(owner).sync()).to.emit(borrowable, "Sync").to.emit(borrowable, "AccrueInterest");
        //
        //            const _reservesBalance = await borrowable.balanceOf(daoReserves);
        //
        //            expect(_reservesBalance).to.be.gt(reservesBalance);
        //        });

        it("Mints reserves according to the reserveFactor`", async () => {
            const { factory, lender, owner, borrowable } = await loadFixture(deployFixure);

            await expect(borrowable.connect(owner).sync()).to.emit(borrowable, "Sync");
            console.log("CYGUSD BAL OF BORROWER: %s", (await borrowable.balanceOf(lender._address)) / 1e6);
            console.log("------------------------------------------------------------------------");

            console.log("Total Supply : %s", (await borrowable.totalSupply()) / 1e6);
            console.log("Total Borrows: %s", (await borrowable.totalBorrows()) / 1e6);
            console.log("Total Balance: %s", (await borrowable.totalBalance()) / 1e6);
            console.log("Borrow Rate  : %s", ((await borrowable.borrowRate()) * (60 * 60 * 24 * 365)) / 1e16);
            console.log("Utilization  : %s", (await borrowable.utilizationRate()) / 1e16);
            await expect(borrowable.connect(owner).sync()).to.emit(borrowable, "Sync");

            console.log("------------------------------------------------------------------------");
            console.log("  MINE 1 Year  ");
            console.log("------------------------------------------------------------------------");

            for (let i = 0; i < 12; i++) {
                await time.increase(60 * 60 * 24 * 30);
                await borrowable.connect(owner).sync();
            }

          const daoReserves = await factory.daoReserves();
          console.log("Balance of Reserves: %s", await borrowable.balanceOf(daoReserves) / 1e6);
          console.log("Exchange Rate: %s", await borrowable.exchangeRate());

            console.log("Total Supply: %s", (await borrowable.totalSupply()) / 1e6);
            console.log("Total Borrows: %s", (await borrowable.totalBorrows()) / 1e6);
            console.log("Total Balance: %s", (await borrowable.totalBalance()) / 1e6);
            console.log("Borrow Rate  : %s", ((await borrowable.borrowRate()) * (60 * 60 * 24 * 365)) / 1e16);
            console.log("Utilization  : %s", (await borrowable.utilizationRate()) / 1e16);
            await expect(borrowable.connect(owner).sync()).to.emit(borrowable, "Sync");

        });
    });
});
