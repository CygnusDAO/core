//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusBorrowControl.sol
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
import {ICygnusBorrowControl} from "./interfaces/ICygnusBorrowControl.sol";
import {CygnusTerminal} from "./CygnusTerminal.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";

// Overrides
import {ERC20} from "./ERC20.sol";

/**
 *  @title  CygnusBorrowControl Contract for controlling borrow settings
 *  @author CygnusDAO
 *  @notice Initializes Borrow Arm. Assigns name, symbol and decimals to CygnusTerminal for the CygUSD Token.
 *          This contract should be the only contract the Cygnus admin has control of, specifically to set the
 *          borrow tracker which tracks individual borrows to reward users with CYG. Admin also sets the interest
 *          rate model used for this pool in this contract along with the reserve rate.
 *
 *          The constructor stores the collateral address this pool is linked with, and only this address can
 *          be used as collateral to borrow this contract`s underlying.
 */
contract CygnusBorrowControl is ICygnusBorrowControl, CygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

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
     *  @notice Minimum kink utilization point allowed (70%)
     */
    uint256 private constant KINK_UTILIZATION_RATE_MIN = 0.70e18;

    /**
     *  @notice Maximum Kink point allowed (99%)
     */
    uint256 private constant KINK_UTILIZATION_RATE_MAX = 0.99e18;

    /**
     *  @notice Maximum Kink multiplier
     */
    uint256 private constant KINK_MULTIPLIER_MAX = 10;

    /**
     *  @notice Used to calculate the per second interest rates
     */
    uint256 private constant SECONDS_PER_YEAR = 31536000;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public override pillarsOfCreation;

    // ───────────────────────────── Current pool rates

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override reserveFactor; // Default is no reserves

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    InterestRateModel public override interestRateModel;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Checks if new parameter is within range when updating borrowable settings
     *  @param min The minimum value allowed for the parameter that is being updated
     *  @param max The maximum value allowed for the parameter that is being updated
     *  @param value The value of the parameter that is being updated
     */
    function _validRange(uint256 min, uint256 max, uint256 value) private pure {
        /// @custom:error ParameterNotInRange Avoid setting important variables outside range
        if (value < min || value > max) revert CygnusBorrowControl__ParameterNotInRange();
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Overrides the name function from the ERC20
     *  @inheritdoc ERC20
     */
    function name() public pure override(ERC20, IERC20) returns (string memory) {
        // Name of the borrowable arm
        return "Cygnus: Borrowable";
    }

    /**
     *  @notice Overrides the symbol function to represent the underlying stablecoin (ie 'CygUSD: USDC')
     *  @inheritdoc ERC20
     */
    function symbol() public view override(ERC20, IERC20) returns (string memory) {
        // Symbol of the Borrowable (ie `CygUSD: USDC`)
        return string(abi.encodePacked("CygUSD: ", IERC20(underlying).symbol()));
    }

    /**
     *  @notice Overrides the decimal function to use the same decimals as underlying
     *  @inheritdoc ERC20
     */
    function decimals() public view override(ERC20, IERC20) returns (uint8) {
        // Override decimals for stablecoin
        return IERC20(underlying).decimals();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    function collateral() external view override returns (address) {
        // Read the stored internal variable from terminal
        return twinstar;
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
    function _interestRateModel(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    ) private {
        // Internal parameter check for base rate
        _validRange(0, BASE_RATE_MAX, baseRatePerYear_);

        // Internal parameter check for kink rate
        _validRange(KINK_UTILIZATION_RATE_MIN, KINK_UTILIZATION_RATE_MAX, kinkUtilizationRate_);

        // Internal parameter check for kink multiplier
        _validRange(2, KINK_MULTIPLIER_MAX, kinkMultiplier_);

        // Slope of the interest rate curve in seconds
        uint256 slope = multiplierPerYear_.divWad(SECONDS_PER_YEAR * kinkUtilizationRate_);

        // Update the interest rate model
        interestRateModel = InterestRateModel({
            // Calculate the Base Rate per second and update to storage
            baseRatePerSecond: SafeCastLib.toUint64(baseRatePerYear_ / SECONDS_PER_YEAR),
            // Calculate the Multiplier per second and update to storage
            multiplierPerSecond: SafeCastLib.toUint64(slope),
            // Calculate the Jump Multiplier per second and update to storage
            jumpMultiplierPerSecond: SafeCastLib.toUint64(slope * kinkMultiplier_),
            // Update kink utilization rate
            kink: SafeCastLib.toUint64(kinkUtilizationRate_)
        });

        /// @custom:event NewInterestParameter
        emit NewInterestRateParameters(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_, kinkUtilizationRate_);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security only-admin 👽
     */
    function setReserveFactor(uint256 newReserveFactor) external override cygnusAdmin {
        // Check if parameter is within range allowed
        _validRange(0, RESERVE_FACTOR_MAX, newReserveFactor);

        // Old reserve factor
        uint256 oldReserveFactor = reserveFactor;

        // Update reserve factor
        reserveFactor = newReserveFactor;

        /// @custom:event NewReserveFactor
        emit NewReserveFactor(oldReserveFactor, newReserveFactor);
    }

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security only-admin 👽
     */
    function setInterestRateModel(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_,
        uint256 kink_
    ) external override cygnusAdmin {
        // Update interest rate model with per second rates
        _interestRateModel(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_, kink_);
    }

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security only-admin 👽
     */
    function setPillarsOfCreation(address newCygRewarder) external override cygnusAdmin {
        // Need the option of setting to address(0) as child contract checks for 0 address in case it's inactive
        // Old CYG rewarder
        address oldCygRewarder = pillarsOfCreation;

        // Assign new rewarder
        pillarsOfCreation = newCygRewarder;

        /// @custom:event NewPillarsOfCreation
        emit NewPillarsOfCreation(oldCygRewarder, newCygRewarder);
    }
}
