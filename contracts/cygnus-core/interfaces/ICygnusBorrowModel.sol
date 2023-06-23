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
     *  @param cashStored Total balance of this lending pool's asset (USDC)
     *  @param totalBorrowsStored Total borrow balances of this lending pool
     *  @param interestAccumulated Interest accumulated since last accrual
     *  @param reservesAdded The amount of CygUSD minted to the DAO
     *
     *  @custom:event AccrueInterest
     */
    event AccrueInterest(uint256 cashStored, uint256 totalBorrowsStored, uint256 interestAccumulated, uint256 reservesAdded);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return totalBorrows Total borrows stored in the lending pool
     */
    function totalBorrows() external view returns (uint96);

    /**
     *  @return borrowIndex Borrow index stored of this lending pool, starts at 1e18
     */
    function borrowIndex() external view returns (uint80);

    /**
     *  @return borrowRate The current per-second borrow rate stored for this pool.
     */
    function borrowRate() external view returns (uint48);

    /**
     *  @return lastAccrualTimestamp The unix timestamp stored of the last interest rate accrual
     */
    function lastAccrualTimestamp() external view returns (uint32);

    /**
     *  @notice This public view function is used to get the borrow balance of users based on stored data
     *
     *  @param borrower The address whose balance should be calculated
     *
     *  @return principal The USD amount borrowed without interest accrual
     *  @return borrowBalance The USD amount borrowed with interest accrual (ie. USD amount the borrower must repay)
     */
    function getBorrowBalance(address borrower) external view returns (uint256 principal, uint256 borrowBalance);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return utilizationRate The current utilization rate for this shuttle
     */
    function utilizationRate() external view returns (uint256);

    /**
     *  @return supplyRate The current supply rate for this shuttle
     */
    function supplyRate() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Applies interest accruals to borrows and reserves (uses 1 memory slot per accrual)
     */
    function accrueInterest() external;

    /**
     *  @notice Tracks borrows of each user for farming rewards and passes the borrow data back to the CYG Rewarder
     *
     *  @param borrower Address of borrower
     */
    function trackBorrower(address borrower) external;

    /**
     *  @notice Tracks CygUSD amounts of each user for farming rewards and passes the data back to the CYG Rewarder
     *
     *  @param lender Address of lender
     */
    function trackLender(address lender) external;
}
