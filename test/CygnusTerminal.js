// Node
// Hardhat
const chai = require('chai');
const hre = require('hardhat');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;
const { keccak256 } = require('@ethersproject/keccak256');
const { toUtf8Bytes } = require('@ethersproject/strings');
const { AddressZero, MaxUint256 } = require('@ethersproject/constants');

// Custom errors
const { CygnusTerminalErrors } = require('./errors/CygnusTerminalErrors.js');

// Cygnus Test utils
const { getDomainSeparator, getApprovalDigest, selfPermit } = require('./utils/Cygnus.js');

chai.use(solidity);

describe('CygnusTerminal', function () {
    /*  ───────────────────────────────────────────── Ethers ───────────────────────────────────────────────  */

    const max = ethers.constants.MaxUint256;

    const AddressZero = ethers.constants.AddressZero;

    const oneMantissa = BigInt(1e18);

    /*  ─────────────────────────────────────────── Addresses ─────────────────────────────────────────────  */

    // signer hardhat, safeAddress2/safeAddress3 check for EIP712
    let owner, safeAddress1, safeAddress2, safeAddress3, unsafeAddress1;

    // ethers signer1
    let owner_privateKey = 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

    // ethers signer2
    let safeAddress1_privateKey = '59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

    // ethers signer3
    let safeAddress2_privateKey = '5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a';

    /*  ──────────────────────────────────────────── Contract ─────────────────────────────────────────────  */

    // Contract
    let cygnusTerminal;

    // Test Tokens
    let testTokens = 2000;

    // Erc20
    let name = 'CygnusPoolToken';

    let symbol = 'CYG-LP';

    // Initialize and mint testTokens
    beforeEach(async () => {
        let cygnusTerminalToken = await ethers.getContractFactory('CygnusTerminal');

        [owner, safeAddress1, safeAddress2, safeAddress3, unsafeAddress1] = await ethers.getSigners();

        cygnusTerminal = await cygnusTerminalToken.deploy(name, symbol, 18);

        totalSupply = cygnusTerminal.totalSupply();
    });

    /**
     * - Erc20 standard functions
     *
     * - Calls checked with event arguments, and errors from CygnusTerminalErrors.js
     *
     */
    describe('Erc20', function () {
        it('name, symbol, decimals', async () => {
            expect(await cygnusTerminal.name()).to.eq(name);

            expect(await cygnusTerminal.symbol()).to.eq(symbol);

            expect(await cygnusTerminal.decimals()).to.eq(18);
        });

        it('totalSupply, balanceOf', async () => {
            const ownerBalance = await cygnusTerminal.balanceOf(owner.address);

            expect(await cygnusTerminal.totalSupply()).to.equal(ownerBalance);

            expect(await cygnusTerminal.balanceOf(owner.address)).to.eq(testTokens);
        });

        it('approve with {Approval} event', async () => {
            // Approval & Event
            await expect(cygnusTerminal.approve(safeAddress1.address, testTokens))
                .to.emit(cygnusTerminal, 'Approval')
                .withArgs(owner.address, safeAddress1.address, testTokens);

            expect(await cygnusTerminal.allowance(owner.address, safeAddress1.address)).to.eq(testTokens);
        });

        it('transfer with {Transfer} event', async () => {
            // Test event
            await expect(cygnusTerminal.transfer(safeAddress1.address, testTokens))
                .to.emit(cygnusTerminal, 'Transfer')
                .withArgs(owner.address, safeAddress1.address, testTokens);

            // Test balances
            expect(await cygnusTerminal.balanceOf(owner.address)).to.eq(0);

            expect(await cygnusTerminal.balanceOf(safeAddress1.address)).to.eq(testTokens);
        });

        it('transfer:FAIL {InsufficientBalance}', async () => {
            // Custom error
            await expect(cygnusTerminal.transfer(safeAddress1.address, testTokens + 100)).to.be.revertedWith(
                CygnusTerminalErrors.INSUFFICIENT_BALANCE,
            );
        });

        it('transferFrom with {Transfer} event', async () => {
            // Approve
            await cygnusTerminal.approve(safeAddress1.address, testTokens);

            // Connect to contract with signer 1 and Test event
            await expect(
                cygnusTerminal.connect(safeAddress1).transferFrom(owner.address, safeAddress1.address, testTokens),
            )
                .to.emit(cygnusTerminal, 'Transfer')
                .withArgs(owner.address, safeAddress1.address, testTokens);

            // Check balances and allowances
            expect(await cygnusTerminal.allowance(owner.address, safeAddress1.address)).to.eq(0);

            expect(await cygnusTerminal.balanceOf(owner.address)).to.eq(0);

            expect(await cygnusTerminal.balanceOf(safeAddress1.address)).to.eq(testTokens);
        });

        it('transferFrom:Max', async () => {
            await cygnusTerminal.approve(safeAddress1.address, MaxUint256);

            // connect to contract with signer 1
            await expect(
                cygnusTerminal.connect(safeAddress1).transferFrom(owner.address, safeAddress1.address, testTokens),
            )
                .to.emit(cygnusTerminal, 'Transfer')
                .withArgs(owner.address, safeAddress1.address, testTokens);

            // Check balances and allowances
            expect(await cygnusTerminal.connect(owner).allowance(owner.address, safeAddress1.address)).to.eq(
                MaxUint256.sub(2000),
            );
        });

        it('transferFrom:FAIL {InsufficientAllowance}', async () => {
            await expect(
                cygnusTerminal.connect(safeAddress1).transferFrom(owner.address, safeAddress1.address, testTokens),
            ).to.be.revertedWith(CygnusTerminalErrors.INSUFFICIENT_ALLOWANCE);
        });

        it('Increase Allowance and emit {Approve} event', async () => {
            // Approve Tokens
            await expect(cygnusTerminal.approve(safeAddress1.address, testTokens))
                .to.emit(cygnusTerminal, 'Approval')
                .withArgs(owner.address, safeAddress1.address, testTokens);

            expect(await cygnusTerminal.allowance(owner.address, safeAddress1.address)).to.eq(testTokens);

            // Increase Allowance
            await expect(cygnusTerminal.increaseAllowance(safeAddress1.address, 666)).to.emit(
                cygnusTerminal,
                'Approval',
            );

            // Updated allowance
            expect(await cygnusTerminal.allowance(owner.address, safeAddress1.address)).to.eq(BigInt(testTokens + 666));
        });

        it('Decrease Allowance and emit {Approve} event', async () => {
            // Approve Tokens
            await expect(cygnusTerminal.approve(safeAddress1.address, testTokens))
                .to.emit(cygnusTerminal, 'Approval')
                .withArgs(owner.address, safeAddress1.address, testTokens);

            expect(await cygnusTerminal.allowance(owner.address, safeAddress1.address)).to.eq(testTokens);

            // Decrease Allowance
            await expect(cygnusTerminal.decreaseAllowance(safeAddress1.address, 666)).to.emit(
                cygnusTerminal,
                'Approval',
            );

            // Updated allowance
            expect(await cygnusTerminal.allowance(owner.address, safeAddress1.address)).to.eq(
                BigInt(testTokens) - BigInt(666),
            );
        });
    });

    context('EIP712 niceties', function () {
        // EIP712
        it('DOMAIN_SEPARATOR, PERMIT_TYPEHASH', async () => {
            expect(await cygnusTerminal.DOMAIN_SEPARATOR()).to.eq(getDomainSeparator(name, cygnusTerminal.address));

            expect(await cygnusTerminal.PERMIT_TYPEHASH()).to.eq(
                keccak256(
                    toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
                ),
            );
        });

        it('PermitSignature', async () => {
            // Build permit struct
            const hashStruct = await selfPermit({
                token: cygnusTerminal,

                owner: safeAddress2.address,

                spender: safeAddress3.address,

                value: testTokens,

                deadline: MaxUint256,

                private_key: safeAddress2_privateKey,
            });

            // Allowances
            expect(await cygnusTerminal.allowance(safeAddress2.address, safeAddress3.address)).to.eq(testTokens);
            // ++
            expect(await cygnusTerminal.nonces(safeAddress2.address)).to.eq(1);
        });

        it('PermitSignature:FAIL', async () => {
            // Build permit struct and Fail
            const hashStruct = await expect(
                selfPermit({
                    token: cygnusTerminal,

                    owner: safeAddress2.address,

                    spender: safeAddress3.address,

                    value: testTokens,

                    deadline: MaxUint256,

                    private_key: safeAddress1_privateKey,
                }),
            ).to.be.revertedWith(CygnusTerminalErrors.INVALID_SIGNATURE);
        });
    });
});
