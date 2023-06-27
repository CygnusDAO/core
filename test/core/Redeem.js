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

/**
 *  @notice Second borrower and lender tests
 *          - Second Borrower deposits 2 LPs, receives 2 CygLP and redeems exactly 2 LPs
 *          - Second Lender deposits 100,000 USDC and receives close to 100,000 CygUSD due to strategy's
 *            interest accrual
 *          - Lender then redeems and receives AT LEAST 100,000 USDC back
 */
describe("Redeem Borrowable (CygUSD) for USDC and Collateral (CygLP) for LP", function () {
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

    // Test: Redeem
    describe("Lender redeems CygUSD shares", () => {
        it("Reverts if withdrawing shares and msg.sender is not owner of shares and has no allowance", async () => {
            // Fixture
            const { owner, borrowable, lender } = await loadFixture(deployFixure);

            // Owner redeems 0 lender shares to themselves
            await expect(borrowable.connect(owner).redeem(BigInt(1e6), owner.address, lender._address)).to.be.reverted;
        });

        it("Reverts if withdrawing 0 shares", async () => {
            // Fixture
            const { borrowable, lender } = await loadFixture(deployFixure);

            // Lender redeems 0 shares
            await expect(borrowable.connect(lender).redeem(0, lender._address, lender._address)).to.be.reverted;
        });

        it("Reverts if withdrawing 0 shares and msg.sender is not owner of shares but has allowance", async () => {
            // Fixture
            const { owner, borrowable, lender } = await loadFixture(deployFixure);

            // Approve first
            await borrowable.connect(lender).approve(owner.address, BigInt(1000e6));

            // Shouldnt be able to redeem 0
            await expect(borrowable.connect(owner).redeem(0, owner.address, lender._address)).to.be.reverted;
        });

        it("Succeeds when owner withdraws shares for assets", async () => {
            // Fixture
            const { borrowable, lender } = await loadFixture(deployFixure);

            // Get shares of lender
            const shares = await borrowable.balanceOf(lender._address);

            // Lender redeems and receives assets
            await expect(borrowable.connect(lender).redeem(shares, lender._address, lender._address))
                .to.emit(borrowable, "Withdraw") // check that a Withdraw event was emitted
                .to.emit(borrowable, "Sync"); // check that a Sync event was emitted
        });

        it("Succeeds when msg.sender redeems owner shares with enough allowance", async () => {
            // Fixture
            const { owner, borrowable, lender } = await loadFixture(deployFixure);

            // Approve lender's transfer of shares to owner
            await borrowable.connect(lender).approve(owner.address, BigInt(1000000e18));

            // Get the number of shares the lender has
            const shares = await borrowable.balanceOf(lender._address);

            // Owner redeems and receives lender`s shares
            await expect(borrowable.connect(owner).redeem(shares, owner.address, lender._address))
                .to.emit(borrowable, "Withdraw") // check that a Withdraw event was emitted
                .to.emit(borrowable, "Sync"); // check that a Sync event was emitted

            // Check that the total balance of the borrowable contract is close to 1000 interest-bearing tokens
            expect(await borrowable.totalBalance()).to.be.closeTo(BigInt(1000), 1); // Interest bearing token

            // Check that the total number of shares in circulation is 1000 (dead shares)
            expect(await borrowable.totalSupply()).to.equal(BigInt(1000));
        });

        it("Succeeds when msg.sender is owner of shares and has sufficient shares", async () => {
            // Fixture
            const { borrowable, lender } = await loadFixture(deployFixure);

            // Get the lender's current balance of CygUSD shares
            const shares = await borrowable.balanceOf(lender._address);

            // Redeem the lender's CygUSD shares
            await expect(borrowable.connect(lender).redeem(shares, lender._address, lender._address))
                .to.emit(borrowable, "Withdraw") // check that a Withdraw event was emitted
                .to.emit(borrowable, "Sync"); // check that a Sync event was emitted

            // Get the total balance and total supply of the borrowable contract (take into account initial dead shares/balance)
            expect(await borrowable.totalBalance()).to.be.closeTo(BigInt(1000), 1); // Interest bearing token

            // Check that the total number of shares in circulation is 1000 (dead shares)
            expect(await borrowable.totalSupply()).to.equal(BigInt(1000));
        });
    });

    describe("Borrower redeems CygLP shares", () => {
        it("Reverts if withdrawing shares and msg.sender is not owner of shares and has no allowance", async () => {
            const { owner, collateral, borrower } = await loadFixture(deployFixure);

            await expect(collateral.connect(owner).redeem(BigInt(1e6), owner.address, borrower._address)).to.be.reverted;
        });

        it("Reverts if withdrawing 0 shares", async () => {
            // Fixture
            const { collateral, borrower } = await loadFixture(deployFixure);

            await expect(collateral.connect(borrower).redeem(0, borrower._address, borrower._address)).to.be.reverted;
        });

        it("Reverts if withdrawing 0 shares and msg.sender is not owner of shares but has allowance", async () => {
            const { owner, collateral, borrower } = await loadFixture(deployFixure);

            await collateral.connect(borrower).approve(owner.address, BigInt(1000e6));

            // Reverts
            await expect(collateral.connect(owner).redeem(0, owner.address, borrower._address)).to.be.reverted;
        });

        it("Succeeds when owner withdraws shares for assets", async () => {
            // Fixture
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get shares of borrower
            const shares = await collateral.balanceOf(borrower._address);

            // Borrower redeems and receives assets
            await expect(collateral.connect(borrower).redeem(shares, borrower._address, borrower._address))
                .to.emit(collateral, "Withdraw") // check that a Withdraw event was emitted
                .to.emit(collateral, "Sync"); // check that a Sync event was emitted
        });

        it("Succeeds when msg.sender redeems owner shares with enough allowance", async () => {
            // Fixture
            const { owner, collateral, borrower } = await loadFixture(deployFixure);

            // Approve borrower's transfer of shares to owner
            await collateral.connect(borrower).approve(owner.address, BigInt(1000000e18));

            // Get the number of shares the borrower has
            const shares = await collateral.balanceOf(borrower._address);

            // Owner redeems and receives borrower`s shares
            await expect(collateral.connect(owner).redeem(shares, owner.address, borrower._address))
                .to.emit(collateral, "Withdraw") // check that a Withdraw event was emitted
                .to.emit(collateral, "Sync"); // check that a Sync event was emitted

            // Check that the total balance of the collateral contract is close to 1000 interest-bearing tokens
            expect(await collateral.totalBalance()).to.be.closeTo(BigInt(1000), 1); // Interest bearing token

            // Check that the total number of shares in circulation is 1000 (initial minted)
            expect(await collateral.totalSupply()).to.equal(BigInt(1000));
        });

        it("Succeeds when msg.sender is owner of shares and has sufficient shares", async () => {
            // Fixture
            const { collateral, borrower } = await loadFixture(deployFixure);

            // Get the borrower's current balance of CygLP shares
            const shares = await collateral.balanceOf(borrower._address);

            // Redeem the borrower`s CygLP shares
            await expect(collateral.connect(borrower).redeem(shares, borrower._address, borrower._address))
                .to.emit(collateral, "Withdraw") // check that a Withdraw event was emitted
                .to.emit(collateral, "Sync"); // check that a Sync event was emitted

            // Get the total balance and total supply of the borrowable contract (take into account initial dead shares/balance)
            expect(await collateral.totalBalance()).to.be.closeTo(BigInt(1000), 1); // Interest bearing token
            expect(await collateral.totalSupply()).to.equal(BigInt(1000));
        });
    });

    // Test: Redeem Shares
    describe("Second lender deposits stablecoins and redeems CygUSD shares", () => {
        // - Initial lender deposits in borrowable
        // - We deposit again with another lender to test for the share amounts minted
        // - Test that shares received are AT LEAST greater than calculated due to strategy interest accrual
        it("Deposits underlying in borrowable and receives correct shares", async () => {
            // Fixture
            const { lender, usdc, owner, borrowable, permit2 } = await loadFixture(deployFixure);

            // Expect owner's balance in `borrowable` to be 0
            expect(await borrowable.balanceOf(owner.address)).to.equal(0);

            // 1. Approve `permit2` in USDC
            await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve `borrowable` contract to transfer USDC on behalf of the owner
            await permit2.connect(owner).approve(usdc.address, borrowable.address, BigInt(45900e6), "28147497671");

            // 3. Transfer some USDC from lender to owner's address
            await usdc.connect(lender).transfer(owner.address, BigInt(45900e6));

            // 4. Create empty permit with dummy variables
            const permit = {
                details: {
                    token: usdc.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: lender._address,
                sigDeadline: 0,
            };

            // Get USDC balance of owner before depositing in `borrowable`
            const usdBalBeforeDeposit = await usdc.balanceOf(owner.address);

            // Sync `borrowable` contract
            await borrowable.sync();

            // Calculate the current exchange rate
            const exchangeRate = await borrowable.callStatic.exchangeRate();

            // Deposit USDC into `borrowable` contract with empty permit
            await borrowable.connect(owner).deposit(usdBalBeforeDeposit, owner.address, permit, "0x");

            // Calculate the shares received by the owner
            const shares = usdBalBeforeDeposit.mul(ONE).div(exchangeRate);
            const sharesReceived = await borrowable.balanceOf(owner.address);

            // Test that shares received are greater than calculated shares
            expect(sharesReceived).to.be.closeTo(shares, BigInt(0.001e6));
        });

        // - Initial lender deposits in borrowable
        // - We deposit again with another lender to test for the share amounts minted, mine 100,000 blocks and redeem
        // - Test that assets received are AT LEAST greater than calculated assets due to strategy interest accrual
        it("Redeems underlying from borrowable and receives correct assets", async () => {
            // Load the test fixture which includes the necessary contracts and users
            const { lender, usdc, owner, borrowable, permit2 } = await loadFixture(deployFixure);

            // Ensure that the balance of the borrower is zero initially
            expect(await borrowable.balanceOf(owner.address)).to.equal(0);

            // 1. Approve permit2 in USDC for the owner
            await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Allow permit2 to spend USDC for the borrowable contract on behalf of the owner
            await permit2.connect(owner).approve(usdc.address, borrowable.address, BigInt(45900e6), "28147497671");

            // 3. Transfer USDC from the lender to the owner
            await usdc.connect(lender).transfer(owner.address, BigInt(45900e6));

            // Create an empty permit with dummy values
            const permit = {
                details: {
                    token: usdc.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: lender._address,
                sigDeadline: 0,
            };

            // Get the USDC balance of the owner before depositing into the borrowable contract
            const usdBalBeforeCYG = await usdc.balanceOf(owner.address);

            // Sync the borrowable contract with its underlying asset
            await borrowable.sync();

            // Deposit USDC into the borrowable contract on behalf of the owner
            await borrowable.connect(owner).deposit(usdBalBeforeCYG, owner.address, permit, "0x");

            // Check we have deposited full amount
            expect(await usdc.balanceOf(owner.address)).to.equal(0);

            // Check that the number of shares received by the owner is close to the expected value
            const sharesReceived = await borrowable.balanceOf(owner.address);

            // Wait for 100000 blocks to simulate the accrual of interest
            await mine(100_000);

            // Sync the borrowable contract with its underlying asset
            await borrowable.sync();

            // Calculate the amount of underlying asset that the owner can redeem for their shares
            const newExchangeRate = await borrowable.callStatic.exchangeRate();
            const assets = sharesReceived.mul(newExchangeRate).div(ONE);

            // Redeem the owner's shares for the underlying asset
            await borrowable.connect(owner).redeem(sharesReceived, owner.address, owner.address);

            // Get asset received
            const assetsReceived = await usdc.balanceOf(owner.address);

            // Check our calculation is close by a mini token due to interest accrual
            expect(assetsReceived).to.be.closeTo(assets, BigInt(0.001e6));

            // Check we have received AT LEAST the amount we had BEFORE interacting with Cygnus
            expect(assetsReceived).to.be.gt(usdBalBeforeCYG);
        });
    });

    describe("Second borrower deposits assets and redeems CygLP shares", () => {
        // - Initial borrower deposits in collateral
        // - We deposit again with another borrower to test for the share amounts minted
        // - Test that shares received are correct
        it("Deposits underlying in collateral and receives correct shares", async () => {
            // Fixture
            const { borrower, lpToken, owner, collateral, permit2 } = await loadFixture(deployFixure);

            // Expect owner's balance in `collateral` to be 0
            expect(await collateral.balanceOf(owner.address)).to.equal(0);

            // 1. Approve `permit2` in LP Token
            await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve `collateral` contract to transfer LP on behalf of the owner
            await permit2.connect(owner).approve(lpToken.address, collateral.address, BigInt(2e18), "28147497671");

            // 3. Transfer some LP from borrower to owner's address
            await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

            // 4. Create empty permit with dummy variables
            const permit = {
                details: {
                    token: lpToken.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: borrower._address,
                sigDeadline: 0,
            };

            // Get LP balance of owner before depositing in `collateral`
            const lpTokenBalBefore = await lpToken.balanceOf(owner.address);

            // Calculate the current exchange rate
            const exchangeRate = await collateral.exchangeRate();

            // Deposit LP Token into `collateral` contract with empty permit
            await collateral.connect(owner).deposit(lpTokenBalBefore, owner.address, permit, "0x");

            // Calculate the shares received by the owner
            const shares = lpTokenBalBefore.mul(ONE).div(exchangeRate);
            const sharesReceived = await collateral.balanceOf(owner.address);

            // Test that shares received are greater than calculated shares
            expect(sharesReceived).to.equal(shares);
        });

        // - Initial borrower deposits in collateral
        // - We deposit again with another borrower to test for the share amounts minted, mine 100,000 blocks and redeem
        // - Test that assets received are correct
        it("Redeems underlying from collateral and receives correct assets", async () => {
            // Load the test fixture which includes the necessary contracts and users
            const { borrower, lpToken, owner, collateral, permit2 } = await loadFixture(deployFixure);

            // Ensure that the balance of the borrower is zero initially
            expect(await collateral.balanceOf(owner.address)).to.equal(0);

            // 1. Approve permit2 in LP for the owner
            await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Allow permit2 to spend LP Tokens for the collateral contract on behalf of the owner
            await permit2.connect(owner).approve(lpToken.address, collateral.address, BigInt(2e18), "28147497671");

            // 3. Transfer LP from the borrower to the owner
            await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

            // Create an empty permit with dummy values
            const permit = {
                details: {
                    token: lpToken.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: borrower._address,
                sigDeadline: 0,
            };

            // Get the LP balance of the owner before depositing into the collateral contract
            const lpBalanceBeforeCyg = await lpToken.balanceOf(owner.address);

            // Deposit LP into the collateral contract on behalf of the owner
            await collateral.connect(owner).deposit(lpBalanceBeforeCyg, owner.address, permit, "0x");

            // Check that the number of shares received by the owner is close to the expected value
            const sharesReceived = await collateral.balanceOf(owner.address);

            // Wait for 100000 blocks to simulate the accrual of interest
            await mine(100_000);

            // Calculate the amount of underlying asset that the owner can redeem for their shares
            const newExchangeRate = await collateral.callStatic.exchangeRate();
            const assets = sharesReceived.mul(newExchangeRate).div(ONE);

            // Redeem the owner's shares for the underlying asset
            await collateral.connect(owner).redeem(sharesReceived, owner.address, owner.address);

            // Check that the amount of underlying asset received by the owner is greater than the expected value
            const assetsReceived = await lpToken.balanceOf(owner.address);

            // Check we receive exact amount of assets we calculated
            expect(assetsReceived).to.be.equal(assets);
        });
    });
});
