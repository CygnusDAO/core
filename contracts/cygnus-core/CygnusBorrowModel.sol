//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusBorrowModel.sol
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
     *  @custom:member principal The total borrowed amount without interest accrued
     *  @custom:member interestIndex Borrow index as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint128 principal;
        uint128 interestIndex;
    }

    /**
     *  @notice Internal snapshot of each borrower. To get the principal and current owed amount use `getBorrowBalance(account)`
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
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice We keep this internal as our borrowRate state variable gets stored during accruals
     *  @param cash Total current balance of assets this contract holds
     *  @param borrows Total amount of borrowed funds
     */
    function _borrowRate(uint256 cash, uint256 borrows) internal view returns (uint256) {
        // Utilization rate = borrows / (cash + borrows)
        // We don't take into account reserves since we mint CygUSD
        uint256 util = borrows.divWad(cash + borrows);

        // If utilization <= kink return normal rate
        if (util <= kinkUtilizationRate) return util.mulWad(multiplierPerSecond) + baseRatePerSecond;

        // else return normal rate + kink rate
        uint256 normalRate = kinkUtilizationRate.mulWad(multiplierPerSecond) + baseRatePerSecond;

        // Get the excess utilization rate
        uint256 excessUtil = util - kinkUtilizationRate;

        // Return per second borrow rate
        return excessUtil.mulWad(jumpMultiplierPerSecond) + normalRate;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @dev It is used by CygnusCollateral contract to check a borrower's position
     *  @inheritdoc ICygnusBorrowModel
     */
    function getBorrowBalance(address borrower) public view override returns (uint256 principal, uint256 borrowBalance) {
        // Load user struct to memory
        BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

        // If interestIndex = 0 then borrowBalance is 0
        if (borrowSnapshot.interestIndex == 0) return (0, 0);

        // The original loaned amount without interest accruals
        principal = borrowSnapshot.principal;

        // Calculate borrow balance with latest borrow index
        borrowBalance = uint256(borrowSnapshot.principal).fullMulDiv(borrowIndex, borrowSnapshot.interestIndex);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function utilizationRate() external view override returns (uint256) {
        // Gas savings
        uint256 _totalBorrows = totalBorrows;

        // Return the current pool utilization rate
        return _totalBorrows == 0 ? 0 : _totalBorrows.divWad(totalBalance + _totalBorrows);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function supplyRate() external view override returns (uint256) {
        // Current burrow rate taking into account the reserve factor
        uint256 rateToPool = uint256(borrowRate).mulWad(1e18 - reserveFactor);

        // Current balance of USDC + owed with interest
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

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Mints reserves to the DAO based on the interest accumulated.
     *  @param interestAccumulated The interest the contract has accrued from borrows since the last interest accrual
     *  @return newReserves The amount of CygUSD minted based on `interestAccumulated and the current exchangeRate
     */
    function mintReservesPrivate(uint256 interestAccumulated) private returns (uint256 newReserves) {
        // Calculate new reserves to mint based on the reserve factor and latest exchange rate
        newReserves = interestAccumulated.fullMulDiv(reserveFactor, exchangeRate());

        // Check to mint new reserves
        if (newReserves > 0) {
            // Get the DAO Reserves current address
            address daoReserves = hangar18.daoReserves();

            // Mint to Hangar18's latest `daoReserves`
            _mint(daoReserves, newReserves);
        }
    }

    /**
     *  @notice Track borrows for borrow rewards (if any)
     *  @param borrower The address of the borrower after updating the borrow snapshot
     *  @param accountBorrows Record of this borrower's total borrows up to this point
     *  @param borrowIndexStored Borrow index stored up to this point
     */
    function trackBorrowerPrivate(address borrower, uint256 accountBorrows, uint256 borrowIndexStored) private {
        // Rewarder address (if any)
        address rewarder = cygnusBorrowRewarder;

        // If not initialized return
        if (rewarder == address(0)) return;

        // Pass borrow to this chain's CYG rewarder
        ICygnusComplexRewarder(rewarder).trackBorrower(borrower, accountBorrows, borrowIndexStored);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Track lenders for lend rewards (if any)
     *  @param lender The address of the lender
     *  @param amount The amount of USD deposited
     */
    function _trackLender(address lender, uint256 amount) internal override {
        // Rewarder address (if any)
        address rewarder = cygnusBorrowRewarder;

        // If not initialized return
        if (rewarder == address(0)) return;

        // Pass borrow to this chain's CYG rewarder
        ICygnusComplexRewarder(rewarder).trackLender(lender, amount);
    }

    /**
     *  @notice Applies accrued interest to total borrows and reserves
     *  @notice Calculates the interest accumulated during the time elapsed since the last accrual and mints reserves accordingly.
     */
    function _accrueInterest() internal {
        // Get the present timestamp
        uint256 currentTimestamp = block.timestamp;

        // Get the last accrual timestamp
        uint256 accrualTimestampStored = lastAccrualTimestamp;

        // Time elapsed between present timestamp and last accrued period
        uint256 timeElapsed = currentTimestamp - accrualTimestampStored;

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
        uint256 borrowRateStored = _borrowRate(cashStored, totalBorrowsStored);

        // 2. BorrowRate by the time elapsed
        uint256 interestFactor = borrowRateStored * timeElapsed;

        // 3. Calculate the interest accumulated in time elapsed
        uint256 interestAccumulated = interestFactor.mulWad(totalBorrowsStored);

        // 4. Add the interest accumulated to total borrows
        totalBorrowsStored += interestAccumulated;

        // 5. Update the borrow index (new_index = index + (interestfactor * index / 1e18))
        borrowIndexStored += interestFactor.mulWad(borrowIndexStored);

        // ──────────────────── Store values: 1 memory slot ─────────────────────

        // Store total borrows
        totalBorrows = SafeCastLib.toUint96(totalBorrowsStored);

        // New borrow index
        borrowIndex = SafeCastLib.toUint80(borrowIndexStored);

        // Borrow rate
        borrowRate = SafeCastLib.toUint48(borrowRateStored);

        // This accruals' timestamp
        lastAccrualTimestamp = SafeCastLib.toUint32(currentTimestamp);

        // ──────────────────────────────────────────────────────────────────────

        // New minted reserves (if any)
        uint256 newReserves = mintReservesPrivate(interestAccumulated);

        /// @custom:event AccrueInterest
        emit AccrueInterest(cashStored, totalBorrowsStored, interestAccumulated, newReserves);
    }

    /**
     * @notice Updates the borrow balance of a borrower and the total borrows of the protocol.
     * @dev This is an internal function that should only be called from within the contract.
     * @param borrower The address of the borrower whose borrow balance is being updated.
     * @param borrowAmount The amount of tokens being borrowed by the borrower.
     * @param repayAmount The amount of tokens being repaid by the borrower.
     * @return accountBorrows The borrower's updated borrow balance
     */
    function _updateBorrow(address borrower, uint256 borrowAmount, uint256 repayAmount) internal returns (uint256 accountBorrows) {
        // Get the borrower's current borrow balance
        // prettier-ignore
        (/* principal */, uint256 borrowBalance) = getBorrowBalance(borrower);

        // If the borrow amount is equal to the repay amount, return the current borrow balance
        if (borrowAmount == repayAmount) return borrowBalance;

        // Get the current borrow index
        uint256 borrowIndexStored = borrowIndex;

        // Get the borrower's current borrow balance and borrow index
        BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

        // Increase the borrower's borrow balance if the borrow amount is greater than the repay amount
        if (borrowAmount > repayAmount) {
            // Amount to increase
            uint256 increaseBorrowAmount;

            // Never underflows
            unchecked {
                // Calculate the actual amount to increase the borrow balance by
                increaseBorrowAmount = borrowAmount - repayAmount;
            }

            // Calculate the borrower's updated borrow balance
            accountBorrows = borrowBalance + increaseBorrowAmount;

            // Update the snapshot record of the borrower's principal
            borrowSnapshot.principal = SafeCastLib.toUint128(accountBorrows);

            // Update the snapshot record of the present borrow index
            borrowSnapshot.interestIndex = SafeCastLib.toUint128(borrowIndexStored);

            // Total borrows of the protocol
            uint256 totalBorrowsStored = totalBorrows + increaseBorrowAmount;

            // Update total borrows to storage
            totalBorrows = SafeCastLib.toUint96(totalBorrowsStored);
        }
        // Decrease the borrower's borrow balance if the repay amount is greater than the borrow amount
        else {
            // Never underflows
            unchecked {
                // Calculate the actual amount to decrease the borrow balance by
                uint256 decreaseBorrowAmount = repayAmount - borrowAmount;

                // Calculate the borrower's updated borrow balance
                accountBorrows = borrowBalance > decreaseBorrowAmount ? borrowBalance - decreaseBorrowAmount : 0;
            }

            // Update the snapshot record of the borrower's principal
            borrowSnapshot.principal = SafeCastLib.toUint128(accountBorrows);

            // Update the snapshot record of the borrower's interest index, if no borrows then interest index is 0
            borrowSnapshot.interestIndex = accountBorrows == 0 ? 0 : SafeCastLib.toUint128(borrowIndexStored);

            // Calculate the actual decrease amount
            uint256 actualDecreaseAmount = borrowBalance - accountBorrows;

            // Total protocol borrows and gas savings
            uint256 totalBorrowsStored = totalBorrows;

            // Never underflows
            unchecked {
                // Condition check to update protocols total borrows
                totalBorrowsStored = totalBorrowsStored > actualDecreaseAmount ? totalBorrowsStored - actualDecreaseAmount : 0;
            }

            // Update total protocol borrows
            totalBorrows = SafeCastLib.toUint96(totalBorrowsStored);
        }

        // Track borrower
        trackBorrowerPrivate(borrower, accountBorrows, borrowIndexStored);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function accrueInterest() external override {
        // Accrue interest to borrows internally
        _accrueInterest();
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function trackBorrower(address borrower) external override {
        // prettier-ignore
        (/* principal */, uint256 borrowBalance) = getBorrowBalance(borrower);

        // Pass borrower info to the Rewarder (if any)
        trackBorrowerPrivate(borrower, borrowBalance, borrowIndex);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function trackLender(address lender) external override {
      // Get the amount of CygUSD the lender owns
        uint256 cygUsdBalance = balanceOf(lender);

        // Pass lender info to the rewarder (if any)
        _trackLender(lender, cygUsdBalance);
    }
}
