// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowTracker } from "./interfaces/ICygnusBorrowTracker.sol";
import { CygnusBorrowApprove } from "./CygnusBorrowApprove.sol";
import { CygnusBorrowInterest } from "./CygnusBorrowInterest.sol";

// Interfaces
import { ICygnusFarmingPool } from "./interfaces/ICygnusFarmingPool.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

/**
 *  @title CygnusBorrowTracker
 *  @notice Contract that accrues interest and tracks borrows for this pool
 *  @dev It is used by both Borrow and Collateral contracts.
 */
contract CygnusBorrowTracker is ICygnusBorrowTracker, CygnusBorrowInterest, CygnusBorrowApprove {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 for fixed point math (uint256 only)
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Container for borrow balance information
     *  @member principal Total balance (with accrued interest) as of the most recent action.
     *  @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint112 principal;
        uint112 interestIndex;
    }

    /**
     *  @notice Internal mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) public borrowBalances;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint128 public override totalReserves;

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint128 public override totalBorrows;

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint112 public override borrowIndex = 1e18;

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint112 public override borrowRate;

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint32 public override lastAccrualTimestamp = uint32(block.timestamp);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Triggers accruals to all borrows and reserves
     */
    modifier accrue() {
        accrueInterest();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @dev It is used by CygnusCollateral and CygnusCollateralModel contracts.
     *  @inheritdoc ICygnusBorrowTracker
     */
    function getBorrowBalance(address borrower) public view override returns (uint256) {
        // memory struct for this borrower
        BorrowSnapshot memory borrowSnapshot = borrowBalances[borrower];

        // If interestIndex = 0 then borrowBalance is 0, return 0 instead of fail division
        if (borrowSnapshot.interestIndex == 0) {
            return 0;
        }

        // Calculate new borrow balance with interest index
        // (borrower.principal * market.borrowIndex) / borrower.borrowIndex
        return PRBMath.mulDiv(uint256(borrowSnapshot.principal), borrowIndex, borrowSnapshot.interestIndex);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @param borrower The address of the borrower after updating the borrow snapshot
     *  @param accountBorrows Record of this borrower's total borrows up to this point
     *  @param borrowIndexStored Borrow index stored up to this point
     */
    function trackBorrowInternal(
        address borrower,
        uint256 accountBorrows,
        uint256 borrowIndexStored
    ) internal {
        address _cygnusBorrowTracker = cygnusBorrowTracker;

        // If not initialized return (individual shuttles)
        if (_cygnusBorrowTracker == address(0)) return;

        // Pass to farming pool
        ICygnusFarmingPool(_cygnusBorrowTracker).trackBorrow(borrower, accountBorrows, borrowIndexStored);
    }

    /**
     *  @notice Record keeping private function for all borrows, repays and liquidations
     *  @param borrower Address of the borrower
     *  @param borrowAmount The amount of the underlying to update
     *  @param repayAmount The amount to repay
     *  @return accountBorrowsPrior Record of account's total borrows before this event
     *  @return accountBorrows Record of account's total borrows (accountBorrowsPrior + borrowAmount)
     *  @return totalBorrowsStored Record of the protocol's cummulative total borrows after this event
     */
    function updateBorrowInternal(
        address borrower,
        uint256 borrowAmount,
        uint256 repayAmount
    )
        internal
        returns (
            uint256 accountBorrowsPrior,
            uint256 accountBorrows,
            uint256 totalBorrowsStored
        )
    {
        // Internal view function to get borrower's balance, if borrower's interestIndex = 0 it returns 0.
        accountBorrowsPrior = getBorrowBalance(borrower);

        if (borrowAmount == repayAmount) {
            return (accountBorrowsPrior, accountBorrowsPrior, totalBorrows);
        }

        // The current borrow index
        uint112 borrowIndexStored = borrowIndex;

        // If borrow amount is higher, then this transaction is a borrow transaction.
        // Increase the borrower's account borrows and store it in snapshot
        if (borrowAmount > repayAmount) {
            // The borrowBalance and borrowIndex of the borrower
            BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

            // Calculate the actual amount to increase
            uint256 increaseBorrowAmount = borrowAmount - repayAmount;

            // User's borrow balance + new borrow amount
            accountBorrows = accountBorrowsPrior + increaseBorrowAmount;

            // Update the snapshot record of the borrower's principal
            borrowSnapshot.principal = uint112(accountBorrows);

            // Update the snapshot record of the present borrow index
            borrowSnapshot.interestIndex = borrowIndexStored;

            // Protocol's Total borrows
            totalBorrowsStored = uint256(totalBorrows) + increaseBorrowAmount;

            totalBorrows = uint128(totalBorrowsStored);
        }
        // This transaction is a Repay transaction.
        // Decrease the borrower's account borrows and store it in the snapshot
        else {
            // Get borrowBalance and borrowIndex of borrower
            BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

            // Calculate the actual amount to decrease
            uint256 decreaseAmount = repayAmount - borrowAmount;

            // The new borrowers balance after this action.
            // If the decrease amount is >= user's prior borrows, return 0, else return the difference.
            accountBorrows = accountBorrowsPrior > decreaseAmount ? accountBorrowsPrior - decreaseAmount : 0;

            // Update the snapshot record of the borrower's principal their new balance
            borrowSnapshot.principal = uint112(accountBorrows);

            // If their new account borrows is 0, this transaction repays the full loan.
            if (accountBorrows == 0) {
                // Update user's interest index to 0
                borrowSnapshot.interestIndex = 0;
            } else {
                // Not fully repaid, update the snapshot record of the borrower's index with current index.
                borrowSnapshot.interestIndex = borrowIndexStored;
            }

            // Actual decrease amount
            uint256 actualDecreaseAmount = accountBorrowsPrior - accountBorrows;

            // Total protocol borrows
            // Gas savings
            totalBorrowsStored = totalBorrows;

            // Condition check to calculate protocols total borrows
            if (totalBorrowsStored > actualDecreaseAmount) {
                totalBorrowsStored -= actualDecreaseAmount;
            } else {
                totalBorrowsStored = 0;
            }

            // Update total protocol borrows
            totalBorrows = uint128(totalBorrowsStored);
        }
        // Track borrows
        trackBorrowInternal(borrower, accountBorrows, borrowIndexStored);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Applies interest accruals to borrows and reserves (2 memory slots)
     *  @inheritdoc ICygnusBorrowTracker
     */
    function accrueInterest() public override {
        // Get the present timestamp
        uint32 currentTimestamp = getBlockTimestamp();

        // Get the last accrual timestamp
        uint32 accrualTimestampStored = lastAccrualTimestamp;

        // If present timestamp is the same as the last accrual timestamp, return and do nothing
        if (accrualTimestampStored == currentTimestamp) {
            return;
        }

        // No possible way back now, store current timestamp as last accrual and start accrue
        lastAccrualTimestamp = currentTimestamp;

        // Time elapsed between present timestamp and last accrued period
        uint32 timeElapsed = currentTimestamp - accrualTimestampStored;

        // Load values from storage
        uint256 totalBorrowsStored = totalBorrows;
        // Protocol Reserves
        uint256 reservesStored = totalReserves;
        // Total balance of underlying held by this contract
        uint256 cashStored = totalBalance;
        // Current borrow index
        uint256 borrowIndexStored = borrowIndex;

        // Return if no borrows
        if (totalBorrowsStored == 0) {
            return;
        }

        // 1. Get BorrowRate
        uint256 borrowRateStored = getBorrowRate(cashStored, totalBorrowsStored, reservesStored);

        // 2. Multiply BorrowAPR by the time elapsed
        uint256 interestFactor = borrowRateStored * timeElapsed;

        // 3. Calculate the interest accumulated in this time elapsed
        uint256 interestAccumulated = interestFactor.mul(totalBorrowsStored);

        // 4. Add the interest accumulated to total borrows.
        totalBorrowsStored += interestAccumulated;

        // 5. Add interest to total reserves (reserveFactor * interestAccumulated / scale) + reservesStored
        reservesStored += reserveFactor.mul(interestAccumulated);

        // 6. Update the borrow index ( new_index = index + (interestfactor * index / 1e18) )
        borrowIndexStored += interestFactor.mul(borrowIndex);

        // Update new values to storage -> 2 memory slots with lastAccrualTimestamp
        // Store total borrows
        totalBorrows = uint128(totalBorrowsStored);
        // Total reserves
        totalReserves = uint128(reservesStored);
        // Borrow rate
        borrowRate = uint112(borrowRateStored);
        // New borrow index
        borrowIndex = uint112(borrowIndexStored);

        /// @custom:event AccrueInterest
        emit AccrueInterest(cashStored, interestAccumulated, borrowIndexStored, totalBorrowsStored, borrowRateStored);
    }

    /**
     *  @notice Tracks account balances of each borrower and passes to the farming pool
     *  @param borrower Address of borrower
     */
    function trackBorrow(address borrower) external {
        // Pass to farming pool
        trackBorrowInternal(borrower, getBorrowBalance(borrower), borrowIndex);
    }
}
