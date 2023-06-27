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

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");
const permit2Abi = require(path.resolve(__dirname, "../../scripts/abis/permit2.json"));

// Constants
const { MaxUint256 } = ethers.constants;
const ONE = ethers.utils.parseUnits("1", 18);

/**
 *  @notice Test the collateral model for borrowers which allows for LP depositors to borrow stablecoins
 *
 *      +----------------------------+------------------------------------------------------------+
 *      | Exchange Rate              | LP Tokens Balance / CygLP Supply                           |
 *      +----------------------------+------------------------------------------------------------+
 *      | Shares                     | Assets / Exchange Rate                                     |
 *      +----------------------------+------------------------------------------------------------+
 *      | Assets                     | Shares * Exchange Rate                                     |
 *      +----------------------------+------------------------------------------------------------+
 *      | Amount Collateral (in USD) | Assets * LP Price                                          |
 *      +----------------------------+------------------------------------------------------------+
 *      | Adjusted Borrowed Amount   | USD Borrows * (liquidationIncentive + liquidationFee)      |
 *      +----------------------------+------------------------------------------------------------+
 *      | Debt Ratio                 | Adjusted Borrowed Amount / (Amount Collateral * debtRatio) |
 *      +----------------------------+------------------------------------------------------------+
 *      | Account Liquidity          | (Amount Collateral * debtRatio) - Adjusted Borrowed Amount |
 *      +----------------------------+------------------------------------------------------------+
 *      | Account Shortfall          | Adjusted Borrowed Amount - (Amount Collateral * debtRatio) |
 *      +----------------------------+------------------------------------------------------------+
 *
 */
describe("Cygnus Collateral Model", function () {
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

    describe("Makes Cygnus Core", () => {
        // Load the initial test fixture to use in subsequent tests
        it("Should load fixture", async () => {
            await loadFixture(deployFixure);
        });
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

    describe("Assures the Collateral Model is correct and borrower has proper liquidity and debt ratio", () => {
        // The account liquidity is given by:
        //
        // Assets            = shares * exchange rate
        // Collateral in USD = assets * lpPrice
        // Account Liquidity = Collateral in USD / (Liquidation Penalty)
        it("Calculates correct account liquidity", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get the number of shares held by the borrower's address
            const shares = await collateral.balanceOf(borrower._address);

            // Get the exchange rate of the collateral token
            const exchangeRate = await collateral.exchangeRate();

            // Get the current price of the LP token for the collateral pool
            const lpPrice = await collateral.getLPTokenPrice();

            // Calculate the collateral held by the borrower in USD
            const collateralInUsd = shares.mul(exchangeRate).div(ONE).mul(lpPrice).div(ONE);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(borrower._address);

            // Get the current debt ratio of the collateral pool
            const debtRatio = await collateral.debtRatio();

            // Get the liquidation incentive and fee for the collateral pool
            const liqIncentive = await collateral.liquidationIncentive();
            const liqFee = await collateral.liquidationFee();
            const liqPenalty = liqIncentive.add(liqFee);

            // Adjust the collateral value based on the debt ratio and liquidation value
            const _liquidity = collateralInUsd.mul(debtRatio).div(ONE).mul(ONE).div(liqPenalty);

            // Check that our calculated liquidity matches the actual account liquidity
            expect(_liquidity).to.equal(liquidity);

            // No shortfall
            expect(shortfall).to.equal(0);
        });

        // Debt raito before borrows
        it("Has 0 debt ratio before borrows", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get the debt ratio of the borrower's account
            const { health } = await collateral.getBorrowerPosition(borrower._address);

            // Check that the debt ratio is 0
            expect(health).to.equal(0);
        });

        // Max Redeem amount with no borrows
        it("Can redeem all shares before borrows", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get the number of shares held by the borrower's address
            const shares = await collateral.balanceOf(borrower._address);

            // Check that the borrower can redeem all of their shares
            expect(await collateral.canRedeem(borrower._address, shares)).to.equal(true);

            // Check for rounding
            const roundToken = BigInt(2);
            // Add round token
            expect(await collateral.canRedeem(borrower._address, shares.add(roundToken))).to.equal(false);
        });

        // Max Borrow amount = Account Liquidity
        it("Calculates the correct max borrow amount", async () => {
            // Load the fixture to get the collateral and borrower objects
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get the current liquidity of the borrower's account
            const { liquidity, shortfall } = await collateral.getAccountLiquidity(borrower._address);

            // Adjust liquidity amount for roudning error
            const roundToken = BigInt(2);

            // Check that the borrower can borrow up to their current liquidity amount
            expect(await collateral.canBorrow(borrower._address, liquidity)).to.equal(true);

            // Check that the borrower cannot borrow more than their current liquidity amount
            expect(await collateral.canBorrow(borrower._address, liquidity.add(roundToken))).to.equal(false);

            // Check that the borrower can borrow less than their current liquidity amount
            expect(await collateral.canBorrow(borrower._address, liquidity.sub(roundToken))).to.equal(true);

            // No shortfall
            expect(shortfall).to.equal(0);
        });
    });
});
