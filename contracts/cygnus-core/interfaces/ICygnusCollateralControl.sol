// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.4;

// Dependencies
import { ICygnusTerminal } from "./ICygnusTerminal.sol";

// Interfaces
import { IChainlinkNebulaOracle } from "./IChainlinkNebulaOracle.sol";

/**
 *  @title ICygnusCollateralControl Interface for the admin control of collateral contracts (incentives, debt ratios)
 */
interface ICygnusCollateralControl is ICygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error ParameterNotInRange Emitted when updating a collateral parameter outside of the range allowed
     */
    error CygnusCollateralControl__ParameterNotInRange(uint256 minRange, uint256 maxRange, uint256 value);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════  
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param oldDebtRatio The old debt ratio at which the collateral was liquidatable in this shuttle
     *  @param newDebtRatio The new debt ratio for this shuttle
     *  @custom:event NewDebtRatio Logs when the debt ratio is updated by admins
     */
    event NewDebtRatio(uint256 oldDebtRatio, uint256 newDebtRatio);

    /**
     *  @param oldLiquidationIncentive The old incentive for liquidators taken from the collateral
     *  @param newLiquidationIncentive The new liquidation incentive for this shuttle
     *  @custom:event NewLiquidationIncentive Logs when the liquidation incentive is updated by admins
     */
    event NewLiquidationIncentive(uint256 oldLiquidationIncentive, uint256 newLiquidationIncentive);
    /**
     *  @param oldLiquidationFee The previous fee the protocol kept as reserves from each liquidation
     *  @param newLiquidationFee The new liquidation fee for this shuttle
     *  @custom:event NewLiquidationFee Logs when the liquidation fee is updated by admins
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

    /**
     *  @return cygnusNebulaOracle The address of the Cygnus Price Oracle
     */
    function cygnusNebulaOracle() external view returns (IChainlinkNebulaOracle);

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
     *  @notice 👽
     *  @notice Updates the debt ratio for the shuttle
     *  @param  newDebtRatio The new requested point at which a loan is liquidatable
     *  @custom:security non-reentrant
     */
    function setDebtRatio(uint256 newDebtRatio) external;

    /**
     *  @notice 👽
     *  @notice Updates the liquidation incentive for the shuttle
     *  @param  newLiquidationIncentive The new requested profit liquidators keep from the collateral
     *  @custom:security non-reentrant
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external;

    /**
     *  @notice 👽
     *  @notice Updates the fee the protocol keeps for every liquidation
     *  @param newLiquidationFee The new requested fee taken from the liquidation incentive
     *  @custom:security non-reentrant
     */
    function setLiquidationFee(uint256 newLiquidationFee) external;
}
