//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusCollateralControl.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
     *  @custom:error ParameterNotInRange
     */
    error CygnusCollateralControl__ParameterNotInRange();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════  
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when the max debt ratio is updated for this shuttle
     *  @param oldDebtRatio The old debt ratio at which the collateral was liquidatable in this shuttle
     *  @param newDebtRatio The new debt ratio for this shuttle
     *  @custom:event NewDebtRatio
     */
    event NewDebtRatio(uint256 oldDebtRatio, uint256 newDebtRatio);

    /**
     *  @dev Logs when a new liquidation incentive is set for liquidators
     *  @param oldLiquidationIncentive The old incentive for liquidators taken from the collateral
     *  @param newLiquidationIncentive The new liquidation incentive for this shuttle
     *  @custom:event NewLiquidationIncentive
     */
    event NewLiquidationIncentive(uint256 oldLiquidationIncentive, uint256 newLiquidationIncentive);

    /**
     *  @dev Logs when a new liquidation fee is set, which the protocol keeps from each liquidation
     *  @param oldLiquidationFee The previous fee the protocol kept as reserves from each liquidation
     *  @param newLiquidationFee The new liquidation fee for this shuttle
     *  @custom:event NewLiquidationFee
     */
    event NewLiquidationFee(uint256 oldLiquidationFee, uint256 newLiquidationFee);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return The address of the Cygnus Borrow contract for this collateral
     */
    function borrowable() external view returns (address);

    /**
     *  @return The current max debt ratio for this shuttle, after which positions become liquidatable
     */
    function debtRatio() external view returns (uint256);

    /**
     *  @return The current liquidation incentive for this shuttle
     */
    function liquidationIncentive() external view returns (uint256);

    /**
     *  @return The current liquidation fee the protocol keeps from each liquidation
     */
    function liquidationFee() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Admin 👽
     *  @notice Updates the shuttle's debt ratio
     *  @param  newDebtRatio The new max debt ratio at which positions become liquidatable.
     *  @custom:security only-admin
     */
    function setDebtRatio(uint256 newDebtRatio) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the liquidation bonus for liquidators
     *  @param  newLiquidationIncentive The new incentive that the liquidators receive for liquidating positions.
     *  @custom:security only-admin
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the liquidation fee that the protocol keeps for every liquidation
     *  @param newLiquidationFee The new fee that the protocol keeps from every liquidation.
     *  @custom:security only-admin
     */
    function setLiquidationFee(uint256 newLiquidationFee) external;
}
