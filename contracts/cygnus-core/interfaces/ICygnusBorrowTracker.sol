// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

import { ICygnusBorrowInterest } from "./ICygnusBorrowInterest.sol";
import { ICygnusBorrowApprove } from "./ICygnusBorrowApprove.sol";

interface ICygnusBorrowTracker is ICygnusBorrowInterest, ICygnusBorrowApprove {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param cashStored Total balance of this market.
     *  @param interestAccumulated Interest accumulated since last update.
     *  @param borrowIndexStored orrow index
     *  @param totalBorrowsStored Total borrow balances.
     *  @param borrowRateStored The current borrow rate.
     *  @custom:event Emitted when interest is accrued.
     */
    event AccrueInterest(
        uint256 cashStored,
        uint256 interestAccumulated,
        uint256 borrowIndexStored,
        uint256 totalBorrowsStored,
        uint256 borrowRateStored
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return totalReserves The current total DAI reserves stored for this lending pool
     */
    function totalReserves() external view returns (uint128);

    /**
     *  @return totalBorrows Total borrows stored in the lending pool
     */
    function totalBorrows() external view returns (uint128);

    /**
     *  @return borrowIndex Borrow index stored of this lending pool, starts at 1e18
     */
    function borrowIndex() external view returns (uint112);

    /**
     *  @return borrowRate The current per-second borrow rate stored for this lending pool. To get the borrow APY
     *          we must annualize this (i.e. borrowRate * SECONDS_PER_YEAR)
     */
    function borrowRate() external view returns (uint112);

    /**
     *  @return lastAccrualTimestamp The unix timestamp stored of the last interest rate accrual
     */
    function lastAccrualTimestamp() external view returns (uint32);

    /**
     *  @notice This public view function is used to get the borrow balance of users based on stored data
     *  @dev It is used by CygnusCollateral and CygnusCollateralModel contracts
     *  @param borrower The address whose balance should be calculated
     *  @return balance The account's outstanding borrow balance or 0 if borrower's interest index is zero
     */
    function getBorrowBalance(address borrower) external view returns (uint256 balance);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Applies interest accruals to borrows and reserves (uses 2 memory slots with blockTimeStamp)
     */
    function accrueInterest() external;

    /**
     *  @notice Tracks borrows of each user for farming rewards and passes the borrow data to the farming pool
     *  @param borrower Address of borrower
     */
    function trackBorrow(address borrower) external;
}
