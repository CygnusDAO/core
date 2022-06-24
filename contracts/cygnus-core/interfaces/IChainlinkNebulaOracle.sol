// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";
import { IDexPair } from "./IDexPair.sol";

/**
 *  @title IChainlinkNebulaOracle Interface to interact with Cygnus' Chainlink oracle
 */
interface IChainlinkNebulaOracle {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error PairIsInitialized Emitted when attempting to initialize an already initialized LP Token
     */
    error ChainlinkNebulaOracle__PairAlreadyInitialized(address lpTokenPair);

    /**
     *  @custom:error PairNotInitialized Emitted when attempting to get the price of an LP Token that is not initialized
     */
    error ChainlinkNebulaOracle__PairNotInitialized(address lpTokenPair);

    /**
     *  @custom:error MsgSenderNotAdmin Emitted when attempting to access admin only methods
     */
    error ChainlinkNebulaOracle__MsgSenderNotAdmin(address msgSender);

    /**
     *  @custom:error AdminCantBeZero Emitted when attempting to set the admin if the pending admin is the zero address
     */
    error ChainlinkNebulaOracle__AdminCantBeZero(address pendingAdmin);

    /**
     *  @custom:error PendingAdminAlreadySet Emitted when attempting to set the same pending admin twice
     */
    error ChainlinkNebulaOracle__PendingAdminAlreadySet(address pendingAdmin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when a new LP Token is added to this oracle and the price is being tracked
     *  @param initialized Whether or not the LP Token is initialized
     *  @param oracleId The ID for this oracle
     *  @param lpTokenPair The address of the LP Token
     *  @param priceFeedA The address of the Chainlink's aggregator contract for this LP Token's token0
     *  @param priceFeedB The address of the Chainlink's aggregator contract for this LP Token's token1
     *  @custom:event InitializeChainlinkNebula Emitted when an LP Token pair's price starts being tracked
     */
    event InitializeChainlinkNebula(
        bool initialized,
        uint24 oracleId,
        address lpTokenPair,
        AggregatorV3Interface priceFeedA,
        AggregatorV3Interface priceFeedB
    );

    /**
     *  @notice Logs when an LP Token is removed from this oracle, rendering all calls on this LP Token null
     *  @param oracleId The ID for this oracle
     *  @param lpTokenPair The contract address of the LP Token
     *  @param priceFeedA The contract address of Chainlink's aggregator contract for this LP Token's token0
     *  @param priceFeedB The contract address of the Chainlink's aggregator contract for this LP Token's token1
     *  @custom:event DeleteChainlinkNebula Emitted when an LP Token pair is removed from this oracle
     */
    event DeleteChainlinkNebula(
        uint24 oracleId,
        address lpTokenPair,
        AggregatorV3Interface priceFeedA,
        AggregatorV3Interface priceFeedB,
        address msgSender
    );

    /**
     *  @notice Logs when a new pending admin for the oracle is set
     *  @param oracleCurrentAdmin The address of the current oracle admin
     *  @param oraclePendingAdmin The address of the pending oracle admin
     *  @custom:event NewNebulaPendingAdmin Emitted when a new pending admin is set, to be accepted by admin
     */
    event NewOraclePendingAdmin(address oracleCurrentAdmin, address oraclePendingAdmin);

    /**
     *  @notice Logs when a new admin for the oracle is confirmed
     *  @param oracleOldAdmin The address of the old oracle admin
     *  @param oracleNewAdmin The address of the new oracle admin
     *  @custom:event NewNebulaAdmin Emitted when the pending admin is confirmed as the new oracle admin
     */
    event NewOracleAdmin(address oracleOldAdmin, address oracleNewAdmin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Returns the struct record of each oracle used by Cygnus
     *  @param lpTokenPair The address of the LP Token
     *  @return initialized Whether an LP Token is being tracked or not
     *  @return oracleId The ID of the LP Token tracked by the oracle
     *  @return underlying The address of the LP Token
     *  @return priceFeedA The address of the Chainlink aggregator used for this LP Token's Token0
     *  @return priceFeedB The address of the Chainlink aggregator used for this LP Token's Token1
     */
    function getNebula(address lpTokenPair)
        external
        view
        returns (
            bool initialized,
            uint24 oracleId,
            address underlying,
            AggregatorV3Interface priceFeedA,
            AggregatorV3Interface priceFeedB
        );

    /**
     *  @notice Gets the address of the LP Token that (if) is being tracked by this oracle
     *  @param id The ID of each LP Token that is being tracked by this oracle
     *  @return The address of the LP Token if it is being tracked by this oracle, else returns address zero
     */
    function allNebulas(uint256 id) external view returns (address);

    /**
     *  @return The name for this Cygnus-Chainlink Nebula oracle
     */
    function name() external view returns (string memory);

    /**
     *  @return The decimals for this Cygnus-Chainlink Nebula oracle
     */
    function decimals() external view returns (uint8);

    /**
     *  @return The symbol for this Cygnus-Chainlink Nebula oracle
     */
    function symbol() external view returns (string memory);

    /**
     *  @return The address of Chainlink's DAI oracle
     */
    function dai() external view returns (AggregatorV3Interface);

    /**
     *  @return The address of the Cygnus admin
     */
    function admin() external view returns (address);

    /**
     *  @return The address of the new requested admin
     */
    function pendingAdmin() external view returns (address);

    /**
     *  @return The version of this oracle
     */
    function version() external view returns (uint8);

    /**
     *  @return How many LP Token pairs' prices are being tracked by this oracle
     */
    function nebulaSize() external view returns (uint24);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return The price of DAI with 18 decimals
     */
    function daiPrice() external view returns (uint256);

    /**
     *  @notice Gets the latest price of the LP Token denominated in DAI
     *  @notice LP Token pair must be initialized, else reverts with custom error
     *  @param lpTokenPair The address of the LP Token
     *  @return lpTokenPrice The price of the LP Token denominated in DAI
     */
    function lpTokenPriceDai(address lpTokenPair) external view returns (uint256 lpTokenPrice);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Initialize an LP Token pair, only admin
     *  @param lpTokenPair The contract address of the LP Token
     *  @param priceFeedA The contract address of the Chainlink's aggregator contract for this LP Token's token0
     *  @param priceFeedB The contract address of the Chainlink's aggregator contract for this LP Token's token1
     *  @custom:security non-reentrant
     */
    function initializeNebula(
        address lpTokenPair,
        AggregatorV3Interface priceFeedA,
        AggregatorV3Interface priceFeedB
    ) external;

    /**
     *  @notice Deletes an LP token pair from the oracle
     *  @notice After deleting, any call from a shuttle deployed that is using this pair will revert
     *  @param lpTokenPair The contract address of the LP Token to remove from the oracle
     *  @custom:security non-reentrant
     */
    function deleteNebula(address lpTokenPair) external;

    /**
     *  @notice Sets a new pending admin for the Oracle
     *  @param newOraclePendingAdmin Address of the requested Oracle Admin
     */
    function setOraclePendingAdmin(address newOraclePendingAdmin) external;

    /**
     *  @notice Sets a new admin for the Oracle
     */
    function setOracleAdmin() external;
}
