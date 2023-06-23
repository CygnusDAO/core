//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusCollateralModel.sol
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
import {ICygnusCollateralControl} from "./ICygnusCollateralControl.sol";

/**
 *  @title ICygnusCollateralModel The interface for querying any borrower's positions and find liquidity/shortfalls
 */
interface ICygnusCollateralModel is ICygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the borrower is the zero address
     *
     *  @custom:error BorrowerCantBeAddressZero
     */
    error CygnusCollateralModel__BorrowerCantBeAddressZero();

    /**
     *  @dev Reverts when the borrower is the collateral address
     *
     *  @custom:error BorrowerCantBeCollateral
     */
    error CygnusCollateralModel__BorrowerCantBeCollateral();

    /**
     *  @dev Reverts when the price returned from the oracle is 0
     *
     *  @custom:error PriceCantBeZero
     */
    error CygnusCollateralModel__PriceCantBeZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Checks if the given user is able to redeem the specified amount of LP tokens.
     *
     *  @param borrower The address of the user to check.
     *  @param redeemAmount The amount of LP tokens to be redeemed.
     *  @return True if the user can redeem, false otherwise.
     *
     */
    function canRedeem(address borrower, uint256 redeemAmount) external view returns (bool);

    /**
     *  @notice Get the price of 1 amount of the underlying in stablecoins. Note: It returns the price in the borrowable`s
     *          decimals. ie If USDC, returns price in 6 deicmals, if DAI/BUSD in 18
     *  @notice Calls the oracle to return the price of the underlying LP Token of this shuttle
     *
     *  @return lpTokenPrice The price of 1 LP Token in USDC
     */
    function getLPTokenPrice() external view returns (uint256);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Gets an account's liquidity or shortfall
     *
     *  @param borrower The address of the borrower
     *  @return liquidity The account's liquidity in USDC
     *  @return shortfall If user has no liquidity, return the shortfall in USDC
     */
    function getAccountLiquidity(address borrower) external view returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Gets the account's total position value in USD (LPs owned multiplied by LP price). It uses the oracle to get the
     *          price of the LP and uses the current exchange rate.
     *
     *  @param borrower The address of the borrower
     *
     *  @return cygLPBalance The user's balance of collateral (CygLP)
     *  @return principal The original loaned USDC amount (without interest)
     *  @return borrowBalance The original loaned USDC amount plus interest (ie. what the user must pay back)
     *  @return price The current LP price
     *  @return positionUsd The borrower's position in USD. position = CygLP Balance * Exchange Rate * LP Price
     *  @return health The user's current loan health (once it reaches 100% the user becomes liquidatable)
     */
    function getBorrowerPosition(
        address borrower
    )
        external
        view
        returns (
            uint256 cygLPBalance,
            uint256 principal,
            uint256 borrowBalance,
            uint256 price,
            uint256 positionUsd,
            uint256 health
        );

    /**
     *  @notice Check if a borrower can borrow a specified amount of an asset from CygnusBorrow.
     *  @dev Throws a custom error message if the borrowableToken is invalid.
     *  @dev Calls the internal accountLiquidityInternal function to calculate the borrower's liquidity and shortfall.
     *
     *  @param borrower The address of the borrower to check.
     *  @param borrowAmount The amount the borrower wishes to borrow.
     *  @return A boolean indicating whether the borrower can borrow the specified amount.
     */
    function canBorrow(address borrower, uint256 borrowAmount) external view returns (bool);
}
