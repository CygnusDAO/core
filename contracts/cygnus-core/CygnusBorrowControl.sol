// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusBorrowControl} from "./interfaces/ICygnusBorrowControl.sol";
import {CygnusTerminal} from "./CygnusTerminal.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";

/**
 *  @title  CygnusBorrowControl Contract for controlling borrow settings
 *  @author CygnusDAO
 *  @notice Initializes Borrow Arm. Assigns name, symbol and decimals to CygnusTerminal for the CygUSD Token.
 *          This contract should be the only contract the Cygnus admin has control of, specifically to set the
 *          borrow tracker which tracks individual borrows to reward users in any token (if there is any),
 *          the reserve factor and the kink utilization rate.
 *
 *          The constructor stores the collateral address this pool is linked with, and only this address can
 *          be used as collateral to borrow this contract`s underlying.
 */
contract CygnusBorrowControl is ICygnusBorrowControl, CygnusTerminal("Cygnus: Borrowable", "", 0) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */
    /**
     *  @custom:library PRBMathUD60x18 for uint256 fixed point math, also imports the main library `PRBMath`.
     */
    using FixedPointMathLib for uint256;

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    // ────────────────────── Min/Max this pool allows

    /**
     *  @notice Maximum base interest rate allowed (10%)
     */
    uint256 private constant BASE_RATE_MAX = 0.10e18;

    /**
     *  @notice Maximum reserve factor that the protocol can keep as reserves (20%)
     */
    uint256 private constant RESERVE_FACTOR_MAX = 0.20e18;

    /**
     *  @notice Minimum kink utilization point allowed (50%)
     */
    uint256 private constant KINK_UTILIZATION_RATE_MIN = 0.50e18;

    /**
     *  @notice Maximum Kink point allowed (95%)
     */
    uint256 private constant KINK_UTILIZATION_RATE_MAX = 0.95e18;

    /**
     *  @notice Maximum Kink multiplier
     */
    uint256 private constant KINK_MULTIPLIER_MAX = 10;

    /**
     *  @notice Used to calculate the per second interest rates
     */
    uint256 private constant SECONDS_PER_YEAR = 31536000;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ──────────────────────────── Important Addresses

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public immutable override collateral;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public override cygnusBorrowRewarder;

    // ───────────────────────────── Current pool rates

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override reserveFactor = 0.10e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override baseRatePerSecond;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override multiplierPerSecond;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override jumpMultiplierPerSecond;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override kinkUtilizationRate = 0.85e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override kinkMultiplier = 2;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Borrow arm of the pool. It assigns the underlying asset (stablecoin),
     *          the collateral for this contract and their lending pool ID. Interest rate parameters get passed also and
     *          and stored during deployment
     */
    constructor() {
        // Get collateral contract and interest rate parameters
        (, address _asset, address _collateral, , uint256 baseRate, uint256 multiplier) = IAlbireoOrbiter(_msgSender())
            .borrowParameters();

        // Name of this CygUSD with token symbol (ie `CygUSD: USDC`)
        symbol = string(abi.encodePacked("CygUSD: ", IERC20(_asset).symbol()));

        // Get decimals
        decimals = IERC20(_asset).decimals();

        // Set collateral
        collateral = _collateral;

        // Update the interest rate model and do min max checks
        interestRateModelInternal(baseRate, multiplier, kinkMultiplier, kinkUtilizationRate);

        // Assurance
        totalSupply = 0;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks if new parameter is within range when updating borrowable settings
     *  @param min The minimum value allowed for the parameter that is being updated
     *  @param max The maximum value allowed for the parameter that is being updated
     *  @param value The value of the parameter that is being updated
     */
    function validRange(uint256 min, uint256 max, uint256 value) internal pure {
        /// @custom:error Avoid outside range
        if (value < min || value > max) {
            revert CygnusBorrowControl__ParameterNotInRange({min: min, max: max, value: value});
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

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Updates the parameters of the interest rate model and writes to storage
     *  @dev Does necessary checks internally. Reverts in case of failing checks
     *  @param baseRatePerYear_ The approximate target base APR, as a mantissa (scaled by 1e18)
     *  @param multiplierPerYear_ The rate of increase in interest rate wrt utilization (scaled by 1e18)
     *  @param kinkMultiplier_ The increase to farmApy once kink utilization is reached
     *  @param kinkUtilizationRate_ The point at which the jump multiplier takes effect
     */
    function interestRateModelInternal(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    ) private {
        // Internal parameter check for base rate
        validRange(0, BASE_RATE_MAX, baseRatePerYear_);

        // Internal parameter check for kink rate
        validRange(KINK_UTILIZATION_RATE_MIN, KINK_UTILIZATION_RATE_MAX, kinkUtilizationRate_);

        // Internal parameter check for kink multiplier
        validRange(1, KINK_MULTIPLIER_MAX, kinkMultiplier_);

        // Calculate the Base Rate per second and update to storage
        baseRatePerSecond = baseRatePerYear_ / SECONDS_PER_YEAR;

        // Calculate the Farm Multiplier per second and update to storage
        multiplierPerSecond = multiplierPerYear_.divWad(SECONDS_PER_YEAR * kinkUtilizationRate_);

        // Update kink multiplier
        kinkMultiplier = kinkMultiplier_;

        // update kink utilization rate
        kinkUtilizationRate = kinkUtilizationRate_;

        // Calculate the Jump Multiplier per second and update to storage
        jumpMultiplierPerSecond = multiplierPerYear_.fullMulDiv(kinkMultiplier_, SECONDS_PER_YEAR).divWad(
            kinkUtilizationRate_
        );

        /// @custom:event NewInterestParameter
        emit NewInterestRateParameters(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_, kinkUtilizationRate_);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant only-admin 👽
     */
    function setInterestRateModel(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    ) external override nonReentrant cygnusAdmin {
        // Update interest rate model with per second rates
        interestRateModelInternal(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_, kinkUtilizationRate_);
    }

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant only-admin 👽
     */
    function setCygnusBorrowRewarder(address newBorrowRewarder) external override nonReentrant cygnusAdmin {
        // Need the option of setting the borrow tracker as address(0) as child contract checks for 0 address in
        // case it's inactive
        // Old borrow tracker
        address oldBorrowRewarder = cygnusBorrowRewarder;

        // Checks admin before, assign borrow tracker
        cygnusBorrowRewarder = newBorrowRewarder;

        /// @custom:event NewCygnusBorrowRewarder
        emit NewCygnusBorrowRewarder(oldBorrowRewarder, newBorrowRewarder);
    }

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security non-reentrant only-admin 👽
     */
    function setReserveFactor(uint256 newReserveFactor) external override nonReentrant cygnusAdmin {
        // Check if parameter is within range allowed
        validRange(0, RESERVE_FACTOR_MAX, newReserveFactor);

        // Old reserve factor
        uint256 oldReserveFactor = reserveFactor;

        // Update reserve factor
        reserveFactor = newReserveFactor;

        /// @custom:event NewReserveFactor
        emit NewReserveFactor(oldReserveFactor, newReserveFactor);
    }
}
