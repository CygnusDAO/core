// Hardhat
const chai = require('chai');
const hre = require('hardhat');
const { solidity } = require('ethereum-waffle');
const { expect } = chai;

// Node
const fs = require('fs');
const path = require('path');

const { ChainlinkNebulaErrors } = require('./errors/ChainlinkNebulaErrors.js');

chai.use(solidity);

// Checks the price the oracle returns vs the fair LP price vs the normal lp token price
// Fork c-chain and update eth/usdc/avax prices
describe('Cygnus-Chainlink: LP Fair Price Oracle', function () {
    // LP Tokens to run the tests
    // The denomination token the price oracle returns the price in
    const daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // Check all with 99% precision
    const rangeMin = BigInt(0.995e18);

    const rangeMax = BigInt(1.005e18);

    const oneMantissa = BigInt(1e18);

    const max = ethers.constants.MaxUint256;

    const AddressZero = ethers.constants.AddressZero;

    const lpTokenAbi = fs.readFileSync(path.resolve(__dirname, './abis/lptoken.json')).toString();

    const daiAbi = fs.readFileSync(path.resolve(__dirname, './abis/dai.json')).toString();

    /*  ─────────────────────────────────────────────────── Test Case 1 ───────────────────────────────────────────────────  */

    // https://snowtrace.io/address/0x454E67025631C065d3cFAD6d71E6892f74487a15
    const joeAvaxLP = '0x454E67025631C065d3cFAD6d71E6892f74487a15';

    // https://snowtrace.io/address/0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a
    const joeAggregator = '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a';

    // https://snowtrace.io/address/0x0A77230d17318075983913bC2145DB16C7366156
    const avaxAggregator = '0x0A77230d17318075983913bC2145DB16C7366156';

    // price and fair price
    let joeAvaxPrice;

    let joeAvaxFairPrice;

    let joeReserves;

    let avaxReserves;

    let joeAvaxTotalSupply;

    async function joeAvaxPx() {
        /*
         *  Get the total supply and reserves of each token0 and token1 from dex to calculate price
         *
         */
        const LPTokenJoeAvax = new ethers.Contract('0x454E67025631C065d3cFAD6d71E6892f74487a15', lpTokenAbi, owner);

        const reserves = await LPTokenJoeAvax.getReserves();

        joeAvaxTotalSupply = Number(BigInt(await LPTokenJoeAvax.totalSupply()) / BigInt(1e18));

        joeReserves = Number(BigInt(reserves._reserve0) / BigInt(1e18));

        avaxReserves = Number(BigInt(reserves._reserve1) / BigInt(1e18));

        // off chain price
        joeAvaxPrice = BigInt(((joePrice * joeReserves + avaxPrice * avaxReserves) / joeAvaxTotalSupply) * 1e18);

        // off chain fair price / cygnus oracle price
        joeAvaxFairPrice = BigInt(
            ((Math.sqrt(joeReserves * avaxReserves) * Math.sqrt(joePrice * avaxPrice)) / joeAvaxTotalSupply) * 2 * 1e18,
        );
    }

    /*  ─────────────────────────────────────────────────── Test Case 2 ───────────────────────────────────────────────────  */

    // https://snowtrace.io/address/0xFE15c2695F1F920da45C30AAE47d11dE51007AF9
    const ethAvaxLP = '0xFE15c2695F1F920da45C30AAE47d11dE51007AF9';

    // https://snowtrace.io/address/0x976B3D034E162d8bD72D6b9C989d545b839003b0
    const ethAggregator = '0x976B3D034E162d8bD72D6b9C989d545b839003b0';

    // price and fair price
    let ethAvaxPrice;

    let ethAvaxFairPrice;

    async function ethAvaxPx() {
        /*
         *  Get the total supply and reserves of each token0 and token1 from dex to calculate price
         *
         */
        const LPTokenEthAvax = new ethers.Contract('0xFE15c2695F1F920da45C30AAE47d11dE51007AF9', lpTokenAbi, owner);

        const reserves = await LPTokenEthAvax.getReserves();

        const ethAvaxTotalSupply = Number(BigInt(await LPTokenEthAvax.totalSupply()) / BigInt(1e18));

        const ethReserves = Number(BigInt(reserves._reserve0) / BigInt(1e18));

        const avaxReservesB = Number(BigInt(reserves._reserve1) / BigInt(1e18));

        // off chain price
        ethAvaxPrice = BigInt(((ethPrice * ethReserves + avaxPrice * avaxReservesB) / ethAvaxTotalSupply) * 1e18);

        // off chain fair price / cygnus oracle price
        ethAvaxFairPrice = BigInt(
            ((Math.sqrt(ethReserves * avaxReservesB) * Math.sqrt(ethPrice * avaxPrice)) / ethAvaxTotalSupply) *
                2 *
                1e18,
        );
    }

    /*  ─────────────────────────────────────────────────── Test Case 3 ───────────────────────────────────────────────────  */

    // https://snowtrace.io/address/0xa389f9430876455c36478deea9769b7ca4e3ddb1
    const usdcAvaxLP = '0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1';

    // https://snowtrace.io/address/0xF096872672F44d6EBA71458D74fe67F9a77a23B9
    const usdcAggregator = '0xF096872672F44d6EBA71458D74fe67F9a77a23B9';

    let usdcAvaxPrice;

    let usdcAvaxFairPrice;

    async function usdcAvaxPx() {
        /*
         *  Get the total supply and reserves of each token0 and token1 from dex to calculate price
         *
         */
        const LPTokenUsdcAvax = new ethers.Contract('0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1', lpTokenAbi, owner);

        const reserves = await LPTokenUsdcAvax.getReserves();

        // Update manually or throws errors, usdc
        const totalSupply = 0.696213;

        // usdc adjust
        const usdcReserves = Number((BigInt(reserves._reserve0) * BigInt(10 ** (18 - 6))) / BigInt(1e18));

        const avaxReservesC = Number(BigInt(reserves._reserve1) / BigInt(1e18));

        // off chain price
        usdcAvaxPrice = BigInt(((usdcPrice * usdcReserves + avaxPrice * avaxReservesC) / totalSupply) * 1e18);

        // off chain fair price / cygnus oracle price
        usdcAvaxFairPrice = BigInt(
            ((Math.sqrt(usdcReserves * avaxReservesC) * Math.sqrt(usdcPrice * avaxPrice)) / totalSupply) * 2 * 1e18,
        );
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*
     * UPDATE TO CURRENT PRICE to do fair price and normal price calculations against the on-chain price the oracle returns
     *
     */
    const joePrice = 0.256483;

    const avaxPrice = 19.71;

    const ethPrice = 1231.36;

    const usdcPrice = 1;

    let owner, user, cygnusOracle;

    before(async () => {
        // Admin and user
        [owner, user] = await ethers.getSigners();

        // Oracle
        const CygnusOracle = await ethers.getContractFactory('ChainlinkNebulaOracle');

        cygnusOracle = await CygnusOracle.deploy(daiAggregator);

        //console.log('Nebula Oracle:', cygnusOracle.address);
    });

    describe('Default oracle state', function () {
        /*
         *  Default oracle state
         */
        it('name', async () => {
            expect(await cygnusOracle.name()).to.eq('Cygnus-Chainlink: LP Oracle');
        });

        it('symbol', async () => {
            expect(await cygnusOracle.symbol()).to.eq('CygNebula');
        });

        it('decimals', async () => {
            expect(await cygnusOracle.decimals()).to.eq(18);
        });

        it('checks admin is deployer', async () => {
            expect(await cygnusOracle.admin()).to.eq(owner.address);
        });

        it('checks pending admin is zero', async () => {
            expect(await cygnusOracle.pendingAdmin()).to.eq(AddressZero);
        });
    });

    describe('Checks oracle price before initializing', function () {
        /*
         *  Oracles must be initialized to return the price.
         *  A shuttle can't be deployed unless the price oracle for that collateral is initialized in oracle contract,
         *  else deployment from factory will revert.
         *
         */
        it('Checks JOE/AVAX LP fair price before initializing pair: FAIL { ChainlinkNebulaOracle__PairNotInitialized }', async () => {
            await expect(cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_NOT_INITIALIZED,
            );
        });

        it('Checks ETH/AVAX LP fair price before initializing pair: FAIL { ChainlinkNebulaOracle__PairNotInitialized }', async () => {
            await expect(cygnusOracle.lpTokenPriceDai(ethAvaxLP)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_NOT_INITIALIZED,
            );
        });

        it('Checks USDc/AVAX LP fair price before initializing pair: FAIL { ChainlinkNebulaOracle__PairNotInitialized }', async () => {
            await expect(cygnusOracle.lpTokenPriceDai(usdcAvaxLP)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_NOT_INITIALIZED,
            );
        });
    });

    describe('Non-Admin initializes oracle Pair', function () {
        /*
         *  Non-admin attempts to initialize oracles, each tx should revert
         *
         */
        it('Initializes JOE/AVAX LP Token: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(
                cygnusOracle.connect(user).initializeNebula(joeAvaxLP, joeAggregator, avaxAggregator),
            ).to.be.revertedWith(ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN);
        });

        it('Initializes ETH/AVAX LP Token: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(
                cygnusOracle.connect(user).initializeNebula(ethAvaxLP, ethAggregator, avaxAggregator),
            ).to.be.revertedWith(ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN);
        });

        it('Initializes USDc/AVAX LP Token: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(
                cygnusOracle.connect(user).initializeNebula(usdcAvaxLP, usdcAggregator, avaxAggregator),
            ).to.be.revertedWith(ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN);
        });
    });

    describe('Admin initializes oracle pair', function () {
        /*
         *  Admin initializes 3 pairs all from traderjoe for simplicity:
         *  - JOE/AVAX
         *  - ETH/AVAX
         *  - USDC/AVAX
         *
         *  Once initialized it emits an event with arguments  initialized, oracle ID and chainlink aggregators
         *  addresses.
         *
         *  Order of aggregators doesn't matter as the oracle calculates the geometric mean of prices
         *  and reserves.
         *
         */
        it('Initializes JOE/AVAX LP Token and emits { InitializeChainlinkNebula } with arguments (true, id, lpToken, aggregatorA, aggregatorB)', async () => {
            await expect(cygnusOracle.initializeNebula(joeAvaxLP, joeAggregator, avaxAggregator))
                .to.emit(cygnusOracle, 'InitializeChainlinkNebula')
                .withArgs(true, 1, joeAvaxLP, joeAggregator, avaxAggregator);
        });

        it('Initializes ETH/AVAX LP Token and emits { InitializeChainlinkNebula } with arguments (true, id, lpToken, aggregatorA, aggregatorB)', async () => {
            await expect(cygnusOracle.initializeNebula(ethAvaxLP, ethAggregator, avaxAggregator))
                .to.emit(cygnusOracle, 'InitializeChainlinkNebula')
                .withArgs(true, 2, ethAvaxLP, ethAggregator, avaxAggregator);
        });

        it('Initializes USDc/AVAX LP Token and emits { InitializeChainlinkNebula } with arguments (true, id, lpToken, aggregatorA, aggregatorB)', async () => {
            await expect(cygnusOracle.initializeNebula(usdcAvaxLP, usdcAggregator, avaxAggregator))
                .to.emit(cygnusOracle, 'InitializeChainlinkNebula')
                .withArgs(true, 3, usdcAvaxLP, usdcAggregator, avaxAggregator);
        });
    });

    describe('Admin initializes oracle pair that is already initialized', function () {
        /*
         *  Tries to initialize already live oracle, reverts. Doesn't matter if aggregators are not sorted
         *  as it only checks the underlying LP token address
         *
         */
        it('Initializes JOE/AVAX LP Token: FAIL { ChainlinkNebulaOracle__PairAlreadyInitialized }', async () => {
            await expect(cygnusOracle.initializeNebula(joeAvaxLP, joeAggregator, avaxAggregator)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_ALREADY_INITIALIZED,
            );
        });

        it('Initializes ETH/AVAX LP Token: FAIL { ChainlinkNebulaOracle__PairAlreadyInitialized }', async () => {
            await expect(cygnusOracle.initializeNebula(ethAvaxLP, ethAggregator, avaxAggregator)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_ALREADY_INITIALIZED,
            );
        });

        it('Initializes USDc/AVAX LP Token: FAIL { ChainlinkNebulaOracle__PairAlreadyInitialized }', async () => {
            await expect(cygnusOracle.initializeNebula(usdcAvaxLP, usdcAggregator, avaxAggregator)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_ALREADY_INITIALIZED,
            );
        });
    });

    describe('Assigning a new admin', function () {
        /*
         *  Assigns a new oracle admin. Oracle admin is the only one who can update pairs by passing the
         *  underlying lp token address + chainlink aggregators.
         *  First sets a pending admin and emits event, and then must call the `setNewOracleAdmin` function
         *  to set the new oracle admin.
         */
        it('Non-Admin assigns a pending admin: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(cygnusOracle.connect(user).setOraclePendingAdmin(user.address)).to.be.revertedWith(
                ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN,
            );
        });

        it('Admin sets a new pending admin without new pending admin: FAIL { ChainlinkNebulaOracle__AdminCantBeZero }', async () => {
            await expect(cygnusOracle.setOracleAdmin()).to.be.revertedWith(
                ChainlinkNebulaErrors.ADMIN_CANT_BE_ADDRESSZERO,
            );
        });

        it('Admin sets a new admin and emits { NewOraclePendingAdmin } with arguments (admin, pendingAdmin)', async () => {
            await expect(cygnusOracle.connect(owner).setOraclePendingAdmin(user.address))
                .to.emit(cygnusOracle, 'NewOraclePendingAdmin')
                .withArgs(owner.address, user.address);
        });

        it('Non-Admin sets a new admin: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(cygnusOracle.connect(user).setOracleAdmin()).to.be.revertedWith(
                ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN,
            );
        });

        it('Admin sets a new admin and emits { NewOracleAdmin } with arguments (oldAdmin, newAdmin)', async () => {
            await expect(cygnusOracle.setOracleAdmin())
                .to.emit(cygnusOracle, 'NewOracleAdmin')
                .withArgs(owner.address, user.address);
        });

        it('Old admin sets a new admin: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(cygnusOracle.setOraclePendingAdmin(owner.address)).to.be.revertedWith(
                ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN,
            );
        });
    });

    describe("Getting the LP Token's fair price (how much 1 LP Token is worth in DAI)", async () => {
        /*
         *  Poke oracle to get the price of 1 LP Token denominated in DAI
         *  First checks against the normal price formula (pa * ra + pb * rb)/totalSupply
         *  Then checks against the fair price formula used by oracle vs the fair price formula
         *  computed above. If price oracle == normal price formula && fair price formula then good
         *
         */
        it('Gets the price from oracle for JOE/AVAX LP Token in DAI vs off-chain calculated price', async () => {
            await joeAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.within(
                (joeAvaxPrice * rangeMin) / oneMantissa,
                (joeAvaxPrice * rangeMax) / oneMantissa,
            );
        });

        it('Gets the price from oracle for JOE/AVAX LP Token in DAI vs off-chain calculated fair price', async () => {
            await joeAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.within(
                (joeAvaxFairPrice * rangeMin) / oneMantissa,
                (joeAvaxFairPrice * rangeMax) / oneMantissa,
            );
        });

        it('Gets the price from oracle for ETH/AVAX LP Token in DAI vs off-chain calculated price', async () => {
            await ethAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(ethAvaxLP)).to.be.within(
                (ethAvaxPrice * rangeMin) / oneMantissa,
                (ethAvaxPrice * rangeMax) / oneMantissa,
            );
        });

        it('Gets the price from oracle for ETH/AVAX LP Token in DAI vs off-chain calculated fair price', async () => {
            await ethAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(ethAvaxLP)).to.be.within(
                (ethAvaxFairPrice * rangeMin) / oneMantissa,
                (ethAvaxFairPrice * rangeMax) / oneMantissa,
            );
        });

        it('Gets the price from oracle for USDc/AVAX LP Token in DAI vs off-chain calculated price (18 decimals check usdc.)', async () => {
            await usdcAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(usdcAvaxLP)).to.be.within(
                (usdcAvaxPrice * rangeMin) / oneMantissa,
                (usdcAvaxPrice * rangeMax) / oneMantissa,
            );
        });

        it('Gets the price from oracle for USDc/AVAX LP Token in DAI vs off-chain calculated fair price (18 decimals check usdc.)', async () => {
            await usdcAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(usdcAvaxLP)).to.be.within(
                (usdcAvaxFairPrice * rangeMin) / oneMantissa,
                (usdcAvaxFairPrice * rangeMax) / oneMantissa,
            );
        });
    });

    describe('Deleting LP pairs from the oracle and adding them back', async () => {
        /*
         *  Deletes an LP Token from the oracle rendering any call to it null.
         *  Oracle admin is still `user` so first set pending admin as `owner`
         *  and accept `owner` as new admin, then delete oracles.
         *
         */
        it('Owner (previous admin) deletes an LP Token pair from the oracle: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(cygnusOracle.deleteNebula(joeAvaxLP)).to.be.revertedWith(
                ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN,
            );
        });

        it('User assigns owner as pendingAdmin to give back the admin role and emits { NewOraclePendingAdmin }', async () => {
            await expect(cygnusOracle.connect(user).setOraclePendingAdmin(owner.address))
                .to.emit(cygnusOracle, 'NewOraclePendingAdmin')
                .withArgs(user.address, owner.address);
        });

        it('User sets owner as the new admin and emits { NewOracleAdmin }', async () => {
            await expect(cygnusOracle.connect(user).setOracleAdmin())
                .to.emit(cygnusOracle, 'NewOracleAdmin')
                .withArgs(user.address, owner.address);
        });

        it('Owner deletes an LP token pair from the oracle and emits { DeleteChainlinkNebula }', async () => {
            await expect(cygnusOracle.deleteNebula(joeAvaxLP))
                .to.emit(cygnusOracle, 'DeleteChainlinkNebula')
                .withArgs(1, joeAvaxLP, joeAggregator, avaxAggregator, owner.address);
        });

        it('Checks that the first slot in array (JOE/AVAX LP) is deleted and is address(0)', async () => {
            // Check that deleted is address(0)
            expect(await cygnusOracle.allNebulas(0)).to.eq(AddressZero);

            expect(await cygnusOracle.allNebulas(1)).to.eq(ethAvaxLP);

            expect(await cygnusOracle.allNebulas(2)).to.eq(usdcAvaxLP);

            // Still 3 slots to avoid duplicating IDs
            expect(await cygnusOracle.nebulaSize()).to.eq(3);

            // Get object
            let deletedOracle = await cygnusOracle.getNebula(joeAvaxLP);

            expect(await deletedOracle.initialized).to.be.eq(false);
        });

        it('Gets the price from oracle for deleted pair: FAIL { ChainlinkNebulaOracle__PairNotInitialized } ', async () => {
            await expect(cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.revertedWith(
                ChainlinkNebulaErrors.PAIR_NOT_INITIALIZED,
            );
        });

        it('Non-Admin initializes deleted oracle: FAIL { ChainlinkNebulaOracle__MsgSenderNotAdmin }', async () => {
            await expect(
                cygnusOracle.connect(user).initializeNebula(joeAvaxLP, joeAggregator, avaxAggregator),
            ).to.be.revertedWith(ChainlinkNebulaErrors.MSG_SENDER_NOT_ADMIN);
        });

        it('Admin initializes deleted oracle again and emits { InitializedChainlinkOracle }', async () => {
            await expect(cygnusOracle.initializeNebula(joeAvaxLP, joeAggregator, avaxAggregator))
                .to.emit(cygnusOracle, 'InitializeChainlinkNebula')
                .withArgs(true, 4, joeAvaxLP, joeAggregator, avaxAggregator);

            expect(await cygnusOracle.nebulaSize()).to.be.eq(4);
        });

        it('Gets the price from oracle for the new JOE/AVAX LP Token in DAI vs off-chain calculated price', async () => {
            await joeAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.within(
                (joeAvaxPrice * rangeMin) / oneMantissa,
                (joeAvaxPrice * rangeMax) / oneMantissa,
            );
        });

        it('Gets the price from oracle for the new JOE/AVAX LP Token in DAI vs off-chain calculated fair price', async () => {
            await joeAvaxPx();

            expect(await cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.within(
                (joeAvaxFairPrice * rangeMin) / oneMantissa,
                (joeAvaxFairPrice * rangeMax) / oneMantissa,
            );
        });
    });

    describe("Getting the LP Token's price with reserves manipulation", function () {
        /*
         *  We simulate what the oracle would calculate when we move along the AMM curve
         *  due to reserves manipulation against the price the oracle currently calculates (on chain).
         *  If LP Token price is the same, then swaps do not change the price of the LP Token, preventing attacks
         *  such as flash loans that move along constant AMM curves.
         *
         *  TO DO (for personal test, not needed): simulate flashLoanV2 with hardhatImpersonateAccount
         */
        it('Prevents LP price manipulations from flash-loans, etc.', async () => {
            await joeAvaxPx();

            // Manipulates reserves
            const joeReservesMxx = joeReserves * 12.5;

            const avaxReservesMxx = avaxReserves / 12.5;

            // ~ $40 each LP Token
            joeAvaxPrice = BigInt(
                ((joePrice * joeReservesMxx + avaxPrice * avaxReservesMxx) / joeAvaxTotalSupply) * 1e18,
            );

            // Off chain fair price / cygnus oracle price ~ $6.40 each LP Token
            joeAvaxFairPrice = BigInt(
                ((Math.sqrt(joeReservesMxx * avaxReservesMxx) * Math.sqrt(joePrice * avaxPrice)) / joeAvaxTotalSupply) *
                    2 *
                    1e18,
            );

            // Check if fair price we calculated with manipulated reserves is the same as the oracle's price
            expect(await cygnusOracle.lpTokenPriceDai(joeAvaxLP)).to.be.within(
                (joeAvaxFairPrice * rangeMin) / oneMantissa,
                (joeAvaxFairPrice * rangeMax) / oneMantissa,
            );
        });
    });
});
