// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowControl} from "./ICygnusBorrowControl.sol";

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
     *
     *  @custom:event AccrueInterest 
     */
    event AccrueInterest(
        uint256 cashStored,
        uint256 totalBorrowsStored,
        uint256 interestAccumulated
    );

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
     *  @notice It is used by CygnusCollateral and CygnusCollateralModel contracts
     *
     *  @param borrower The address whose balance should be calculated
     *
     *  @return balance The account's outstanding borrow balance or 0 if borrower's interest index is zero
     */
    function getBorrowBalance(address borrower) external view returns (uint256 balance);

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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Applies interest accruals to borrows and reserves (uses 1 memory slot per accrual)
     */
    function accrueInterest() external;

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Tracks borrows of each user for farming rewards and passes the borrow data back to the CYG Rewarder
     *
     *  @param borrower Address of borrower
     */
    function trackBorrower(address borrower) external;
}
