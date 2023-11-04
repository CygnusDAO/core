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
//  along with this prograinterestRateModel.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowModel} from "./interfaces/ICygnusBorrowModel.sol";
import {CygnusBorrowControl} from "./CygnusBorrowControl.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {IPillarsOfCreation} from "./interfaces/IPillarsOfCreation.sol";

// Overrides
import {CygnusTerminal, ICygnusTerminal} from "./CygnusTerminal.sol";

/**
 *  @title  CygnusBorrowModel Contract that accrues interest and stores borrow data of each user
 *  @author CygnusDAO
 *  @notice Contract that accrues interest and tracks borrows for this shuttle. It accrues interest on any borrow,
 *          liquidation or repay. The Accrue function uses 1 memory slot per accrual. This contract is also used
 *          by CygnusCollateral contracts to get the latest borrow balance of a borrower to calculate current debt
 *          ratio, liquidity or shortfall.
 *
 *          The interest accrual mechanism is similar to Compound Finance's with the exception of reserves.
 *          If the reserveRate is set (> 0) then the contract mints the vault token (CygUSD) to the daoReserves
 *          contract set at the factory.
 *
 *          There's also 2 functions `trackLender` & `trackBorrower` which are used to give out rewards to lenders
 *          and borrowers respectively. The way rewards are calculated is by querying the latest balance of
 *          CygUSD for lenders and the latest borrow balance for borrowers. See the `_afterTokenTransfer` function
 *          in CygnusBorrow.sol. After any token transfer of CygUSD we pass the balance of CygUSD of the `from`
 *          and `to` address. After any borrow, repay or liquidate we track the latest borrow balance of the
 *          borrower.
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

    // 1 memory slot per accrual

    /**
     *  @notice The stored total borrows as per last state changing action
     */
    uint144 internal _totalBorrows;

    /**
     *  @notice The stored borrow index as per last state changing action
     */
    uint80 internal _borrowIndex;

    /**
     *  @notice The stored timestamp of the last interest accrual
     */
    uint32 internal _accrualTimestamp;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the borrowable model contract
     */
    constructor() {
        // Set initial borrow index to 1
        _borrowIndex = 1e18;

        // Set last accrual timestamp to deployment time
        _accrualTimestamp = uint32(block.timestamp);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Overrides the previous modifier from CygnusTerminal to accrue interest before any interaction
     *  @notice CygnusTerminal override
     *  @custom:modifier update Accrues interest to total borrows
     */
    modifier update() override(CygnusTerminal) {
        // Accrue interest before any state changing action (ie. Deposit/Redeem/Borrow/Repay/Liquidate)
        _accrueInterest();
        // Update before to prevent deposit spam for yield bearing tokens
        _update();
        _;
        // Update after deposit
        _update();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ───────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

    /**
     *  @notice Internal function used to calculate the total assets of the borrowable (cash + borrows).
     *  @notice The deposit and redeem functions always use this function to calculate the shares and assets 
     *          respectively passing `false` as these accrue interest and update via the `update` modifier.
     *          This is done to stop the _convertToShares and _convertToAssets functions from extra SLOADS.
     *          If called externally via `totalAssets()` then we always simulate accrual.
     *  @param accrue Whether we should simulate accrual or not.
     *  @return The total underlying assets we own (total balance + borrows)
     */
    function _totalAssets(bool accrue) internal view override returns (uint256) {
        // Current cash in strategy
        uint256 balance = _totalBalance;

        // Current borrows stored
        uint256 borrows = _totalBorrows;

        // If we should accrue then get the latest balance (`_previewTotalBalance`) and borrows with interest accrued 
        // from the borrow indices. 
        // `_convertToAssets` and `_convertToShares` always pass false as already accrued.
        if (accrue) (balance, borrows, , , ) = _borrowIndices();

        // Return total cash + total borrows
        return balance + borrows;
    }

    /**
     *  @notice Get the latest borrow indices
     *  @return cash The total amount of underlying currently deposited in the strategy
     *  @return borrows The latest borrows with interest accruals
     *  @return index The latest borrow index with interst accruals
     *  @return timeElapsed The time elapsed since the last accrual timestamp
     *  @return interest The interest accrued since last accrual
     */
    function _borrowIndices() internal view returns (uint256 cash, uint256 borrows, uint256 index, uint256 timeElapsed, uint256 interest) {
        // Total balance of the underlying deposited in the strategy
        cash = _previewTotalBalance();

        // ──────────────────── Load values from storage ────────────────────────
        // Total borrows stored
        borrows = _totalBorrows;

        // Borrow index stored
        index = _borrowIndex;

        // Time elapsed between present timestamp and last accrued period
        timeElapsed = block.timestamp - _accrualTimestamp;

        // Return cash, stored borrows and stored index if no time elapsed since last accrual and thus no interest
        if (timeElapsed == 0) return (cash, borrows, index, timeElapsed, 0);

        // ──────────────────────────────────────────────────────────────────────
        // 1. Get latest per-second BorrowRate with current cash and stored borrows
        uint256 latestBorrowRate = _latestBorrowRate(cash, borrows);

        // 2. The borrow rate by the time elapsed
        uint256 interestFactor = latestBorrowRate * timeElapsed;

        // 3. Calculate the interest accumulated in time elapsed with the stored borrows
        interest = interestFactor.mulWad(borrows);

        // 4. Add the interest accumulated to the stored borrows
        borrows += interest;

        // 5. Latest borrow index (new_index = index + (interestfactor * index / 1e18))
        index += interestFactor.mulWad(index);
    }

    /**
     *  @notice Get the latest borrow balance for `borrower`. If accrue is false it means that we have already accrued interest
     *          (through the `update` modifier) with win the transaction and there is no need to load the borrow indices.
     *  @param borrower The address of the borrower
     *  @param accrue Whether we should simulate accrue or not
     *  @return principal The original borrowed amount without interest
     *  @return borrowBalance The borrowed amount with interest
     */
    function _latestBorrowBalance(address borrower, bool accrue) internal view returns (uint256 principal, uint256 borrowBalance) {
        // Load user struct to storage (gas savings when called from Collateral.sol)
        BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];

        // If interestIndex = 0 then user has no borrows
        if (borrowSnapshot.interestIndex == 0) return (0, 0);

        // The original loaned amount without interest accruals
        principal = borrowSnapshot.principal;

        // Get the current index. If called in `_updateBorrow` (after any liquidation or borrow) then we use the
        // stored borrow index as we have accrued before and this is the latest borrow index.
        uint256 index = _borrowIndex;

        /// If accrue then get the latest borrow index with interest accrued
        if (accrue) (, , index, , ) = _borrowIndices();

        // Calculate borrow balance with latest borrow index
        borrowBalance = principal.fullMulDiv(index, borrowSnapshot.interestIndex);
    }

    /**
     *  @param cash Total current balance of assets this contract holds
     *  @param borrows Total amount of borrowed funds
     */
    function _latestBorrowRate(uint256 cash, uint256 borrows) internal view returns (uint256) {
        // Utilization rate = borrows / (cash + borrows). We don't take into account reserves since we mint CygUSD
        uint256 util = borrows == 0 ? 0 : borrows.divWad(cash + borrows);

        // If utilization <= kink return normal rate
        if (util <= interestRateModel.kink) {
            // Normal rate = slope + base
            return util.mulWad(interestRateModel.multiplierPerSecond) + interestRateModel.baseRatePerSecond;
        }

        // else return normal rate + kink rate
        uint256 normalRate = uint256(interestRateModel.kink).mulWad(interestRateModel.multiplierPerSecond) +
            interestRateModel.baseRatePerSecond;

        // Get the excess utilization rate
        uint256 excessUtil = util - interestRateModel.kink;

        // Return per second borrow rate
        return excessUtil.mulWad(interestRateModel.jumpMultiplierPerSecond) + normalRate;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    // Stored variables

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function totalBorrows() external view returns (uint256 borrows) {
        // Latest borrows
        (, borrows, , , ) = _borrowIndices();
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function borrowIndex() external view returns (uint256 index) {
        // Latest borrow index
        (, , index, , ) = _borrowIndices();
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function lastAccrualTimestamp() external view returns (uint256) {
        // Latest interest accrual timestamp
        return _accrualTimestamp;
    }

    // Latest user positions

    /**
     *  @dev It is used by CygnusCollateral contract to check a borrower's position
     *  @inheritdoc ICygnusBorrowModel
     */
    function getBorrowBalance(address borrower) external view override returns (uint256 principal, uint256 borrowBalance) {
        // Return using latest borrow indices always if called externally
        return _latestBorrowBalance(borrower, true);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function getLenderPosition(address lender) external view returns (uint256 cygUsdBalance, uint256 rate, uint256 positionUsd) {
        // CygUSD balance
        cygUsdBalance = balanceOf(lender);

        // Exchange Rate between CygUSD and USD (uses borrow indices)
        rate = exchangeRate();

        // Position in USD = CygUSD balance * Exchange Rate
        positionUsd = cygUsdBalance.mulWad(rate);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function getBorrowTokenPrice() external view override returns (uint256) {
        // Return price of the denom token
        return nebula.denominationTokenPrice();
    }

    // Interest rate model

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function borrowRate() external view override returns (uint256 latestBorrowRate) {
        // Get the current borrows with interest
        // Calculates the borrow rate with the stored borrows and simulate interest
        // accrual up to this point.
        (uint256 cash, uint256 borrows, , , ) = _borrowIndices();

        // Calculates the latest borrow rate with the new increased borrows
        latestBorrowRate = _latestBorrowRate(cash, borrows);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function supplyRate() external view override returns (uint256) {
        // Get the latest borrows with interest accrued
        (uint256 cash, uint256 borrows, , , ) = _borrowIndices();

        // Latest per second borrow rate with updated borrows
        uint256 latestBorrowRate = _latestBorrowRate(cash, borrows);

        // Current burrow rate taking into account the reserve factor
        uint256 rateToPool = uint256(latestBorrowRate).mulWad(1e18 - reserveFactor);

        // Avoid divide by 0
        if (borrows == 0) return 0;

        // Utilization rate
        uint256 util = uint256(borrows).divWad(cash + borrows);

        // Return pool supply rate
        return util.mulWad(rateToPool);
    }

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function utilizationRate() external view override returns (uint256) {
        /// Get the latest borrows with interest accrued
        (uint256 cash, uint256 borrows, , , ) = _borrowIndices();

        // Return the current pool utilization rate - we don't take into account reserves since we mint CygUSD
        return borrows == 0 ? 0 : borrows.divWad(cash + borrows);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Track borrows and lending rewards
     *  @param account The address of the lender or borrower
     *  @param balance Record of this borrower's total borrows up to this point
     *  @param collateral Whether the position is a lend or borrow position
     */
    function trackRewardsPrivate(address account, uint256 balance, address collateral) private {
        // Latest pillars of creation address
        address rewarder = pillarsOfCreation;

        // If pillars of creation is set then track reward
        if (rewarder != address(0)) IPillarsOfCreation(rewarder).trackRewards(account, balance, collateral);
    }

    /**
     *  @notice Mints reserves to the DAO based on the interest accumulated.
     *  @param cash Total cash in the strategy
     *  @param borrows Total latest borrows with interest accrued
     *  @param interest The total interest we have accrued during this accrual
     *  @return newReserves The amount of CygUSD minted based on `interestAccumulated and the current exchangeRate
     */
    function mintReservesPrivate(uint256 cash, uint256 borrows, uint256 interest) private returns (uint256 newReserves) {
        // Calculate the reserves to keep from the total interest accrued (interest * reserveFactor)
        newReserves = interest.mulWad(reserveFactor);

        // Check to mint new reserves
        if (newReserves > 0) {
            // Since we mint CygUSD, calculate the amount of CygUSD reserves to mint
            // Same as `_convertToShares` but use cash from `_borrowIndices` for gas savings and allow for 0 shares
            uint256 cygUsdReserves = newReserves.fullMulDiv(totalSupply(), (cash + borrows - newReserves));

            // Get the DAO Reserves current address, DAO reserves is never zero
            address daoReserves = hangar18.daoReserves();

            // Mint to Hangar18's latest `daoReserves`
            _mint(daoReserves, cygUsdReserves);
        }
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Applies accrued interest to total borrows and reserves
     *  @notice Calculates the interest accumulated during the time elapsed since the last accrual and mints reserves accordingly.
     */
    function _accrueInterest() internal {
        // Get borrow indices
        (uint256 cash, uint256 borrows, uint256 index, uint256 timeElapsed, uint256 interest) = _borrowIndices();

        // Escape if no time has past since last accrue
        if (timeElapsed == 0) return;

        // Mint reserves (if any) before updating borrows storage
        uint256 newReserves = mintReservesPrivate(cash, borrows, interest);

        // ──────────────────── Store values: 1 memory slot ─────────────────────
        // Store total borrows with interests
        _totalBorrows = SafeCastLib.toUint144(borrows);

        // Store latest borrow index
        _borrowIndex = SafeCastLib.toUint80(index);

        // This accruals' timestamp
        _accrualTimestamp = SafeCastLib.toUint32(block.timestamp);

        // ──────────────────────────────────────────────────────────────────────
        /// @custom:event AccrueInterest
        emit AccrueInterest(cash, borrows, interest, newReserves);
    }

    /**
     * @notice Updates the borrow balance of a borrower and the total borrows of the protocol.
     * @param borrower The address of the borrower whose borrow balance is being updated.
     * @param borrowAmount The amount of tokens being borrowed by the borrower.
     * @param repayAmount The amount of tokens being repaid by the borrower.
     * @return accountBorrows The borrower's updated borrow balance
     */
    function _updateBorrow(address borrower, uint256 borrowAmount, uint256 repayAmount) internal returns (uint256 accountBorrows) {
        // Get the borrower's latest borrow balance.
        // This is always guaranteed to be the latest borrow balance as this function is only called
        // after `borrow` and `liquidate` which accrue interest beforehand.
        (, uint256 borrowBalance) = _latestBorrowBalance(borrower, false);

        // If the borrow amount is equal to the repay amount, return the current borrow balance
        if (borrowAmount == repayAmount) return borrowBalance;

        // Get the current borrow index
        uint256 borrowIndexStored = _borrowIndex;

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
            uint256 totalBorrowsStored = _totalBorrows + increaseBorrowAmount;

            // Update total borrows to storage
            _totalBorrows = SafeCastLib.toUint144(totalBorrowsStored);
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
            uint256 totalBorrowsStored = _totalBorrows;

            // Never underflows
            unchecked {
                // Condition check to update protocols total borrows
                totalBorrowsStored = totalBorrowsStored > actualDecreaseAmount ? totalBorrowsStored - actualDecreaseAmount : 0;
            }

            // Update total protocol borrows
            _totalBorrows = SafeCastLib.toUint144(totalBorrowsStored);
        }

        // Track borrower
        trackRewardsPrivate(borrower, borrowSnapshot.principal, twinstar);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowModel
     */
    function trackLender(address lender) public override {
        // Get latest CygUSD balance
        uint256 balance = balanceOf(lender);

        // Pass balance with address(0) as collateral - The rewarder will calculate the exchange rate of CygUSD to USD to
        // correctly track how much USD the user currently has.
        trackRewardsPrivate(lender, balance, address(0));
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
        // Rewards are paid out on borrower's principal (original borrowed amount), so no need to accrue.
        (uint256 principal, ) = _latestBorrowBalance(borrower, false);

        // Pass borrower info to the Rewarder (if any)
        trackRewardsPrivate(borrower, principal, twinstar);
    }
}
