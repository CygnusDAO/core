// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

// Dependencies
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";
import { Context } from "./utils/Context.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { IErc20 } from "./interfaces/IErc20.sol";
import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";
import { IDexPair } from "./interfaces/IDexPair.sol";

/**
 *  @title  ChainlinkNebulaOracle
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in DAI. In case need
 *          different implementation just update the denomination variable `dai` with another price feed
 *  @notice Implementation of fair lp token pricing using Chainlink price feeds
 *          https://blog.alphaventuredao.io/fair-lp-token-pricing/
 */
contract ChainlinkNebulaOracle is IChainlinkNebulaOracle, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice returns the struct record of each oracle used by Cygnus
     *  @custom:struct Official record of all Chainlink oracles used by Cygnus
     *  @custom:member initialized Whether an LP Token is being tracked or not
     *  @custom:member oracleId The ID of the LP Token tracked by the oracle
     *  @custom:member underlying The address of the LP Token
     *  @custom:member priceFeedA The address of the Chainlink aggregator used for this LP Token's Token0
     *  @custom:member priceFeedB The address of the Chainlink aggregator used for this LP Token's Token1
     */
    struct ChainlinkNebula {
        bool initialized;
        uint24 oracleId;
        address underlying;
        AggregatorV3Interface priceFeedA;
        AggregatorV3Interface priceFeedB;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    mapping(address => ChainlinkNebula) public override getNebula;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    address[] public override allNebulas;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    string public constant override name = "Cygnus-Chainlink: LP Oracle";

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    string public constant override symbol = "CygNebula";

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    uint8 public constant override decimals = 18;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    uint8 public constant override version = 1;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    AggregatorV3Interface public immutable override dai;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    address public override admin;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    address public override pendingAdmin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Oracle
     *  @param priceDenominator The denomination token this oracle returns the price in
     */
    constructor(AggregatorV3Interface priceDenominator) {
        // Assign admin
        admin = _msgSender();

        // Assign the denomination the LP Token will be priced in
        dai = AggregatorV3Interface(priceDenominator);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Modifier for admin control only 👽
     */
    modifier cygnusAdmin() {
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for admin control only 👽
     */
    function isCygnusAdmin() internal view {
        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (_msgSender() != admin) {
            revert ChainlinkNebulaOracle__MsgSenderNotAdmin(_msgSender());
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function nebulaSize() public view override returns (uint24) {
        return uint24(allNebulas.length);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function daiPrice() external view override returns (uint256 latestPriceDai) {
        // Chainlink price feed for the LP denomination token, in our case DAI
        (, int256 latestDaiPrice, , , ) = dai.latestRoundData();

        // Adjust dai price to 18 decimals and return price
        latestPriceDai = uint256(latestDaiPrice) * 10**(decimals - dai.decimals());
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function lpTokenPriceDai(address lpTokenPair) external view override returns (uint256 lpTokenPrice) {
        // Load to memory
        ChainlinkNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert ChainlinkNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get reserves of Token A and Token B to compute k
        (
            uint112 reservesTokenA,
            uint112 reservesTokenB, /* Timestamp */

        ) = IDexPair(lpTokenPair).getReserves();

        // 2. Get total supply of the underlying LP Token
        uint256 totalSupply = IDexPair(lpTokenPair).totalSupply();

        // Adjust reserves Token A
        uint256 adjustedReservesA = reservesTokenA *
            (10**(decimals - IErc20(IDexPair(lpTokenPair).token0()).decimals()));

        // Adjust reserves Token B
        uint256 adjustedReservesB = reservesTokenB *
            (10**(decimals - IErc20(IDexPair(lpTokenPair).token1()).decimals()));

        // 3. Geometric mean of reservesA and reservesB
        uint256 productReserves = adjustedReservesA.gm(adjustedReservesB);

        // Chainlink price feed for this lpTokens token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Chainlink price feed for this lpTokens token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Chainlink price feed for denomination token, in cygnus' case DAI
        (, int256 latestDaiPrice, , , ) = dai.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = uint256(priceA) * 10**(decimals - cygnusNebula.priceFeedA.decimals());

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = uint256(priceB) * 10**(decimals - cygnusNebula.priceFeedB.decimals());

        // Adjust dai price to 18 decimals
        uint256 adjustedDaiPrice = uint256(latestDaiPrice) * 10**(decimals - dai.decimals());

        // 4. Geometric mean of priceA and priceB
        uint256 productPrice = adjustedPriceA.gm(adjustedPriceB);

        // LP Token price denominated in USD
        uint256 lpTokenPriceUSD = PRBMath.mulDiv(productReserves, productPrice, totalSupply) * 2;

        // 5. Return LP Token price denominated in DAI
        lpTokenPrice = lpTokenPriceUSD.div(adjustedDaiPrice);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function initializeNebula(
        address lpTokenPair,
        AggregatorV3Interface aggregatorA,
        AggregatorV3Interface aggregatorB
    ) external override cygnusAdmin nonReentrant {
        // Load to storage
        ChainlinkNebula storage cygnusNebula = getNebula[lpTokenPair];

        /// @custom:error PairIsinitialized Avoid duplicate oracle
        if (cygnusNebula.initialized) {
            revert ChainlinkNebulaOracle__PairAlreadyInitialized(lpTokenPair);
        }

        // Add to list
        allNebulas.push(lpTokenPair);

        // This pair's id
        uint24 pairId = nebulaSize();

        // Assign id
        cygnusNebula.oracleId = pairId;

        // Store LP Token address
        cygnusNebula.underlying = lpTokenPair;

        // Store the chainlink's aggregator contract address for this LP Token's token0
        cygnusNebula.priceFeedA = aggregatorA;

        // Store the chainlink's aggregator contract address for this LP Token's token1
        cygnusNebula.priceFeedB = aggregatorB;

        // Store oracle status
        cygnusNebula.initialized = true;

        /// @custom:event InitializeChainlinkNebula
        emit InitializeChainlinkNebula(true, pairId, lpTokenPair, aggregatorA, aggregatorB);
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function deleteNebula(address lpTokenPair) external override cygnusAdmin nonReentrant {
        /// @custom:error PairNotinitialized Avoid delete if not initialized
        if (!getNebula[lpTokenPair].initialized) {
            revert ChainlinkNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Get the index of this oracle
        uint24 oracleId = getNebula[lpTokenPair].oracleId;

        // Get the first price feed for this oracle
        AggregatorV3Interface priceFeedA = getNebula[lpTokenPair].priceFeedA;

        // Get the second price feed for this oracle
        AggregatorV3Interface priceFeedB = getNebula[lpTokenPair].priceFeedB;

        // Delete from array leaving a gap as to not mix up IDs
        delete allNebulas[oracleId - 1];

        // Delete from object
        delete getNebula[lpTokenPair];

        /// @custom:event DeleteChainlinkNebula
        emit DeleteChainlinkNebula(oracleId, lpTokenPair, priceFeedA, priceFeedB, _msgSender());
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function setOraclePendingAdmin(address newOracleAdmin) external override cygnusAdmin nonReentrant {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newOracleAdmin == pendingAdmin) {
            revert ChainlinkNebulaOracle__PendingAdminAlreadySet(newOracleAdmin);
        }

        // Assign address of the requested admin
        pendingAdmin = newOracleAdmin;

        /// @custom:event NewOraclePendingAdmin
        emit NewOraclePendingAdmin(admin, newOracleAdmin);
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function setOracleAdmin() external override cygnusAdmin nonReentrant {
        /// @custom:error AdminCantBeZero Avoid settings the admin to the zero address
        if (pendingAdmin == address(0)) {
            revert ChainlinkNebulaOracle__AdminCantBeZero(pendingAdmin);
        }

        // Address of the Admin up until now
        address oldAdmin = admin;

        // Assign new admin
        admin = pendingAdmin;

        // Gas refund
        delete pendingAdmin;

        // @custom:event NewOracleAdmin
        emit NewOracleAdmin(oldAdmin, admin);
    }
}
