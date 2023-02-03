// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowModel } from "./interfaces/ICygnusBorrowModel.sol";
import { CygnusBorrowControl } from "./CygnusBorrowControl.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusFarmingPool } from "./interfaces/ICygnusFarmingPool.sol";

/**
 *  @title  CygnusBorrowModel Contract that accrues interest and stores borrow data of each user
 *  @author CygnusDAO
 *  @notice Contract that accrues interest and tracks borrows for this shuttle. It accrues interest on any borrow,
 *          liquidation or repay. The Accrue function uses 2 memory slots on each call to store reserves and
 *          borrows. It is also used by CygnusCollateral contracts to get the borrow balance of each user to
 *          calculate current debt ratios, liquidity or shortfall.
 */
contract CygnusBorrowModel is ICygnusBorrowModel, CygnusBorrowControl {
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
     *  @custom:member interestIndex Borrow index as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint112 principal;
        uint112 interestIndex;
    }

    /**
     *  @notice Internal mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) internal borrowBalances;

    /**
     *  @notice Internal variable to keep track of reserve mints used by CygnusBorrow contract to add to
     *          `totalReserves`. Keep track internally to avoid using `balanceOf` and break accounting
     */
    uint256 internal mintedReserves;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // 2 memory slots on every accrual

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint128 public override totalReserves;

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint128 public override totalBorrows;

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint112 public override borrowIndex;

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    uint112 public override borrowRate;

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
        lastAccrualTimestamp = getBlockTimestamp();
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

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice We keep this internal as our borrowRate state variable gets stored during accruals
     *  @param cash Total current balance of assets this contract holds
     *  @param borrows Total amount of borrowed funds
     *  @param reserves Total amount the protocol keeps as reserves
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) internal view returns (uint256) {
        // Utilization rate (borrows * scale) / ((cash + borrows) - reserves)
        uint256 util = borrows.div((cash + borrows) - reserves);

        // If utilization <= kink return normal rate
        if (util <= kinkUtilizationRate) {
            return util.mul(multiplierPerSecond) + baseRatePerSecond;
        }

        // else return normal rate + kink rate
        uint256 normalRate = kinkUtilizationRate.mul(multiplierPerSecond) + baseRatePerSecond;

        // Get the excess utilization rate
        uint256 excessUtil = util - kinkUtilizationRate;

        // Return per second borrow rate
        return excessUtil.mul(jumpMultiplierPerSecond) + normalRate;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @dev It is used by CygnusCollateral contract
     *  @inheritdoc ICygnusBorrowModel
     */
    function getBorrowBalance(address borrower) public view override returns (uint256) {
        // memory struct for this borrower
        BorrowSnapshot memory borrowSnapshot = borrowBalances[borrower];

        // If interestIndex = 0 then borrowBalance is 0, return 0 instead of fail division
        if (borrowSnapshot.interestIndex == 0) {
            return 0;
        }

        // Calculate new borrow balance with the interest index
        return
            PRBMath.mulDiv(
                uint256(borrowSnapshot.principal),
                uint256(borrowIndex),
                uint256(borrowSnapshot.interestIndex)
            );
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function utilizationRate() external view override returns (uint256) {
        // Return the current pool utilization rate
        return
            totalBorrows == 0 ? 0 : uint256(totalBorrows).div((totalBalance + uint256(totalBorrows)) - totalReserves);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function supplyRate() external view override returns (uint256) {
        // Current burrow rate taking into account the reserve factor
        uint256 rateToPool = uint256(borrowRate).mul(1e18 - reserveFactor);

        // Return pool supply rate
        return
            rateToPool == 0
                ? 0
                : uint256(totalBorrows).div((totalBalance + totalBorrows) - totalReserves).mul(rateToPool);
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
    function trackBorrowInternal(address borrower, uint256 accountBorrows, uint256 borrowIndexStored) internal {
        // Rewarder address (if any)
        address _cygnusBorrowRewarder = cygnusBorrowRewarder;

        // If not initialized return
        if (_cygnusBorrowRewarder == address(0)) {
            return;
        }

        // Pass to farming pool
        ICygnusFarmingPool(_cygnusBorrowRewarder).trackBorrow(shuttleId, borrower, accountBorrows, borrowIndexStored);
    }

    /**
     *  @notice Record keeping function for all borrows, repays and liquidations
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
    ) internal returns (uint256 accountBorrowsPrior, uint256 accountBorrows, uint256 totalBorrowsStored) {
        // Internal view function to get borrower's balance, if borrower's interestIndex = 0 it returns 0
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

            // Never underflows
            // If the decrease amount is >= user's prior borrows then user borrows is 0, else return the difference
            unchecked {
                accountBorrows = accountBorrowsPrior > decreaseBorrowAmount
                    ? accountBorrowsPrior - decreaseBorrowAmount
                    : 0;
            }

            // Update the snapshot record of the borrower's principal
            borrowSnapshot.principal = uint112(accountBorrows);

            // Update the snapshot record of the borrower's interest index, if no borrows then interest index is 0
            borrowSnapshot.interestIndex = accountBorrows == 0 ? 0 : borrowIndexStored;

            // Actual decrease amount checked
            uint256 actualDecreaseAmount = accountBorrowsPrior - accountBorrows;

            // Total protocol borrows and gas savings
            totalBorrowsStored = totalBorrows;

            // Never underflows
            // Condition check to update protocols total borrows
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
     *  @inheritdoc ICygnusBorrowModel
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

        // 4. Add the interest accumulated to total borrows
        totalBorrowsStored += interestAccumulated;

        // 5. Add interest to total reserves (reserveFactor * interestAccumulated / scale) + reservesStored
        reservesStored += reserveFactor.mul(interestAccumulated);

        // 6. Update the borrow index ( new_index = index + (interestfactor * index / 1e18) )
        borrowIndexStored += interestFactor.mul(borrowIndexStored);

        // ────── Store values: 2 memory slots with uint32 lastAccrualTime ──────

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

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function trackBorrow(address borrower) external override {
        // Pass to farming pool
        trackBorrowInternal(borrower, getBorrowBalance(borrower), borrowIndex);
    }
}
