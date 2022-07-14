// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusTerminal } from "./ICygnusTerminal.sol";

/**
 *  @title ICygnusBorrowControl Interface for the control of borrow contracts (interest rate params, reserves, etc.)
 */
interface ICygnusBorrowControl is ICygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error ParameterNotInRange Emitted when trying to update a borrow parameter outside of range allowed
     */
    error CygnusBorrowControl__ParameterNotInRange(uint256 minRange, uint256 maxRange, uint256 value);

    /**
     *  @custom:error BorrowTrackerAlreadySet Emitted when updating the borrow tracker is the zero address
     */
    error CygnusBorrowControl__BorrowTrackerAlreadySet(address currentTracker, address newTracker);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when the borrow tracker is updated by admins
     *  @param oldBorrowTracker The address of the borrow tracker up until this point used for CYG distribution
     *  @param newBorrowTracker The address of the new borrow tracker
     *  @custom:event NewCygnusBorrowTracker Emitted when a new borrow tracker is set set by admins
     */
    event NewCygnusBorrowTracker(address oldBorrowTracker, address newBorrowTracker);

    /**
     *  @notice Logs when the kink utilization rate is updated by admins
     *  @param oldKinkUtilizationRate The kink utilization rate used in this shuttle until this point
     *  @param newKinkUtilizationRate The new kink utilization rate set
     *  @custom:event NewKinkUtilizationRate Emitted when a new kink utilization rate is set set by admins
     */
    event NewKinkUtilizationRate(uint256 oldKinkUtilizationRate, uint256 newKinkUtilizationRate);

    /**
     *  @notice Logs when the reserve factor is updated by admins
     *  @param oldReserveFactor The reserve factor used in this shuttle until this point
     *  @param newReserveFactor The new reserve factor set
     *  @custom:event NewReserveFactor Emitted when a new reserve factor is set set by admins
     */
    event NewReserveFactor(uint256 oldReserveFactor, uint256 newReserveFactor);

    /**
     *  @notice Logs when the base rate is updated by admins
     *  @param oldBaseRatePerYear The base rate per year used in this shuttle until this point
     *  @param newBaseRatePerYear The new base rate set for this shuttle
     *  @custom:event NewBaseRate Emitted when a new base rate is set by admins
     */
    event NewBaseRate(uint256 oldBaseRatePerYear, uint256 newBaseRatePerYear);

    /**
     *  @notice Logs when the kink multiplier is updated by admins
     *  @param oldKinkMultiplier The old kink multiplier used in this shuttle until this point
     *  @param newKinkMultiplier The new kink multiplier set for this shuttle
     *  @custom:event NewKinkMultiplier Emitted when a kink multiplier is set by admins
     */
    event NewKinkMultiplier(uint256 oldKinkMultiplier, uint256 newKinkMultiplier);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ────────────── Important Addresses ─────────────

    /**
     *  @return collateral Address of the collateral contract
     */
    function collateral() external view returns (address);

    /**
     *  @return cygnusBorrowTracker Address of the borrow tracker.
     */
    function cygnusBorrowTracker() external view returns (address);

    // ────────────── Current Pool Rates ──────────────

    /**
     *  @return exchangeRateStored The current exchange rate of tokens
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     *  @return kinkUtilizationRate Current utilization point at which the jump multiplier is applied
     */
    function kinkUtilizationRate() external view returns (uint256);

    /**
     *  @return reserveFactor Percentage of interest that is routed to this market's Reserve Pool
     */
    function reserveFactor() external view returns (uint256);

    /**
     *  @return kinkMultiplier The multiplier that is applied to the interest rate once util > kink
     */
    function kinkMultiplier() external view returns (uint256);

    // ──────────── Min/Max rates allowed ─────────────

    /**
     *  @return BASE_RATE_MAX Maximum base interest rate allowed (20%)
     */
    function BASE_RATE_MAX() external pure returns (uint256);

    /**
     *  @return KINK_UTILIZATION_RATE_MIN Minimum kink utilization point allowed, equivalent to 50%
     */
    function KINK_UTILIZATION_RATE_MIN() external pure returns (uint256);

    /**
     *  @return KINK_UTILIZATION_RATE_MAX Maximum Kink point allowed, equivalent to 95%
     */
    function KINK_UTILIZATION_RATE_MAX() external pure returns (uint256);

    /**
     *  @return RESERVE_FACTOR_MAX The maximum reserve factor allowed, equivalent to 50%
     */
    function RESERVE_FACTOR_MAX() external pure returns (uint256);

    /**
     *  @return KINK_MULTIPLIER_MAX The maximum kink multiplier than can be applied to this shuttle
     */
    function KINK_MULTIPLIER_MAX() external pure returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice 👽
     *  @notice Updates the borrow tracker contract
     *  @param newBorrowTracker The address of the new Borrow tracker
     *  @custom:security non-reentrant
     */
    function setCygnusBorrowTracker(address newBorrowTracker) external;

    /**
     *  @notice 👽
     *  @notice Updates the kink utilization rate for this shuttle
     *  @param newKinkUtilizationRate The new utilization rate at which the jump kultiplier takes effect
     *  @custom:security non-reentrant
     */
    function setKinkUtilizationRate(uint256 newKinkUtilizationRate) external;

    /**
     *  @notice 👽
     *  @notice Updates the reserve factor
     *  @param newReserveFactor The new reserve factor for this shuttle
     *  @custom:security non-reentrant
     */
    function setReserveFactor(uint256 newReserveFactor) external;
}
