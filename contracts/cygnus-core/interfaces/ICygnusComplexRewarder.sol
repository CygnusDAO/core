//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusComplexRewarder.sol
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

/**
 *  @notice Interface for function to track user CYG rewards
 */
interface ICygnusComplexRewarder {
    /**
     * @dev Updates the borrowing information for a given borrower in a specific borrowable asset pool.
     *
     * @param borrower The address of the borrower whose information is being updated.
     * @param borrowBalance The new borrow balance for the borrower in the borrowable asset pool.
     * @param borrowIndex The current borrow index for the borrowable asset pool.
     *
     * Requirements:
     * - The caller must be the borrowable contract associated with the given Shuttle.
     */
    function trackBorrower(address borrower, uint256 borrowBalance, uint256 borrowIndex) external;

    /**
     *  @dev Tracks the borrow activity of a lender in a specific borrowable asset.
     *
     *  @param lender The address of the lender
     *  @param usdBalance The current deposited amount of usd of the lender.
     *
     *  Effects:
     *  - Updates the shares and reward debt of the borrower in the borrowable asset's pool.
     *  - Updates the total shares of the borrowable asset's pool.
     */
    function trackLender(address lender, uint usdBalance) external;
}
