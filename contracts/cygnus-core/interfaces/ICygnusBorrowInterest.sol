// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowControl } from "./ICygnusBorrowControl.sol";

/**
 *  @title ICygnusBorrowInterest Interface for the Interest Rate model used by cygnus
 */
interface ICygnusBorrowInterest is ICygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     *  @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     *  @param jumpMultiplierPerYear The multiplierPerSecond after hitting a specified utilization point
     *  @param kink_ is the utilization rate at which the kink happens
     *  custom:event Emitted when a new interest rate is set
     */
    event NewInterestRateParameters(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice baseRatePerSecond The interest rate for this pool when utilization is 0 divided by seconds in a year
     */
    function baseRatePerSecond() external view returns (uint256);

    /**
     *  @notice baseRatePerSecond The mulitplier for this pool divided by seconds in a year
     */
    function multiplierPerSecond() external view returns (uint256);

    /**
     *  @notice jumpMultiplierPerSecond The Jump multiplier for this pool divided by seconds in a year
     */
    function jumpMultiplierPerSecond() external view returns (uint256);

    /**
     *  @return SECONDS_PER_YEAR The seconds per year this model uses to calculate per second interest rates
     */
    function SECONDS_PER_YEAR() external view returns (uint32);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Internal function to update the parameters of the interest rate model
     *  @param newBaseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     *  @param newMultiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     *  @param newKink The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModel(
        uint256 newBaseRatePerYear,
        uint256 newMultiplierPerYear,
        uint256 newKink
    ) external;
}
