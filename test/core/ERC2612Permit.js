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
 *  Simple tests for soladys erc2612
 */
describe("ERC2612 Tests", function () {
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
        };
    };

    /**
     *  BEGIN TESTS
     */
    describe("------------------- Begin Test -------------------", () => {
        it("...begins...", async () => await loadFixture(deployFixure));
    });

    describe("Checks ERC2616 implementation is correct for Borrowable contracts", () => {
        // name()
        it("Should match the name of `Cygnus: Borrowable`", async () => {
            // Fixture
            const { borrowable } = await loadFixture(deployFixure);

            expect(await borrowable.name()).to.be.eq(`Cygnus: Borrowable`);
        });

        // symbol()
        it("Should match the name of `CygUSD: USDC`", async () => {
            // Fixture
            const { borrowable, usdc } = await loadFixture(deployFixure);

            const symbol = await usdc.symbol();

            expect(await borrowable.symbol()).to.be.eq(`CygUSD: ${symbol}`);
        });

        // decimals()
        it("Should match the decimals of the underlying", async () => {
            // Fixture
            const { borrowable, usdc } = await loadFixture(deployFixure);

            const decimals = await usdc.decimals();

            expect(await borrowable.decimals()).to.be.eq(decimals);
        });

        // DOMAIN_SEPARATOR()
        it("Should match the DOMAIN_SEPARATOR as detailed in https://eips.ethereum.org/EIPS/eip-2612", async () => {
            //    DOMAIN_SEPARATOR = keccak256(
            //        abi.encode(
            //            keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
            //            keccak256(bytes(name)),
            //            keccak256(bytes(version)),
            //            chainid,
            //            address(this)
            //    ));

            // Fixture
            const { borrowable, owner } = await loadFixture(deployFixure);

            // DOMAIN_SEPARATOR from the contract
            const domainSeparator = await borrowable.DOMAIN_SEPARATOR();

            // Build domain
            const _name = await borrowable.name();
            const _version = "1"; // Solady's erc20 has no version
            const _chainId = await owner.getChainId();
            const _verifyingContract = await borrowable.address;

            const domain = {
                name: _name,
                version: _version,
                chainId: _chainId,
                verifyingContract: _verifyingContract,
            };

            // Compute domain
            const computeDomainSeparator = await ethers.utils._TypedDataEncoder.hashDomain(domain);

            // Expect domain == DOMAIN_SEPARATOR
            expect(domainSeparator).to.be.equal(computeDomainSeparator);
        });

        // permit()
        it("Should revert when increasing allowance with `permit` if owner is not signer", async () => {
            // Fixture
            const { borrowable, owner, lender } = await loadFixture(deployFixure);

            // Build domain
            const _name = await borrowable.name();
            const _version = "1"; // Solady's erc20 has no version
            const _chainId = await owner.getChainId();
            const _verifyingContract = await borrowable.address;

            const domain = {
                name: _name,
                version: _version,
                chainId: _chainId,
                verifyingContract: _verifyingContract,
            };

            const types = {
                Permit: [
                    { name: "owner", type: "address" },
                    { name: "spender", type: "address" },
                    { name: "value", type: "uint256" },
                    { name: "nonce", type: "uint256" },
                    { name: "deadline", type: "uint256" },
                ],
            };

            // Values
            const _nonce = await borrowable.nonces(owner.address);

            const values = {
                owner: lender._address,
                spender: owner.address,
                value: ethers.constants.MaxUint256,
                nonce: _nonce,
                deadline: ethers.constants.MaxUint256,
            };

            const signature = await owner._signTypedData(domain, types, values);

            const { v, r, s } = await ethers.utils.splitSignature(signature);

            // Lender is the "vulnerable" account with collateral
            const allowanceBefore = await borrowable.allowance(lender._address, owner.address);

            // In the signature the owner is the lender
            await expect(
                borrowable
                    .connect(owner)
                    .permit(owner.address, lender._address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s),
            ).to.be.reverted;

            // Same as signature, expect to revert since ecrecover will not match owner
            await expect(
                borrowable
                    .connect(owner)
                    .permit(lender._address, owner.address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s),
            ).to.be.reverted;

            // Approving themselves with wrong signature
            await expect(
                borrowable
                    .connect(owner)
                    .permit(owner.address, owner.address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s),
            ).to.be.reverted;

            // Expect the same allowance
            expect(await borrowable.allowance(lender._address, owner.address)).to.be.equal(allowanceBefore);
        });

        // permit()
        it("Should increase allowance with `permit` if owner is the signer", async () => {
            // Fixture
            const { borrowable, owner, router } = await loadFixture(deployFixure);

            // DOMAIN
            const _name = await borrowable.name();
            const _version = "1"; // Solady's erc20 has no version
            const _chainId = await owner.getChainId();
            const _verifyingContract = await borrowable.address;

            const domain = {
                name: _name,
                version: _version,
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
                value: ethers.constants.MaxUint256,
                nonce: _nonce,
                deadline: ethers.constants.MaxUint256,
            };

            const signature = await owner._signTypedData(domain, types, values);

            const { v, r, s } = await ethers.utils.splitSignature(signature);

            // Lender is the "vulnerable" account with collateral
            const allowanceBefore = await borrowable.allowance(owner.address, router.address);

            await borrowable
                .connect(owner)
                .permit(owner.address, router.address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s);

            expect(await borrowable.allowance(owner.address, router.address)).to.be.gt(allowanceBefore);
        });
    });

    describe("Checks ERC2616 implementation is correct for Collateral contracts", () => {
        // name()
        it("Should match the name of `Cygnus: Collateral`", async () => {
            // Fixture
            const { collateral } = await loadFixture(deployFixure);

            expect(await collateral.name()).to.be.eq(`Cygnus: Collateral`);
        });

        // symbol()
        it("Should match the name of `CygLP: {LP Token Symbol}`", async () => {
            // Fixture
            const { collateral, lpToken } = await loadFixture(deployFixure);

            const symbol = await lpToken.symbol();

            expect(await collateral.symbol()).to.be.eq(`CygLP: ${symbol}`);
        });

        // decimals()
        it("Should match the decimals of the underlying", async () => {
            // Fixture
            const { collateral, lpToken } = await loadFixture(deployFixure);

            const decimals = await lpToken.decimals();

            expect(await collateral.decimals()).to.be.eq(decimals);
        });

        // DOMAIN_SEPARATOR()
        it("Should match the DOMAIN_SEPARATOR as detailed in https://eips.ethereum.org/EIPS/eip-2612", async () => {
            //    DOMAIN_SEPARATOR = keccak256(
            //        abi.encode(
            //            keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
            //            keccak256(bytes(name)),
            //            keccak256(bytes(version)),
            //            chainid,
            //            address(this)
            //    ));

            // Fixture
            const { collateral, owner } = await loadFixture(deployFixure);

            // DOMAIN_SEPARATOR from the contract
            const domainSeparator = await collateral.DOMAIN_SEPARATOR();

            // Build domain
            const _name = await collateral.name();
            const _version = "1"; // Solady's erc20 has no version
            const _chainId = await owner.getChainId();
            const _verifyingContract = await collateral.address;

            const domain = {
                name: _name,
                version: _version,
                chainId: _chainId,
                verifyingContract: _verifyingContract,
            };

            // Compute domain
            const computeDomainSeparator = await ethers.utils._TypedDataEncoder.hashDomain(domain);

            // Expect domain == DOMAIN_SEPARATOR
            expect(domainSeparator).to.be.equal(computeDomainSeparator);
        });

        // permit()
        it("Should revert when increasing allowance with `permit` if owner is not signer", async () => {
            // Fixture
            const { collateral, owner, lender } = await loadFixture(deployFixure);

            // Build domain
            const _name = await collateral.name();
            const _version = "1"; // Solady's erc20 has no version
            const _chainId = await owner.getChainId();
            const _verifyingContract = await collateral.address;

            const domain = {
                name: _name,
                version: _version,
                chainId: _chainId,
                verifyingContract: _verifyingContract,
            };

            const types = {
                Permit: [
                    { name: "owner", type: "address" },
                    { name: "spender", type: "address" },
                    { name: "value", type: "uint256" },
                    { name: "nonce", type: "uint256" },
                    { name: "deadline", type: "uint256" },
                ],
            };

            // Values
            const _nonce = await collateral.nonces(owner.address);

            const values = {
                owner: lender._address,
                spender: owner.address,
                value: ethers.constants.MaxUint256,
                nonce: _nonce,
                deadline: ethers.constants.MaxUint256,
            };

            const signature = await owner._signTypedData(domain, types, values);

            const { v, r, s } = await ethers.utils.splitSignature(signature);

            // Lender is the "vulnerable" account with collateral
            const allowanceBefore = await collateral.allowance(lender._address, owner.address);

            // In the signature the owner is the lender
            await expect(
                collateral
                    .connect(owner)
                    .permit(owner.address, lender._address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s),
            ).to.be.reverted;

            // Same as signature, expect to revert since ecrecover will not match owner
            await expect(
                collateral
                    .connect(owner)
                    .permit(lender._address, owner.address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s),
            ).to.be.reverted;

            // Approving themselves with wrong signature
            await expect(
                collateral
                    .connect(owner)
                    .permit(owner.address, owner.address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s),
            ).to.be.reverted;

            // Expect the same allowance
            expect(await collateral.allowance(lender._address, owner.address)).to.be.equal(allowanceBefore);
        });

        // permit()
        it("Should increase allowance with `permit` if owner is the signer", async () => {
            // Fixture
            const { collateral, owner, router } = await loadFixture(deployFixure);

            // DOMAIN
            const _name = await collateral.name();
            const _version = "1"; // Solady's erc20 has no version
            const _chainId = await owner.getChainId();
            const _verifyingContract = await collateral.address;

            const domain = {
                name: _name,
                version: _version,
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
            const _nonce = await collateral.nonces(owner.address);
            const values = {
                owner: owner.address,
                spender: router.address,
                value: ethers.constants.MaxUint256,
                nonce: _nonce,
                deadline: ethers.constants.MaxUint256,
            };

            const signature = await owner._signTypedData(domain, types, values);

            const { v, r, s } = await ethers.utils.splitSignature(signature);

            // Lender is the "vulnerable" account with collateral
            const allowanceBefore = await collateral.allowance(owner.address, router.address);

            await collateral
                .connect(owner)
                .permit(owner.address, router.address, ethers.constants.MaxUint256, ethers.constants.MaxUint256, v, r, s);

            expect(await collateral.allowance(owner.address, router.address)).to.be.gt(allowanceBefore);
        });
    });
});
