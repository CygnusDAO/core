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
const { MaxUint256, AddressZero } = ethers.constants;

/**
 *  @notice Simple deposit tests for permit2 and to check modifiers/shares received by both borrowable/collateral
 */
describe("Borrowable and Collateral Deposit with Permit2", function () {
    /**
     *  Deploys the fixture for testing the Cygnus Core contracts.
     */
    async function deployFixure() {
        // Make lending pool and collateral
        const [, , router, borrowable, collateral, usdc, lpToken, chainId] = await Make();

        // Create users: owner (admin), lender, and borrower
        const [owner, , , lender, borrower] = await Users();

        // Charge Borrowbale allowance to deposit in rewarder
        await borrowable.chargeVoid();

        // Charge Collateral allowance to deposit in rewarder
        await collateral.chargeVoid();

        return {
            router, // Router contract
            borrowable, // Lending pool contract
            collateral, // Collateral contract
            usdc, // USDC contract
            lpToken, // LP token contract
            owner, // Owner (admin) user
            lender, // Lender user before CYG
            borrower, // Borrower user before CYG
            chainId, // Chain ID of the network being tested
        };
    }

    describe("------------------- Begin Test -------------------", () => {
        it("...begins...", async () => {
            await loadFixture(deployFixure);
        });
    });

    // Test: Deploy Borrowable
    describe("Deployment Borrowable (USDC)", () => {
        it("Should deploy borrowable pool with USDC underlying", async () => {
            const { borrowable, usdc } = await loadFixture(deployFixure);
            const underlying = await borrowable.underlying();
            expect(underlying.toLowerCase()).to.equal(usdc.address.toLowerCase());
        });

        it("Should have 0 total supply", async () => {
            const { borrowable } = await loadFixture(deployFixure);
            expect(await borrowable.totalSupply()).to.equal(0);
        });

        it("Should have 0 total balance", async () => {
            const { borrowable } = await loadFixture(deployFixure);
            expect(await borrowable.totalBalance()).to.equal(0);
        });

        it("Should have 0 total borrows", async () => {
            const { borrowable } = await loadFixture(deployFixure);
            expect(await borrowable.totalBorrows()).to.equal(0);
        });

        it("Should have the initial exchange rate of one mantissa", async () => {
            const { borrowable } = await loadFixture(deployFixure);
            expect(await borrowable.callStatic.exchangeRate()).to.equal(BigInt(1e18));
        });
    });

    // Test: Deploy Collateral
    describe("Deployment Collateral (LP)", () => {
        it("Should deploy Collateral pool with LP underlying", async () => {
            const { collateral, lpToken } = await loadFixture(deployFixure);
            const underlying = await collateral.underlying();
            expect(underlying.toLowerCase()).to.equal(lpToken.address.toLowerCase());
        });

        it("Should have 0 total supply", async () => {
            const { collateral } = await loadFixture(deployFixure);
            expect(await collateral.totalSupply()).to.equal(0);
        });

        it("Should have 0 total balance", async () => {
            const { collateral } = await loadFixture(deployFixure);
            expect(await collateral.totalBalance()).to.equal(0);
        });

        it("Should have the initial exchange rate of one mantissa", async () => {
            const { collateral } = await loadFixture(deployFixure);
            expect(await collateral.callStatic.exchangeRate()).to.equal(BigInt(1e18));
        });
    });

    // Test: Deposit USD in Borrowable
    describe("Deposits USDC in Borrowable pool with Permit2", () => {
        // Allows users to deposit in 1 transaction
        it("Should allow deposits with permit2 to owner in 1 transaction", async () => {
            // Load fixture
            const { borrowable, usdc, owner, lender } = await loadFixture(deployFixure);

            // Get chain ID of owner's network
            const _chainId = await owner.getChainId();

            // 1. Approve permit2 in USDC
            await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Build permit data
            const permitB = {
                details: {
                    token: usdc.address,
                    amount: BigInt(100000e6),
                    expiration: MaxAllowanceExpiration,
                    nonce: 0,
                },
                spender: borrowable.address,
                sigDeadline: MaxUint256,
            };

            // Get permit data and signature
            const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
            const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);

            // 3. Transfer USDC to owner
            await usdc.connect(lender).transfer(owner.address, BigInt(120000e6));

            // 4. Owner deposits using lender address
            await expect(borrowable.connect(owner).deposit(BigInt(100000e6), owner.address, permitB, signatureB))
                .to.emit(borrowable, "Deposit") // Emit Deposit event
                .to.emit(borrowable, "Sync"); // Emit Sync event

            // Check that the owner's balance of borrowable tokens has increased by the expected amount
            // Subtract initial 1000 shares minted during deployment
            expect(await borrowable.balanceOf(owner.address)).to.be.closeTo(BigInt(100000e6 - 1000), 1);
        });

        it("Should allow deposits with permit2 to someone else in 1 transaction", async () => {
            // Load fixture
            const { borrowable, usdc, owner, lender } = await loadFixture(deployFixure);

            // Get chain ID of owner's network
            const _chainId = await owner.getChainId();

            // 1. Approve permit2 in USDC
            await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Build permit data
            const permitB = {
                details: {
                    token: usdc.address,
                    amount: BigInt(100000e6),
                    expiration: MaxAllowanceExpiration,
                    nonce: 0,
                },
                spender: borrowable.address,
                sigDeadline: MaxUint256,
            };

            // Get permit data and signature
            const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
            const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);

            // 3. Transfer USDC to owner
            await usdc.connect(lender).transfer(owner.address, BigInt(120000e6));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(borrowable.connect(owner).deposit(BigInt(100000e6), lender._address, permitB, signatureB)).to.emit(borrowable, 'Deposit');

            // Check that the lender's balance of borrowable tokens has increased by the expected amount
            // Subtract initial 1000 shares minted during deployment
            expect(await borrowable.balanceOf(lender._address)).to.be.closeTo(BigInt(100000e6 - 1000), 1);
        });

        // TEST: Deposit without permit2
        it("Should allow deposits without permit2 signature (requires 2 txs)", async () => {
            // Fixture
            const { borrowable, usdc, lender } = await loadFixture(deployFixure);

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await usdc.connect(lender).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2.connect(lender).approve(usdc.address, borrowable.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB = {
                details: {
                    token: usdc.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: lender._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(borrowable.connect(lender).deposit(BigInt(100000e6), lender._address, permitB, "0x")).to.emit(borrowable, 'Deposit')

            // Substract initial 1000 shares mint
            expect(await borrowable.balanceOf(lender._address)).to.be.closeTo(BigInt(100000e6 - 1000), 1);
        });

        // TEST: Deposit without permit2
        it("Should allow deposits without permit2 without signature to someone else (requires 2 txs)", async () => {
            // Fixture
            const { borrowable, usdc, lender, owner } = await loadFixture(deployFixure);

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await usdc.connect(lender).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2.connect(lender).approve(usdc.address, borrowable.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB = {
                details: {
                    token: usdc.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: lender._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(borrowable.connect(lender).deposit(BigInt(100000e6), owner.address, permitB, "0x")).to.emit(borrowable, 'Deposit')

            // Substract initial 1000 shares mint
            expect(await borrowable.balanceOf(owner.address)).to.be.closeTo(BigInt(100000e6 - 1000), 1);
        });

        // TEST: Deposit without permit2
        it("Should mint 1000 shares to address zero only on first deposits", async () => {
            // Fixture
            const { borrowable, usdc, lender, owner } = await loadFixture(deployFixure);

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await usdc.connect(lender).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2.connect(lender).approve(usdc.address, borrowable.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB = {
                details: {
                    token: usdc.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: lender._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(borrowable.connect(lender).deposit(BigInt(100000e6), lender._address, permitB, "0x")).to.emit(borrowable, 'Deposit')

            // Substract initial 1000 shares mint
            expect(await borrowable.balanceOf(lender._address)).to.be.closeTo(BigInt(100000e6 - 1000), 1);
            expect(await borrowable.balanceOf(AddressZero)).to.be.equal(BigInt(1000));

            // Second deposit
            await expect(borrowable.connect(lender).deposit(BigInt(200e6), lender._address, permitB, "0x")).to.emit(
                borrowable,
                "Deposit",
            );
            expect(await borrowable.balanceOf(AddressZero)).to.be.equal(BigInt(1000));

            // Third deposit
            // 1. Approve permit2 in USDC
            await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2.connect(owner).approve(usdc.address, borrowable.address, BigInt(1000000e18), "28147497671");

            // 3. Transfer USDC to owner
            await usdc.connect(lender).transfer(owner.address, BigInt(1000e6));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(borrowable.connect(owner).deposit(BigInt(995e6), owner.address, permitB, "0x")).to.emit(borrowable, 'Deposit')
            expect(await borrowable.balanceOf(AddressZero)).to.be.equal(BigInt(1000));
        });
    });

    //
    // Test: Deposit LP in Collateral
    //
    describe("Deposits LP in Collateral pool with Permit2", () => {
        // TEST: Deposit without permit2
        it("Should allow deposits with permit2 to owner in 1 transaction", async () => {
            // Fixture
            const { collateral, lpToken, owner, borrower } = await loadFixture(deployFixure);

            // Chain ID
            const _chainId = await owner.getChainId();

            // 1. Approve permit2 in USDC
            await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Build permit
            const permitB = {
                details: {
                    token: lpToken.address,
                    amount: BigInt(1000e18),
                    expiration: MaxAllowanceExpiration,
                    nonce: 0,
                },
                spender: collateral.address,
                sigDeadline: MaxUint256,
            };

            // Sign
            const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
            // DOMAIN,TYPES,VALUES
            const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);

            // 3. Transfer USDC to owner
            await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(owner).deposit(BigInt(2e18), owner.address, permitB, signatureB)).to.emit(collateral, "Deposit")

            // Substract initial 1000 shares mint
            expect(await collateral.balanceOf(owner.address)).to.be.closeTo(BigInt(2e18) - BigInt(1000), 1);
        });

        it("Should allow deposits with permit2 to someone else in 1 transaction", async () => {
            // Fixture
            const { collateral, lpToken, owner, borrower } = await loadFixture(deployFixure);

            // Chain ID
            const _chainId = await owner.getChainId();

            // 1. Approve permit2 in USDC
            await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Build permit
            const permitB = {
                details: {
                    token: lpToken.address,
                    amount: BigInt(1000e18),
                    expiration: MaxAllowanceExpiration,
                    nonce: 0,
                },
                spender: collateral.address,
                sigDeadline: MaxUint256,
            };

            // Sign
            const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
            // DOMAIN,TYPES,VALUES
            const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);

            // 3. Transfer USDC to owner
            await lpToken.connect(borrower).transfer(owner.address, BigInt(1.5e18));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(owner).deposit(BigInt(1.5e18), borrower._address, permitB, signatureB)).to.emit(collateral, 'Deposit');

            // Substract initial 1000 shares mint
            expect(await collateral.balanceOf(borrower._address)).to.be.closeTo(BigInt(1.5e18) - BigInt(1000), 1);
        });

        // TEST: Deposit without permit2
        it("Should allow deposits without permit2 (requires 2 txs)", async () => {
            // Fixture
            const { collateral, lpToken, borrower } = await loadFixture(deployFixure);

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await lpToken.connect(borrower).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2
                .connect(borrower)
                .approve(lpToken.address, collateral.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB = {
                details: {
                    token: lpToken.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: borrower._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(borrower).deposit(BigInt(2e18), borrower._address, permitB, "0x")).to.emit(collateral, 'Deposit')

            // Substract initial 1000 shares mint
            expect(await collateral.balanceOf(borrower._address)).to.be.closeTo(BigInt(2e18) - BigInt(1000), 1);
        });

        // TEST: Deposit without permit2
        it("Should allow deposits without permit2 to someone else (requires 2 txs)", async () => {
            // Fixture
            const { collateral, lpToken, borrower, owner } = await loadFixture(deployFixure);

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await lpToken.connect(borrower).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2
                .connect(borrower)
                .approve(lpToken.address, collateral.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB = {
                details: {
                    token: lpToken.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: borrower._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(borrower).deposit(BigInt(2e18), owner.address, permitB, "0x")).to.emit(collateral, 'Deposit')

            // Substract initial 1000 shares mint
            expect(await collateral.balanceOf(owner.address)).to.be.closeTo(BigInt(2e18) - BigInt(1000), 1);
        });

        // TEST: Deposit without permit2
        it("Should mint 1000 shares to 0xdEaD only on first deposits", async () => {
            // Fixture
            const { collateral, lpToken, borrower, owner } = await loadFixture(deployFixure);

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await lpToken.connect(borrower).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2
                .connect(borrower)
                .approve(lpToken.address, collateral.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB = {
                details: {
                    token: lpToken.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: borrower._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(borrower).deposit(BigInt(1.25e18), borrower._address, permitB, "0x")).to.emit(collateral, 'Deposit')

            // Substract initial 1000 shares mint
            expect(await collateral.balanceOf(borrower._address)).to.be.closeTo(BigInt(1.25e18) - BigInt(1000), 1);
            expect(await collateral.balanceOf(AddressZero)).to.be.equal(BigInt(1000));

            // Second deposit
            await expect(
                collateral.connect(borrower).deposit(BigInt(0.25e18), borrower._address, permitB, "0x"),
            ).to.emit(collateral, "Deposit");
            expect(await collateral.balanceOf(AddressZero)).to.be.equal(BigInt(1000));

            // Third deposit
            // 1. Approve permit2 in USDC
            await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2
                .connect(owner)
                .approve(lpToken.address, collateral.address, BigInt(1000000e18), "28147497671");

            // 3. Transfer USDC to owner
            await lpToken.connect(borrower).transfer(owner.address, BigInt(1.75e18));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(owner).deposit(BigInt(1.75e18), owner.address, permitB, "0x")).to.emit(collateral, 'Deposit').to.emit(collateral, 'Sync')
            expect(await collateral.balanceOf(AddressZero)).to.be.equal(BigInt(1000));
        });
    });

    describe("Accuracy of vault shares", () => {
        it("Collateral should only mint shares on > 0 asset deposits & shares received should represent current exchange rate", async () => {
            // Fixture
            const { collateral, lpToken, owner, borrower } = await loadFixture(deployFixure);

            // ----------- DEPOSIT 1 ---------- //

            // Chain ID
            const _chainId = await owner.getChainId();

            // 1. Approve permit2 in USDC
            await lpToken.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Build permit
            const permitB = {
                details: {
                    token: lpToken.address,
                    amount: BigInt(1000e18),
                    expiration: MaxAllowanceExpiration,
                    nonce: 0,
                },
                spender: collateral.address,
                sigDeadline: MaxUint256,
            };

            // Sign
            const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
            // DOMAIN,TYPES,VALUES
            const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);

            // 3. Transfer USDC to owner
            await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(collateral.connect(owner).deposit(BigInt(2e18), owner.address, permitB, signatureB)).to.emit(collateral, "Deposit").to.emit(collateral, 'Sync')

            // Substract initial 1000 shares mint
            expect(await collateral.balanceOf(owner.address)).to.be.closeTo(BigInt(2e18) - BigInt(1000), 1);

            // ----------- DEPOSIT 2 ---------- //

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await lpToken.connect(borrower).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2
                .connect(borrower)
                .approve(lpToken.address, collateral.address, BigInt(1000000e18), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB2 = {
                details: {
                    token: lpToken.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: borrower._address,
                sigDeadline: 0,
            };

            // 4. Owner deposits using lender address
            //
            /// @custom:error CantMintZeroShares
            await expect(collateral.connect(borrower).deposit(0, borrower._address, permitB2, "0x")).to.be.reverted;

            // Check CygLP balance is 0
            expect(await collateral.balanceOf(borrower._address)).to.be.equal(0);

            // Deposit
            await expect(collateral.connect(borrower).deposit(BigInt(0.1e18), borrower._address, permitB2, "0x"))
                .to.emit(collateral, "Deposit")
                .to.emit(collateral, "Sync");

            // We check to be equal exchange rate
            expect(await collateral.balanceOf(borrower._address)).to.be.equal(BigInt(0.1e18));
        });

        // Test: 2 lenders deposit and receive shares
        it("Borrowable should only mint shares on > 0 asset deposits & shares received should represent current exchange rate", async () => {
            // Fixture
            const { borrowable, usdc, owner, lender } = await loadFixture(deployFixure);

            // ----------- DEPOSIT 1 ---------- //

            // Chain ID
            const _chainId = await owner.getChainId();

            // 1. Approve permit2 in USDC
            await usdc.connect(owner).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Build permit
            const permitB = {
                details: {
                    token: usdc.address,
                    amount: BigInt(1000e18),
                    expiration: MaxAllowanceExpiration,
                    nonce: 0,
                },
                spender: borrowable.address,
                sigDeadline: MaxUint256,
            };

            // Sign
            const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
            // DOMAIN,TYPES,VALUES
            const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);

            // 3. Transfer USDC to owner
            await usdc.connect(lender).transfer(owner.address, BigInt(1000e6));

            // 4. Owner deposits using lender address
            // prettier-ignore
            await expect(borrowable.connect(owner).deposit(BigInt(1000e6), owner.address, permitB, signatureB)).to.emit(borrowable, "Deposit").to.emit(borrowable, 'Sync')

            // Substract initial 1000 shares mint
            expect(await borrowable.balanceOf(owner.address)).to.be.closeTo(BigInt(1000e6) - BigInt(1000), 1);

            // ----------- DEPOSIT 2 ---------- //

            // Make permit2
            const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

            // 1. Approve permit2 in USDC
            await usdc.connect(lender).approve(PERMIT2_ADDRESS, MaxUint256);

            // 2. Approve borrowable to spend our USDC in Permit2
            await permit2.connect(lender).approve(usdc.address, borrowable.address, BigInt(4000e6), "28147497671");

            // 3. Empty permit with dummy vars
            const permitB2 = {
                details: {
                    token: usdc.address,
                    amount: 0,
                    expiration: 0,
                    nonce: 0,
                },
                spender: lender._address,
                sigDeadline: 0,
            };

            // 4. Lender deposits without permit2 signature

            /// @custom:error CantMintZeroShares
            await expect(borrowable.connect(lender).deposit(0, lender._address, permitB2, "0x")).to.be.reverted;

            // Check lender's balance of CygUSD is still 0
            expect(await borrowable.balanceOf(lender._address)).to.be.equal(0);

            // Deposit
            await expect(borrowable.connect(lender).deposit(BigInt(1000e6), lender._address, permitB2, "0x"))
                .to.emit(borrowable, "Deposit")
                .to.emit(borrowable, "Sync");

            // We have to reduce by 10 or so since the borrowable accrues interests for the cToken, and thus our balance increases prior deposits
            expect(await borrowable.balanceOf(lender._address)).to.be.closeTo(BigInt(1000e6), 10);
        });
    });
});
