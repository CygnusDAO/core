// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusTerminal} from "./ICygnusTerminal.sol";

/**
 *  @title  ICygnusBorrowControl Interface for the control of borrow contracts (interest rate params, reserves, etc.)
 *  @notice Admin contract for Cygnus Borrow contract 👽
 */
interface ICygnusBorrowControl is ICygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when attempting to set a parameter outside the min/max ranges allowed in the Control contract
     *
     *  @custom:error ParameterNotInRange
     */
    error CygnusBorrowControl__ParameterNotInRange();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a new contract is set that rewards users in CYG
     *
     *  @param oldBorrowRewarder The address of the borrow rewarder up until this point used for CYG distribution
     *  @param newBorrowRewarder The address of the new borrow rewarder
     *
     *  @custom:event NewCygnusBorrowRewarder
     */
    event NewCygnusBorrowRewarder(address oldBorrowRewarder, address newBorrowRewarder);

    /**
     *  @dev Logs when a new reserve factory is set by admin
     *
     *  @param oldReserveFactor The reserve factor used in this shuttle until this point
     *  @param newReserveFactor The new reserve factor set
     *
     *  @custom:event NewReserveFactor
     */
    event NewReserveFactor(uint256 oldReserveFactor, uint256 newReserveFactor);

    /**
     *  @dev Logs when a new interest rate curve is set for this shuttle
     *
     *  @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     *  @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     *  @param kinkMultiplier_ The increase to multiplier per year once kink utilization is reached
     *  @param kinkUtilizationRate_ The rate at which the jump interest rate takes effect
     *
     *  custom:event NewInterestRateParameters
     */
    event NewInterestRateParameters(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ──────────────────────────── Important Addresses

    /**
     *  @return collateral Address of the collateral contract
     */
    function collateral() external view returns (address);

    /**
     *  @return cygnusBorrowRewarder Address of the contract that rewards borrowers in CYG (or other)
     */
    function cygnusBorrowRewarder() external view returns (address);

    // ───────────────────────────── Current pool rates

    /**
     *  @return baseRatePerSecond The interest rate for this pool when utilization is 0 divided by seconds in a year
     */
    function baseRatePerSecond() external view returns (uint256);

    /**
     *  @return baseRatePerSecond The mulitplier for this pool divided by seconds in a year
     */
    function multiplierPerSecond() external view returns (uint256);

    /**
     *  @return jumpMultiplierPerSecond The Jump multiplier for this pool divided by seconds in a year
     */
    function jumpMultiplierPerSecond() external view returns (uint256);

    /**
     *  @return kinkUtilizationRate Current utilization point at which the jump multiplier is applied
     */
    function kinkUtilizationRate() external view returns (uint256);

    /**
     *  @return kinkMultiplier The multiplier that is applied to the interest rate once util > kink
     */
    function kinkMultiplier() external view returns (uint256);

    /**
     *  @return reserveFactor Percentage of interest that is routed to this market's Reserve Pool
     */
    function reserveFactor() external view returns (uint256);

    /**
     *  @return exchangeRateStored The exchange rate used to mint reserves
     */
    function exchangeRateStored() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Admin 👽
     *  @notice Updates the borrow rewarder contract
     *
     *  @param newBorrowRewarder The address of the new CYG Borrow rewarder
     *
     *  @custom:security only-admin
     */
    function setCygnusBorrowRewarder(address newBorrowRewarder) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the reserve factor
     *
     *  @param newReserveFactor The new reserve factor for this shuttle
     *
     *  @custom:security only-admin
     */
    function setReserveFactor(uint256 newReserveFactor) external;

    /**
     *  @notice Admin 👽
     *  @notice Internal function to update the parameters of the interest rate model
     *
     *  @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     *  @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     *  @param kinkMultiplier_ The increase to farmApy once kink utilization is reached
     *  @param kinkUtilizationRate_ The new utilization rate
     *
     *  @custom:security only-admin
     */
    function setInterestRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    ) external;
}
