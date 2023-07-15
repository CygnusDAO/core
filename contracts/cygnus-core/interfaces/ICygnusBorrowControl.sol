//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusBorrowControl.sol
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

    /**
     *  @dev Reverts when setting the collateral if the msg.sender is not the hangar18 contract
     *
     *  @custom:error MsgSenderNotHangar
     */
    error CygnusBorrowControl__MsgSenderNotHangar();

    /**
     *  @dev Reverts wehn attempting to set a collateral that has already been set
     *
     *  @custom:error CollateralAlreadySet
     */
    error CygnusBorrowControl__CollateralAlreadySet();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    event NewCollateralAdded(address sender, address collateral, uint256 collateralsLength);

    /**
     *  @dev Logs when a new contract is set that rewards users in CYG
     *
     *  @param oldRewarder The address of the rewarder up until this point used for CYG distribution
     *  @param newRewarder The address of the new rewarder
     *
     *  @custom:event NewCygnusBorrowRewarder
     */
    event NewPillarsOfCreation(address oldRewarder, address newRewarder);

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
     */ // prettier-ignore
    event NewInterestRateParameters( uint256 baseRatePerYear, uint256 multiplierPerYear, uint256 kinkMultiplier_, uint256 kinkUtilizationRate_);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct InterestRateModel The structwith the interest rate params for this pool
     *  @custom:member baseRatePerSecond The base interest rate which is the y-intercept when utilization rate is 0
     *  @custom:member multiplierPerSecond The multiplier of utilization rate that gives the slope of the interest rate
     *  @custom:member jumpMultiplierPerSecond The multiplierPerSecond after hitting a specified utilization point
     *  @custom:member kink The utilization point at which the jump multiplier is applied
     */
    struct InterestRateModel {
        uint64 baseRatePerSecond;
        uint64 multiplierPerSecond;
        uint64 jumpMultiplierPerSecond;
        uint64 kink;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Returns whether or not an address is a collateral for this borrowable
     */
    function isCollateral(address collateral) external view returns (bool);

    /**
     *  @notice Returns a collateral at a given index
     */
    function allCollaterals(uint256 id) external view returns (address);

    /**
     *  @notice Returns this station's id
     */
    function stationId() external view returns (uint256);

    /**
     *  @notice Total collaterals length
     */
    function totalCollaterals() external view returns (uint256);

    /**
     *  @return collaterals Returns the whole array of all supported collaterals
     */
    function collaterals() external view returns (address[] memory);

    /**
     *  @return pillarsOfCreation Address of the contract that rewards both borrowers and lenders in CYG
     */
    function pillarsOfCreation() external view returns (address);

    // ────────────── Current Pool Rates ──────────────

    /**
     *  @notice The current interest rate params set for this pool
     *  @return baseRatePerSecond The base interest rate which is the y-intercept when utilization rate is 0
     *  @return multiplierPerSecond The multiplier of utilization rate that gives the slope of the interest rate
     *  @return jumpMultiplierPerSecond The multiplierPerSecond after hitting a specified utilization point
     *  @return kink The utilization point at which the jump multiplier is applied
     */
    // prettier-ignore
    function interestRateModel() external view returns (uint64 baseRatePerSecond, uint64 multiplierPerSecond, uint64 jumpMultiplierPerSecond, uint64 kink);

    /**
     *  @return reserveFactor Percentage of interest that is routed to this market's Reserve Pool
     */
    function reserveFactor() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

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

    /**
     *  @notice Admin 👽
     *  @notice Updates the pillars of creation contract. This can be updated to the zero address in case we need
     *          to remove rewards from pools saving us gas instead of calling the contract.
     *
     *  @param newPillars The address of the new CYG rewarder
     *
     *  @custom:security only-admin
     */
    function setPillarsOfCreation(address newPillars) external;

    function setCollateral(address collateral) external;
}
