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
     *  @notice The current total DAI reserves stored for this lending pool.
     */
    function totalReserves() external view returns (uint128);

    /**
     *  @notice Total borrows in the lending pool.
     */
    function totalBorrows() external view returns (uint128);

    /**
     *  @notice Initial borrow index of the market equivalent to 1e18.
     */
    function borrowIndex() external view returns (uint112);

    /**
     *  @notice The current borrow rate stored for the lending pool.
     */
    function borrowRate() external view returns (uint112);

    /**
     *  @notice block.timestamp of the last accrual.
     */
    function lastAccrualTimestamp() external view returns (uint32);

    /**
     *  @notice This public view function is used to get the borrow balance of users based on stored data.
     *  @dev It is used by CygnusCollateral and CygnusCollateralModel contracts.
     *  @param borrower The address whose balance should be calculated.
     *  @return balance The account's stored borrow balance or 0 if borrower's interest index is zero.
     */
    function getBorrowBalance(address borrower) external view returns (uint256 balance);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Accrues interest rate and updates borrow rate and total cash.
     */
    function accrueInterest() external;
}
