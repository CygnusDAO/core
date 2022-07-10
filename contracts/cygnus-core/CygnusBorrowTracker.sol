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
 *  @title  CygnusBorrowTracker
 *  @notice Contract that accrues interest and tracks borrows for this pool
 *  @notice It is used by both Borrow and Collateral contracts.
 */
contract CygnusBorrowTracker is ICygnusBorrowTracker, CygnusBorrowInterest, CygnusBorrowApprove {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Library for uint256 fixed point math, also imports the main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct BorrowSnapshot Container for individual user's borrow balance information
     *  @custom:member principal Total balance (with accrued interest) as of the most recent action
     *  @custom:member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint112 principal;
        uint112 interestIndex;
    }

    /**
     *  @notice Internal mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) internal borrowBalances;

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
    uint112 public override borrowIndex;

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint112 public override borrowRate;

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    uint32 public override lastAccrualTimestamp;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the borrow tracker
     */
    constructor() {
        // Set initial borrow index to 1
        borrowIndex = 1e18;

        // Set last accrual timestamp to deployment time
        lastAccrualTimestamp = uint32(block.timestamp);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Accrues interests to all borrows and reserves
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

        // Calculate new borrow balance with the interest index
        return PRBMath.mulDiv(uint256(borrowSnapshot.principal), borrowIndex, borrowSnapshot.interestIndex);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Track borrows for borrow rewards (if any)
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

        // If not initialized return
        if (_cygnusBorrowTracker == address(0)) {
            return;
        }

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

        // if borrow amount == repayAmount, accountBorrowsPrior == accountBorrows
        if (borrowAmount == repayAmount) {
            return (accountBorrowsPrior, accountBorrowsPrior, totalBorrows);
        }

        // The current borrow index
        uint112 borrowIndexStored = borrowIndex;

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

            // Update total borrows to storage
            totalBorrows = uint128(totalBorrowsStored);
        }
        // Decrease the borrower's account borrows and store it in the snapshot
        else {
            // Get borrowBalance and borrowIndex of borrower
            BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

            // Calculate the actual amount to decrease
            uint256 decreaseBorrowAmount = repayAmount - borrowAmount;

            // If the decrease amount is >= user's prior borrows then user borrows is 0, else return the difference
            // Never underflows
            unchecked {
                accountBorrows = accountBorrowsPrior > decreaseBorrowAmount
                    ? accountBorrowsPrior - decreaseBorrowAmount
                    : 0;
            }

            // Update the snapshot record of the borrower's principal their new balance
            borrowSnapshot.principal = uint112(accountBorrows);

            // If no account borrows then interest index is 0
            borrowSnapshot.interestIndex = accountBorrows == 0 ? 0 : borrowIndexStored;

            // Actual decrease amount checked
            uint256 actualDecreaseAmount = accountBorrowsPrior - accountBorrows;

            // Total protocol borrows and gas savings
            totalBorrowsStored = totalBorrows;

            // Condition check to update protocols total borrows
            // Never underflows
            unchecked {
                totalBorrowsStored = totalBorrowsStored > actualDecreaseAmount
                    ? totalBorrowsStored - actualDecreaseAmount
                    : 0;
            }

            // Update total protocol borrows
            totalBorrows = uint128(totalBorrowsStored);
        }
        // Track borrows
        trackBorrowInternal(borrower, accountBorrows, borrowIndexStored);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
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

        // Store current timestamp as last accrual and start accrue
        lastAccrualTimestamp = currentTimestamp;

        // Time elapsed between present timestamp and last accrued period
        uint32 timeElapsed = currentTimestamp - accrualTimestampStored;

        // ──────────────────── Load values from storage ────────────────────────

        // Total borrows stored
        uint256 totalBorrowsStored = totalBorrows;

        // Protocol Reserves
        uint256 reservesStored = totalReserves;

        // Total balance of underlying held by this contract
        uint256 cashStored = totalBalance;

        // Current borrow index
        uint256 borrowIndexStored = borrowIndex;

        // ──────────────────────────────────────────────────────────────────────

        // Return if no borrows
        if (totalBorrowsStored == 0) {
            return;
        }

        // 1. Get per-second BorrowRate
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

        // ──────────────────── Store values to storage ─────────────────────────

        // Store total borrows
        totalBorrows = uint128(totalBorrowsStored);

        // Total reserves
        totalReserves = uint128(reservesStored);

        // Borrow rate
        borrowRate = uint112(borrowRateStored);

        // New borrow index
        borrowIndex = uint112(borrowIndexStored);

        // ──────────────────────────────────────────────────────────────────────

        /// @custom:event AccrueInterest
        emit AccrueInterest(cashStored, interestAccumulated, borrowIndexStored, totalBorrowsStored, borrowRateStored);
    }

    /**
     *  @inheritdoc ICygnusBorrowTracker
     */
    function trackBorrow(address borrower) external override {
        // Pass to farming pool
        trackBorrowInternal(borrower, getBorrowBalance(borrower), borrowIndex);
    }
}
