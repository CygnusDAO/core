// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowInterest } from "./interfaces/ICygnusBorrowInterest.sol";
import { CygnusBorrowControl } from "./CygnusBorrowControl.sol";

// Libraries
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

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

    // Used to accrue interests per second

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
        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, kink);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @dev This should only be accessible from the child contract BorrowTracker as it updates totalBalance
     *  @dev In case the Admins modify it with `updateJumpRateModel` the totalbalances do not get updated
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
        if (util <= kink) {
            return util.mul(multiplierPerSecond) + baseRatePerSecond;
        }
        // else return normal rate + kink rate
        uint256 normalRate = kink.mul(multiplierPerSecond) + baseRatePerSecond;

        uint256 excessUtil = util - kink;

        return excessUtil.mul(jumpMultiplierPerSecond) + normalRate;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Updates the parameters of the interest rate model and writes to storage.
     *  @dev Does necessary checks internally. Reverts in case of failing checks.
     *  @param baseRatePerYear_ The approximate target base APR, as a mantissa (scaled by 1e18).
     *  @param multiplierPerYear_ The rate of increase in interest rate wrt utilization (scaled by 1e18).
     *  @param kink_ The utilization point at which the jump multiplier is applied.
     */
    function updateJumpRateModelInternal(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kink_
    ) private {
        // Internal parameter check for BaseRate to not exceed maximum allowed (10%).
        validRange(0, BASE_RATE_MAX, baseRatePerYear);

        // Internal parameter check for the Kink point to not be below minimum or above maximum allowed.
        validRange(KINK_RATE_MIN, KINK_RATE_MAX, kink_);

        // Calculate using kinkMultiplier
        uint256 jumpMultiplierPerYear_ = multiplierPerYear_ * kinkMultiplier;

        // Update jump multiplier
        jumpMultiplierPerYear = jumpMultiplierPerYear_;

        // Calculate the Base Rate per second and update to storage
        baseRatePerSecond = baseRatePerYear_ / SECONDS_PER_YEAR;

        // Calculate the Farm Multiplier per second and update to storage
        multiplierPerSecond = multiplierPerYear_.div(SECONDS_PER_YEAR * kink_);

        // Calculate the Jump Multiplier per second and update to storage
        jumpMultiplierPerSecond = jumpMultiplierPerYear_ / SECONDS_PER_YEAR;

        /// @custom:event NewInterestParameter
        emit NewInterestRateParameters(baseRatePerYear_, multiplierPerYear_, jumpMultiplierPerYear_, kink_);
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
        uint256 newKinkRate
    ) external override nonReentrant cygnusAdmin {
        // Store baserate per year
        baseRatePerYear = newBaseRatePerYear;

        // Store multiplier per year
        multiplierPerYear = newMultiplierPerYear;

        // Update kink utilization
        kink = newKinkRate;

        updateJumpRateModelInternal(newBaseRatePerYear, newMultiplierPerYear, newKinkRate);
    }
}
