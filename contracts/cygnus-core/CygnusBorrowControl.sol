// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowControl } from "./interfaces/ICygnusBorrowControl.sol";
import { CygnusTerminal } from "./CygnusTerminal.sol";

// Interfaces
import { ICygnusAlbireo } from "./interfaces/ICygnusAlbireo.sol";

/**
 *  @title  CygnusBorrowControl Contract for controlling borrow settings like interest base rate, kink utilization, etc.
 *  @author CygnusDAO
 *  @notice Initializes Borrow Arm. Passes name, symbol and decimals to CygnusTerminal for the CygDAI Token
 */
contract CygnusBorrowControl is ICygnusBorrowControl, CygnusTerminal("Cygnus: Borrow", "CygDAI", 18) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ───────────────────── Important Addresses  ──────────────────────

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public immutable override collateral;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public override cygnusBorrowTracker;

    // ────────────────────── Current pool rates  ───────────────────────

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override exchangeRateStored;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override multiplierPerYear;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override baseRatePerYear;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override jumpMultiplierPerYear;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override kink;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override reserveFactor = 0.05e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override kinkMultiplier = 2;

    // ──────────────────── Min/Max this pool allows  ────────────────────

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public constant override BASE_RATE_MAX = 0.15e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public constant override KINK_RATE_MIN = 0.50e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public constant override KINK_RATE_MAX = 0.95e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public constant override RESERVE_FACTOR_MAX = 0.20e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public constant override KINK_MULTIPLIER_MAX = 20;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Borrow arm of the pool. It assigns the factory, the underlying asset (DAI) and the
     *          collateral contract for this borrow token. Aside from this is assigns the custom interest rate model
     *          from the deployment: base rate, multiplier and the kink utilization rate.
     */
    constructor() {
        // Get factory, underlying and collateral addressand interest rate parameters for this shuttle
        (hangar18, underlying, collateral, baseRatePerYear, multiplierPerYear, kink) = ICygnusAlbireo(_msgSender())
            .borrowParameters();

        // Match initial exchange rate
        exchangeRateStored = INITIAL_EXCHANGE_RATE;

        // Assurance
        totalSupply = 0;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks if new parameter is within range when updating interest rate model
     *  @param min The minimum value allowed for the parameter that is being updated
     *  @param max The maximum value allowed for the parameter that is being updated
     *  @param parameter The value of the parameter that is being updated
     */
    function validRange(
        uint256 min,
        uint256 max,
        uint256 parameter
    ) internal pure {
        /// @custom:error Avoid outside range
        if (parameter < min || parameter > max) {
            revert CygnusBorrowControl__ParameterNotInRange({ minRange: min, maxRange: max, value: parameter });
        }
    }

    /**
     *  @return The uint32 block timestamp
     */
    function getBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant
     */
    function setCygnusBorrowTracker(address newBorrowTracker) external override cygnusAdmin nonReentrant {
        /// @custom:error BorrowTrackerAlreadySet Avoid Duplicate
        if (newBorrowTracker == cygnusBorrowTracker) {
            revert CygnusBorrowControl__BorrowTrackerAlreadySet({
                currentTracker: cygnusBorrowTracker,
                newTracker: newBorrowTracker
            });
        }

        // Old borrow tracker
        address oldBorrowTracker = cygnusBorrowTracker;

        // Checks admin before, assign borrow tracker
        cygnusBorrowTracker = newBorrowTracker;

        /// @custom:event NewCygnusBorrowTracker
        emit NewCygnusBorrowTracker(oldBorrowTracker, newBorrowTracker);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant
     */
    function setReserveFactor(uint256 newReserveFactor) external override cygnusAdmin nonReentrant {
        // Check if parameter is within range allowed
        validRange(0, RESERVE_FACTOR_MAX, newReserveFactor);

        // Old reserve factor
        uint256 oldReserveFactor = reserveFactor;

        // Update reserve factor
        reserveFactor = newReserveFactor;

        /// @custom:event NewReserveFactor
        emit NewReserveFactor(oldReserveFactor, newReserveFactor);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant
     */
    function setKinkUtilizationRate(uint256 newKinkUtilizationRate) external override cygnusAdmin nonReentrant {
        // Check if parameter is within range allowed
        validRange(KINK_RATE_MIN, KINK_RATE_MAX, newKinkUtilizationRate);

        // Old kink utilization rate
        uint256 oldKinkUtilizationRate = kink;

        // Update kink utilization rate
        kink = newKinkUtilizationRate;

        /// @custom:event NewKinkUtilizationRate
        emit NewKinkUtilizationRate(oldKinkUtilizationRate, newKinkUtilizationRate);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant
     */
    function setKinkMultiplier(uint256 newKinkMultiplier) external override cygnusAdmin nonReentrant {
        // Check if parameter is within range allowed
        validRange(0, KINK_MULTIPLIER_MAX, newKinkMultiplier);

        // Old kink multiplier
        uint256 oldKinkMultiplier = kinkMultiplier;

        // Update kink multiplier
        kinkMultiplier = newKinkMultiplier;

        /// @custom:event NewKinkMultiplier
        emit NewKinkMultiplier(oldKinkMultiplier, newKinkMultiplier);
    }
}
