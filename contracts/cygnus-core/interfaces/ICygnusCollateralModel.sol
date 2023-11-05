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
 *  @title ICygnusCollateralModel The contract that implements the collateralization model
 */
interface ICygnusCollateralModel is ICygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the borrower is the zero address or this collateral
     *  @custom:error InvalidBorrower
     */
    error CygnusCollateralModel__InvalidBorrower();

    /**
     *  @dev Reverts when the price returned from the oracle is 0
     *  @custom:error PriceCantBeZero
     */
    error CygnusCollateralModel__PriceCantBeZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Checks if the given user is able to redeem the specified amount of LP tokens.
     *  @param borrower The address of the user to check.
     *  @param redeemAmount The amount of LP tokens to be redeemed.
     *  @return True if the user can redeem, false otherwise.
     *
     */
    function canRedeem(address borrower, uint256 redeemAmount) external view returns (bool);

    /**
     *  @notice Get the price of 1 amount of the underlying in stablecoins. Note: It returns the price in the borrowable`s
     *          decimals. ie If USDC, returns price in 6 deicmals, if DAI/BUSD in 18
     *  @notice Calls the oracle to return the price of 1 unit of the underlying LP Token of this shuttle
     *  @return The price of 1 LP Token denominated in the Borrowable's underlying stablecoin
     */
    function getLPTokenPrice() external view returns (uint256);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Gets an account's liquidity or shortfall
     *  @param borrower The address of the borrower
     *  @return liquidity The account's liquidity denominated in the borrowable's underlying stablecoin.
     *  @return shortfall The account's shortfall denominated in the borrowable's underlying stablecoin. If positive 
     *                    then the account can be liquidated.
     */
    function getAccountLiquidity(address borrower) external view returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Check if a borrower can borrow a specified amount of stablecoins from the borrowable contract.
     *  @param borrower The address of the borrower
     *  @param borrowAmount The amount of stablecoins that borrower wants to borrow.
     *  @return A boolean indicating whether the borrower can borrow the specified amount
     */
    function canBorrow(address borrower, uint256 borrowAmount) external view returns (bool);

    /**
     *  @notice Quick view function to get a borrower's latest position
     *  @param borrower The address of the borrower
     *  @return lpBalance The borrower`s position in LP Tokens
     *  @return positionUsd The borrower's position in USD (ie. CygLP Balance * Exchange Rate * LP Token Price)
     *  @return health The user's current loan health (once it reaches 100% the user becomes liquidatable)
     */
    function getBorrowerPosition(address borrower) external view returns (uint256 lpBalance, uint256 positionUsd, uint256 health);
}
