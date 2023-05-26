// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusTerminal} from "./ICygnusTerminal.sol";

/**
 *  @title  ICygnusCollateralControl Interface for the admin control of collateral contracts (incentives, debt ratios)
 *  @notice Admin contract for Cygnus Collateral contract 👽
 */
interface ICygnusCollateralControl is ICygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when attempting to set a parameter outside the min/max ranges allowed in the Control contract
     *
     *  @custom:error ParameterNotInRange
     */
    error CygnusCollateralControl__ParameterNotInRange();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════  
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when the max debt ratio is updated for this shuttle
     *
     *  @param oldDebtRatio The old debt ratio at which the collateral was liquidatable in this shuttle
     *  @param newDebtRatio The new debt ratio for this shuttle
     *
     *  @custom:event NewDebtRatio
     */
    event NewDebtRatio(uint256 oldDebtRatio, uint256 newDebtRatio);

    /**
     *  @dev Logs when a new liquidation incentive is set for liquidators
     *
     *  @param oldLiquidationIncentive The old incentive for liquidators taken from the collateral
     *  @param newLiquidationIncentive The new liquidation incentive for this shuttle
     *
     *  @custom:event NewLiquidationIncentive
     */
    event NewLiquidationIncentive(uint256 oldLiquidationIncentive, uint256 newLiquidationIncentive);

    /**
     *  @dev Logs when a new liquidation fee is set, which the protocol keeps from each liquidation
     *
     *  @param oldLiquidationFee The previous fee the protocol kept as reserves from each liquidation
     *  @param newLiquidationFee The new liquidation fee for this shuttle
     *
     *  @custom:event NewLiquidationFee
     */
    event NewLiquidationFee(uint256 oldLiquidationFee, uint256 newLiquidationFee);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ────────────── Important Addresses ─────────────

    /**
     *  @return borrowable The address of the Cygnus borrow contract for this collateral which holds USDC
     */
    function borrowable() external view returns (address);

    // ────────────── Current Pool Rates ──────────────

    /**
     *  @return debtRatio The current debt ratio for this shuttle, default at 95%
     */
    function debtRatio() external view returns (uint256);

    /**
     *  @return liquidationIncentive The current liquidation incentive for this shuttle
     */
    function liquidationIncentive() external view returns (uint256);

    /**
     *  @return liquidationFee The current liquidation fee the protocol keeps from each liquidation
     */
    function liquidationFee() external view returns (uint256);

    // ──────────── Min/Max rates allowed ─────────────

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Admin 👽
     *  @notice Updates the debt ratio for the shuttle
     *
     *  @param  newDebtRatio The new requested point at which a loan is liquidatable
     *
     *  @custom:security only-admin
     */
    function setDebtRatio(uint256 newDebtRatio) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the liquidation incentive for the shuttle
     *
     *  @param  newLiquidationIncentive The new requested profit liquidators keep from the collateral
     *
     *  @custom:security only-admin
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the fee the protocol keeps for every liquidation
     *
     *  @param newLiquidationFee The new requested fee taken from the liquidation incentive
     *
     *  @custom:security only-admin
     */
    function setLiquidationFee(uint256 newLiquidationFee) external;
}
