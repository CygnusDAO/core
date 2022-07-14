// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowInterest } from "./interfaces/ICygnusBorrowInterest.sol";
import { CygnusBorrowControl } from "./CygnusBorrowControl.sol";

// Interfaces
import { ICygnusAlbireo } from "./interfaces/ICygnusAlbireo.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

/**
 *  @title  CygnusBorrowInterest Interest rate model contract for Cygnus
 *  @author CygnusDAO
 *  @notice Constructs the interest rate model used and updates the `per-second` rates
 */
contract CygnusBorrowInterest is ICygnusBorrowInterest, CygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 for uint256 fixed point math, also imports the main library `PRBMath`.
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowInterest
     */
    uint256 public override baseRatePerSecond;

    /**
     *  @inheritdoc ICygnusBorrowInterest
     */
    uint256 public override multiplierPerSecond;

    /**
     *  @inheritdoc ICygnusBorrowInterest
     */
    uint256 public override jumpMultiplierPerSecond;

    /**
     *  @inheritdoc ICygnusBorrowInterest
     */
    uint32 public constant override SECONDS_PER_YEAR = 31536000;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Interest Rate model
     */
    constructor() {
        // prettier-ignore
        (/* factory */, /* underlying */ , /* collateral */, uint256 baseRate, uint256 multiplier, uint256 kink) = 
          ICygnusAlbireo(_msgSender()).borrowParameters();

        /// Update the interest rate model from the parameters passed and stored through CygnusBorrowControl
        updateJumpRateModelInternal(baseRate, multiplier, kink);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @dev This should only be accessible from the child contract CygnusBorrowTracker
     *  @param cash Total unused funds in this pool
     *  @param borrows Total amount of borrowed funds in this pool
     *  @param reserves Total amount the protocol keeps as reserves in this pool
     */
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) internal view returns (uint256) {
        // Utilization rate (borrows * scale) / ((cash + borrows) - reserves)
        uint256 util = borrows.div((cash + borrows) - reserves);

        // If utilization <= kink return normal rate
        if (util <= kinkUtilizationRate) {
            return util.mul(multiplierPerSecond) + baseRatePerSecond;
        }

        // else return normal rate + kink rate
        uint256 normalRate = kinkUtilizationRate.mul(multiplierPerSecond) + baseRatePerSecond;

        // Get the excess utilization rate
        uint256 excessUtil = util - kinkUtilizationRate;

        // Return per second borrow rate
        return excessUtil.mul(jumpMultiplierPerSecond) + normalRate;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Updates the parameters of the interest rate model and writes to storage
     *  @dev Does necessary checks internally. Reverts in case of failing checks
     *  @param baseRatePerYear_ The approximate target base APR, as a mantissa (scaled by 1e18).
     *  @param multiplierPerYear_ The rate of increase in interest rate wrt utilization (scaled by 1e18).
     *  @param kinkMultiplier_ The utilization point at which the jump multiplier is applied.
     */
    function updateJumpRateModelInternal(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_
    ) private {
        // Internal parameter check for BaseRate to not exceed maximum allowed
        validRange(0, BASE_RATE_MAX, baseRatePerYear_);

        // Internal parameter check for the Kink point to not be below minimum or above maximum allowed
        validRange(1, KINK_MULTIPLIER_MAX, kinkMultiplier_);

        // Update kink multiplier
        kinkMultiplier = kinkMultiplier_;

        // Calculate the Base Rate per second and update to storage
        baseRatePerSecond = baseRatePerYear_ / SECONDS_PER_YEAR;

        // Calculate the Farm Multiplier per second and update to storage
        multiplierPerSecond = multiplierPerYear_.div(SECONDS_PER_YEAR * kinkUtilizationRate);

        // Calculate the Jump Multiplier per second and update to storage
        jumpMultiplierPerSecond = PRBMath.mulDiv(multiplierPerYear_, kinkMultiplier_, SECONDS_PER_YEAR).div(
            kinkUtilizationRate
        );

        /// @custom:event NewInterestParameter
        emit NewInterestRateParameters(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_);
    }

    /*  ───────────────────────────────────────────── External ────────────────────────────────────────────────  */

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusBorrowInterest
     *  @custom:security non-reentrant
     */
    function updateJumpRateModel(
        uint256 newBaseRatePerYear,
        uint256 newMultiplierPerYear,
        uint256 newKinkMultiplier
    ) external override nonReentrant cygnusAdmin {
        // Update Per second rates
        updateJumpRateModelInternal(newBaseRatePerYear, newMultiplierPerYear, newKinkMultiplier);
    }
}
