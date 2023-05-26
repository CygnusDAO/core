// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowModel} from "./interfaces/ICygnusBorrowModel.sol";
import {CygnusBorrowControl} from "./CygnusBorrowControl.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {ICygnusComplexRewarder} from "./interfaces/ICygnusComplexRewarder.sol";

/**
 *  @title  CygnusBorrowModel Contract that accrues interest and stores borrow data of each user
 *  @author CygnusDAO
 *  @notice Contract that accrues interest and tracks borrows for this shuttle. It accrues interest on any borrow,
 *          liquidation or repay. The Accrue function uses 1 memory slot per accrual. This contract is also also
 *          used by CygnusCollateral contracts to get the latest borrow balance of a borrower to calculate current
 *          debt ratio, liquidity or shortfall.
 */
contract CygnusBorrowModel is ICygnusBorrowModel, CygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct BorrowSnapshot Container for individual user's borrow balance information
     *  @custom:member principal Total balance (with accrued interest) as of the most recent action
     *  @custom:member interestIndex Borrow index as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint128 principal;
        uint128 interestIndex;
    }

    /**
     *  @notice Internal mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) internal borrowBalances;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // Use one memory slot per accrual

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint96 public override totalBorrows;

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint80 public override borrowIndex;

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint48 public override borrowRate;

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint32 public override lastAccrualTimestamp;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the borrow tracker contract
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
     *  @custom:modifier accrue Accrue interest rate to totalBorrows
     */
    modifier accrue() {
        // Accrue interest
        accrueInterest();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice We keep this internal as our borrowRate state variable gets stored during accruals
     *  @param cash Total current balance of assets this contract holds
     *  @param borrows Total amount of borrowed funds
     */
    function getBorrowRate(uint256 cash, uint256 borrows) internal view returns (uint256) {
        // Don't take into account reserves as we mint CygUSD in CygnusBorrow.sol
        // Utilization rate borrows / (cash + borrows)
        uint256 util = borrows.divWad(cash + borrows);

        // If utilization <= kink return normal rate
        if (util <= kinkUtilizationRate) {
            return util.mulWad(multiplierPerSecond) + baseRatePerSecond;
        }

        // else return normal rate + kink rate
        uint256 normalRate = kinkUtilizationRate.mulWad(multiplierPerSecond) + baseRatePerSecond;

        // Get the excess utilization rate
        uint256 excessUtil = util - kinkUtilizationRate;

        // Return per second borrow rate
        return excessUtil.mulWad(jumpMultiplierPerSecond) + normalRate;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @dev It is used by CygnusCollateral contract
     *  @inheritdoc ICygnusBorrowModel
     */
    function getBorrowBalance(address borrower) public view override returns (uint256) {
        // Load user struct to memory
        BorrowSnapshot memory borrowSnapshot = borrowBalances[borrower];

        // If interestIndex = 0 then borrowBalance is 0
        if (borrowSnapshot.interestIndex == 0) return 0;

        // Calculate borrow balance with latest borrow index
        return uint256(borrowSnapshot.principal).fullMulDiv(borrowIndex, borrowSnapshot.interestIndex);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function utilizationRate() external view override returns (uint256) {
        // Gas savings
        uint256 _totalBorrows = totalBorrows;

        // Return the current pool utilization rate
        return _totalBorrows == 0 ? 0 : _totalBorrows.divWad((totalBalance + _totalBorrows));
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function supplyRate() external view override returns (uint256) {
        // Current burrow rate taking into account the reserve factor
        uint256 rateToPool = uint256(borrowRate).mulWad(1e18 - reserveFactor);

        // Balance
        uint256 balance = totalBalance + totalBorrows;

        // Avoid divide by 0
        if (balance == 0) return 0;

        // Utilization rate
        uint256 util = uint256(totalBorrows).divWad(balance);

        // Return pool supply rate
        return util.mulWad(rateToPool);
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
    function trackBorrowerInternal(address borrower, uint256 accountBorrows, uint256 borrowIndexStored) internal {
        // Rewarder address (if any)
        address rewarder = cygnusBorrowRewarder;

        // If not initialized return
        if (rewarder == address(0)) return;

        // Pass borrow to this chain's CYG rewarder
        ICygnusComplexRewarder(rewarder).trackBorrower(shuttleId, borrower, accountBorrows, borrowIndexStored);
    }

    /**
     * @notice Updates the borrow balance of a borrower and the total borrows of the protocol.
     * @dev This is an internal function that should only be called from within the contract.
     * @param borrower The address of the borrower whose borrow balance is being updated.
     * @param borrowAmount The amount of tokens being borrowed by the borrower.
     * @param repayAmount The amount of tokens being repaid by the borrower.
     * @return accountBorrows The borrower's updated borrow balance
     */
    function updateBorrowInternal(
        address borrower,
        uint256 borrowAmount,
        uint256 repayAmount
    ) internal returns (uint256 accountBorrows) {
        // Get the borrower's current borrow balance
        uint256 borrowBalance = getBorrowBalance(borrower);

        // If the borrow amount is equal to the repay amount, return the current borrow balance
        if (borrowAmount == repayAmount) return borrowBalance;

        // Get the current borrow index
        uint256 borrowIndexStored = borrowIndex;

        // Get the borrower's current borrow balance and borrow index
        BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

        // Increase the borrower's borrow balance if the borrow amount is greater than the repay amount
        if (borrowAmount > repayAmount) {
            // Calculate the actual amount to increase the borrow balance by
            uint256 increaseBorrowAmount = borrowAmount - repayAmount;

            // Calculate the borrower's updated borrow balance
            accountBorrows = borrowBalance + increaseBorrowAmount;

            // Update the snapshot record of the borrower's principal
            borrowSnapshot.principal = uint128(accountBorrows);

            // Update the snapshot record of the present borrow index
            borrowSnapshot.interestIndex = uint128(borrowIndexStored);

            // Total borrows of the protocol
            uint256 totalBorrowsStored = totalBorrows + increaseBorrowAmount;

            // Update total borrows to storage
            totalBorrows = uint96(totalBorrowsStored);
        }
        // Decrease the borrower's borrow balance if the repay amount is greater than the borrow amount
        else {
            // Calculate the actual amount to decrease the borrow balance by
            uint256 decreaseBorrowAmount = repayAmount - borrowAmount;

            // Never underflows
            unchecked {
                // Calculate the borrower's updated borrow balance
                accountBorrows = borrowBalance > decreaseBorrowAmount ? borrowBalance - decreaseBorrowAmount : 0;
            }

            // Update the snapshot record of the borrower's principal
            borrowSnapshot.principal = uint128(accountBorrows);

            // Update the snapshot record of the borrower's interest index, if no borrows then interest index is 0
            borrowSnapshot.interestIndex = accountBorrows == 0 ? 0 : uint128(borrowIndexStored);

            // Calculate the actual decrease amount
            uint256 actualDecreaseAmount = borrowBalance - accountBorrows;

            // Total protocol borrows and gas savings
            uint256 totalBorrowsStored = totalBorrows;

            // Never underflows
            // Condition check to update protocols total borrows
            unchecked {
                totalBorrowsStored = totalBorrowsStored > actualDecreaseAmount
                    ? totalBorrowsStored - actualDecreaseAmount
                    : 0;
            }

            // Update total protocol borrows
            totalBorrows = uint96(totalBorrowsStored);
        }

        // Track borrower
        trackBorrowerInternal(borrower, accountBorrows, borrowIndexStored);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function accrueInterest() public override {
        // Get the present timestamp
        uint32 currentTimestamp = uint32(block.timestamp);

        // Get the last accrual timestamp
        uint32 accrualTimestampStored = lastAccrualTimestamp;

        // Time elapsed between present timestamp and last accrued period
        uint32 timeElapsed = currentTimestamp - accrualTimestampStored;

        // ──────────────────── Load values from storage ────────────────────────

        // Total borrows stored
        uint256 totalBorrowsStored = totalBorrows;

        // Total balance of underlying held by this contract
        uint256 cashStored = totalBalance;

        // Current borrow index
        uint256 borrowIndexStored = borrowIndex;

        // Escape if no time has past since last accrue
        if (currentTimestamp == accrualTimestampStored || totalBorrowsStored == 0) return;

        // ──────────────────────────────────────────────────────────────────────

        // 1. Get per-second BorrowRate
        uint256 borrowRateStored = getBorrowRate(cashStored, totalBorrowsStored);

        // 2. BorrowRate by the time elapsed
        uint256 interestFactor = borrowRateStored * timeElapsed;

        // 3. Calculate the interest accumulated in time elapsed
        uint256 interestAccumulated = interestFactor.mulWad(totalBorrowsStored);

        // 4. Add the interest accumulated to total borrows
        totalBorrowsStored += interestAccumulated;

        // 5. Update the borrow index ( new_index = index + (interestfactor * index / 1e18) )
        borrowIndexStored += interestFactor.mulWad(borrowIndexStored);

        // ──────────────────── Store values: 1 memory slot ─────────────────────

        // Store total borrows
        totalBorrows = SafeCastLib.toUint96(totalBorrowsStored);

        // New borrow index
        borrowIndex = SafeCastLib.toUint80(borrowIndexStored);

        // Borrow rate
        borrowRate = SafeCastLib.toUint48(borrowRateStored);

        // This accruals' timestamp
        lastAccrualTimestamp = currentTimestamp;

        /// @custom:event AccrueInterest
        emit AccrueInterest(cashStored, totalBorrowsStored, interestAccumulated);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function trackBorrower(address borrower) external override {
        // Get into internal and pass to rewarder
        trackBorrowerInternal(borrower, getBorrowBalance(borrower), borrowIndex);
    }
}
