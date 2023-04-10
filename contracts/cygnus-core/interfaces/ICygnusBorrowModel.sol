// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusBorrowControl} from "./ICygnusBorrowControl.sol";

interface ICygnusBorrowModel is ICygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param cashStored Total balance of this lending pool's asset (USDC)
     *  @param interestAccumulated Interest accumulated since last accrual
     *  @param borrowIndexStored The latest stored borrow index
     *  @param totalBorrowsStored Total borrow balances of this lending pool
     *  @param borrowRateStored The current borrow rate
     *  @custom:event AccrueInterest Logs when interest is accrued to borrows and reserves
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
     *  @return totalBorrows Total borrows stored in the lending pool
     */
    function totalBorrows() external view returns (uint256);

    /**
     *  @return borrowIndex Borrow index stored of this lending pool, starts at 1e18
     */
    function borrowIndex() external view returns (uint112);

    /**
     *  @return borrowRate The current per-second borrow rate stored for this shuttle. To get the borrow APY
     *          we must annualize this (i.e. borrowRate * SECONDS_PER_YEAR)
     */
    function borrowRate() external view returns (uint112);

    /**
     *  @return lastAccrualTimestamp The unix timestamp stored of the last interest rate accrual
     */
    function lastAccrualTimestamp() external view returns (uint32);

    /**
     *  @notice This public view function is used to get the borrow balance of users based on stored data
     *  @notice It is used by CygnusCollateral and CygnusCollateralModel contracts
     *  @param borrower The address whose balance should be calculated
     *  @return balance The account's outstanding borrow balance or 0 if borrower's interest index is zero
     */
    function getBorrowBalance(address borrower) external view returns (uint256 balance);

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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Applies interest accruals to borrows and reserves (uses 2 memory slots with blockTimeStamp)
     */
    function accrueInterest() external;

    /**
     *  @notice Tracks borrows of each user for farming rewards and passes the borrow data back to the CYG Rewarder
     *  @param borrower Address of borrower
     */
    function trackBorrow(address borrower) external;
}
