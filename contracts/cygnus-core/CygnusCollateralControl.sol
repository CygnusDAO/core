//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusCollateralControl.sol
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
import {ICygnusCollateralControl} from "./interfaces/ICygnusCollateralControl.sol";
import {CygnusTerminal} from "./CygnusTerminal.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";

// Overrides
import {ERC20} from "./ERC20.sol";

/**
 *  @title  CygnusCollateralControl Contract for controlling collateral settings like debt ratios/liq. incentives
 *  @author CygnusDAO
 *  @notice Initializes Collateral Arm. Assigns name, symbol and decimals to CygnusTerminal for the CygLP Token.
 *          This contract should be the only contract the Admin has control of (along with the strateyg contract)
 *          specifically to set liquidation fees for the protocol, liquidation incentives for the liquidators and
 *          setting and the max debt ratio.
 */
contract CygnusCollateralControl is ICygnusCollateralControl, CygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    // ─────────────────────── Min/Max this pool allows

    /**
     *  @notice Minimum debt ratio at which the collateral becomes liquidatable
     */
    uint256 private constant DEBT_RATIO_MIN = 0.80e18;

    /**
     *  @notice Maximum debt ratio at which the collateral becomes liquidatable
     */
    uint256 private constant DEBT_RATIO_MAX = 0.99e18;

    /**
     *  @notice Minimum liquidation incentive for liquidators that can be set
     */
    uint256 private constant LIQUIDATION_INCENTIVE_MIN = 1.00e18;

    /**
     *  @notice Maximum liquidation incentive for liquidators that can be set
     */
    uint256 private constant LIQUIDATION_INCENTIVE_MAX = 1.15e18;

    /**
     *  @notice Maximum fee the protocol is keeps from each liquidation
     */
    uint256 private constant LIQUIDATION_FEE_MAX = 0.10e18;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override debtRatio = 0.95e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override liquidationIncentive = 1.04e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override liquidationFee = 0.01e18;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Checks if new parameter is within range when updating collateral settings
     *  @param min The minimum value allowed for this parameter
     *  @param max The maximum value allowed for this parameter
     *  @param value The value for the parameter that is being updated
     */
    function _validRange(uint256 min, uint256 max, uint256 value) private pure {
        /// @custom:error ParameterNotInRange Avoid setting important variables outside range
        if (value < min || value > max) revert CygnusCollateralControl__ParameterNotInRange();
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Overrides the name function from the ERC20
     *  @inheritdoc ERC20
     */
    function name() public pure override(ERC20, IERC20) returns (string memory) {
        // Name of the collateral arm
        return "Cygnus: Collateral";
    }

    /**
     *  @notice Overrides the symbol function to represent the underlying LP (Most dexes use 2 tokens, ie 'CygLP: ETH/USDC')
     *  @inheritdoc ERC20
     */
    function symbol() public view override(ERC20, IERC20) returns (string memory) {
        // Symbol of the Collateral (ie `CygLP: ETH/OP`)
        return string(abi.encodePacked("CygLP: ", IERC20(underlying).symbol()));
    }

    /**
     *  @notice Overrides the decimal function to use the same decimals as underlying
     *  @inheritdoc ERC20
     */
    function decimals() public view override(ERC20, IERC20) returns (uint8) {
        // Override decimals for LP tokens
        return IERC20(underlying).decimals();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    function borrowable() external view returns (address) {
        // Read the stored internal variable from terminal
        return twinstar;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security only-admin 👽
     */
    function setDebtRatio(uint256 newDebtRatio) external override cygnusAdmin {
        // Checks if parameter is within bounds
        _validRange(DEBT_RATIO_MIN, DEBT_RATIO_MAX, newDebtRatio);

        // Debt ratio until now
        uint256 oldDebtRatio = debtRatio;

        /// @custom:event newDebtRatio
        emit NewDebtRatio(oldDebtRatio, debtRatio = newDebtRatio);
    }

    /**
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security only-admin 👽
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external override cygnusAdmin {
        // Checks if parameter is within bounds
        _validRange(LIQUIDATION_INCENTIVE_MIN, LIQUIDATION_INCENTIVE_MAX, newLiquidationIncentive);

        // Liquidation incentive until now
        uint256 oldLiquidationIncentive = liquidationIncentive;

        /// @custom:event NewLiquidationIncentive
        emit NewLiquidationIncentive(oldLiquidationIncentive, liquidationIncentive = newLiquidationIncentive);
    }

    /**
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security only-admin 👽
     */
    function setLiquidationFee(uint256 newLiquidationFee) external override cygnusAdmin {
        // Checks if parameter is within bounds
        _validRange(0, LIQUIDATION_FEE_MAX, newLiquidationFee);

        // Liquidation fee until now
        uint256 oldLiquidationFee = liquidationFee;

        /// @custom:event newLiquidationFee
        emit NewLiquidationFee(oldLiquidationFee, liquidationFee = newLiquidationFee);
    }
}
