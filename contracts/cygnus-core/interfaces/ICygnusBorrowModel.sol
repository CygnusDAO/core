//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusBorrowModel.sol
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
import {ICygnusBorrowControl} from "./ICygnusBorrowControl.sol";

/**
 *  @title ICygnusBorrowModel Interface of the contract that implements the interest rate model and interest accruals
 */
interface ICygnusBorrowModel is ICygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when interest is accrued to borrows and reserves
     *  @param cash Total balance of the underlying in the strategy
     *  @param borrows Latest total borrows stored
     *  @param interest Interest accumulated since last accrual
     *  @param reserves The amount of CygUSD minted to the DAO
     *  @custom:event AccrueInterest
     */
    event AccrueInterest(uint256 cash, uint256 borrows, uint256 interest, uint256 reserves);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct BorrowSnapshot Container for individual user's borrow balance information
     *  @custom:member principal The total borrowed amount without interest accrued
     *  @custom:member interestIndex Borrow index as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint128 principal;
        uint128 interestIndex;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return Total borrows of the lending pool (uses borrow indices to simulate interest rate accruals)
     */
    function totalBorrows() external view returns (uint256);

    /**
     *  @return Borrow index stored of this lending pool (uses borrow indices)
     */
    function borrowIndex() external view returns (uint256);

    /**
     *  @return The unix timestamp stored of the last interest rate accrual
     */
    function lastAccrualTimestamp() external view returns (uint256);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return The price of the denomination token in 18 decimals, used for reporting purposes only
     */
    function getUsdPrice() external view returns (uint256);

    /**
     *  @return The total amount of borrowed funds divided by the total vault assets
     */
    function utilizationRate() external view returns (uint256);

    /**
     *  @return The current per-second borrow rate
     */
    function borrowRate() external view returns (uint256);

    /**
     *  @return The current per-second supply rate
     */
    function supplyRate() external view returns (uint256);

    /**
     *  @notice Function used to get the borrow balance of users and their principal.
     *  @param borrower The address whose balance should be calculated
     *  @return principal The stablecoin amount borrowed without interests
     *  @return borrowBalance The stablecoin amount borrowed with interests  (ie. what borrowers must pay back)
     */
    function getBorrowBalance(address borrower) external view returns (uint256 principal, uint256 borrowBalance);

    /**
     *  @notice Gets the lender`s full position
     *  @param lender The address of the lender
     *  @return usdBalance The amount of stablecoins that the lender owns
     *  @return positionInUsd The position of the lender in USD
     */
    function getLenderPosition(address lender) external view returns (uint256 usdBalance, uint256 positionInUsd);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Applies interest accruals to borrows and reserves
     */
    function accrueInterest() external;

    /**
     *  @notice Manually track the user's CygUSD shares to pass to the rewarder contract
     *  @param lender The address of the lender
     */
    function trackLender(address lender) external;

    /**
     *  @notice Manually track the user's borrows
     *  @param borrower The address of the borrower
     */
    function trackBorrower(address borrower) external;
}
