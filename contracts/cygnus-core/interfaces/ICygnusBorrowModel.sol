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
 *  @title ICygnusBorrowModel
 *  @notice Interface for the Borrowable's model which takes into account interest accruals and borrow snapshots
 */
interface ICygnusBorrowModel is ICygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when interest is accrued to borrows and reserves
     *
     *  @param cash Total balance of the underlying in the strategy
     *  @param borrows Latest total borrows stored
     *  @param interest Interest accumulated since last accrual
     *  @param reserves The amount of CygUSD minted to the DAO
     *
     *  @custom:event AccrueInterest
     */
    event AccrueInterest(uint256 cash, uint256 borrows, uint256 interest, uint256 reserves);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return totalBorrows Total borrows stored in the lending pool
     */
    function totalBorrows() external view returns (uint256);

    /**
     *  @return borrowIndex Borrow index stored of this lending pool, starts at 1e18
     */
    function borrowIndex() external view returns (uint256);

    /**
     *  @return lastAccrualTimestamp The unix timestamp stored of the last interest rate accrual
     */
    function lastAccrualTimestamp() external view returns (uint256);

    /**
     *  @notice This public view function is used to get the borrow balance of users and their principal.
     *
     *  @param borrower The address whose balance should be calculated
     *
     *  @return principal The USD amount borrowed without interest accrual
     *  @return borrowBalance The USD amount borrowed with interest accrual (ie. USD amount the borrower must repay)
     */
    function getBorrowBalance(address borrower) external view returns (uint256 principal, uint256 borrowBalance);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return utilizationRate The total amount of borrowed funds divided by the total cash the pool has available
     */
    function utilizationRate() external view returns (uint256);

    /**
     *  @return borrowRate The current per-second borrow rate stored for this pool.
     */
    function borrowRate() external view returns (uint256);

    /**
     *  @return supplyRate The current APR for lenders
     */
    function supplyRate() external view returns (uint256);

    /**
     *  @return getBorrowTokenPrice the price of the denomination token
     */
    function getBorrowTokenPrice() external view returns (uint256);

    /**
     *  @notice Get the lender`s full position
     *  @param lender The address of the lender
     *  @return cygUsdBalance The `lender's` balance of CygUSD
     *  @return rate The currente exchange rate
     *  @return positionInUsd The lender's position in USD
     */
    function getLenderPosition(address lender) external view returns (uint256 cygUsdBalance, uint256 rate, uint256 positionInUsd);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Manually track the user's deposited USD
     *
     *  @param lender The address of the lender
     */
    function trackLender(address lender) external;

    /**
     *  @notice Applies interest accruals to borrows and reserves
     */
    function accrueInterest() external;

    /**
     *  @notice Manually track the user's borrows
     *
     *  @param borrower The address of the borrower
     */
    function trackBorrower(address borrower) external;
}
