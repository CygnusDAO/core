// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";
import {CygnusBorrowVoid} from "./CygnusBorrowVoid.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusTerminal} from "./CygnusTerminal.sol";
import {ICygnusCollateral} from "./interfaces/ICygnusCollateral.sol";
import {ICygnusAltairCall} from "./interfaces/ICygnusAltairCall.sol";

/**
 *  @title  CygnusBorrow Main borrow contract for Cygnus which handles borrows, liquidations and reserves.
 *  @notice This is the main Borrow contract which is used for borrowing stablecoins and liquidating shortfall
 *          positions.
 *
 *          It also overrides the `exchangeRate` function at CygnusTerminal and we add the accrue modifiers,
 *          to accrue interest during deposits and redeems.
 *
 *          Reserves are also minted to the address `daoReserves` of the CygnusFactory (`hangar18`). The way
 *          the DAO accumulates reserves is not through underlying but through the minting of CygUSD.
 *
 *          The `borrow` function allows anyone to borrow or leverage USD to buy more LP Tokens. If calldata is
 *          passed, then the function calls the `altairBorrow` function on the router, and leverages users'
 *          position. If there is no calldata, the user can simply borrow instead of leveraging. The same borrow
 *          function is used to repay a loan, by checking the totalBalance held of underlying.
 */
contract CygnusBorrow is ICygnusBorrow, CygnusBorrowVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
         6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice mints reserves to CygnusReservesManager. Uses the mintedReserves variable to keep internal track
     *          of reserves instead of balanceOf
     *  @param _exchangeRate The current exchange rate between underlying and CygUSD
     *  @param _totalReserves The total reserves up to this point
     *  @return Latest exchange rate
     */
    function mintReservesInternal(uint256 _exchangeRate, uint256 _totalReserves) internal returns (uint256) {
        // Calculate new reserves if any
        uint256 newReserves = _totalReserves - mintedReserves;

        // if there are no new reserves to mint, just return exchangeRate
        if (newReserves > 0) {
            // Get the current DAO reserves contract
            address daoReserves = hangar18.daoReserves();

            // Mint new resereves
            mintInternal(daoReserves, newReserves);

            unchecked {
                // Update minted reserves
                mintedReserves += newReserves;
            }
        }

        // Return new exchange rate
        return _exchangeRate;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Overrides the previous exchange rate from CygnusTerminal
     *  @inheritdoc ICygnusBorrow
     */
    function exchangeRate() public override(ICygnusBorrow, ICygnusTerminal) accrue returns (uint256) {
        // Save SLOAD if non zero
        uint256 _totalSupply = totalSupply;

        // If there are no tokens in circulation, return initial (1e18), else calculate new exchange rate
        if (_totalSupply == 0) return 1e18;

        // Gas savings
        uint256 _totalReserves = totalReserves;

        // New Exchange Rate = (totalBalance + totalBorrows - reserves) / totalSupply
        uint256 _exchangeRate = (totalBalance + totalBorrows - _totalReserves).divWad(_totalSupply);

        // Check if there are new reserves to mint
        return mintReservesInternal(_exchangeRate, _totalReserves);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This low level function should only be called from `Altair` contract only
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function borrow(
        address borrower,
        address receiver,
        uint256 borrowAmount,
        bytes calldata data
    ) external override nonReentrant update accrue {
        // Gas savings
        uint256 totalBalanceStored = totalBalance;

        /// @custom:error BorrowExceedsTotalBalance Avoid borrowing more than pool's underlying balance
        if (borrowAmount > totalBalanceStored) {
            revert CygnusBorrow__BorrowExceedsTotalBalance({
                invalidBorrowAmount: borrowAmount,
                contractBalance: totalBalanceStored
            });
        }

        // Optimistically transfer borrowAmount to `receiver`
        if (borrowAmount > 0) {
            // Withdraw `borrowAmount` from strategy
            beforeWithdrawInternal(borrowAmount);

            // Transfer
            underlying.safeTransfer(receiver, borrowAmount);
        }

        // For leverage functionality pass data to the router
        if (data.length > 0) {
            ICygnusAltairCall(receiver).altairBorrow_O9E(_msgSender(), borrowAmount, data);
        }

        // If repaying get the repay amount
        uint256 repayAmount = contractBalanceOf(underlying);

        // We check both for non-zero, ideally we should add borrowAmount to the repayAmount and substract from the
        // total balance, but can cause arithmetic underflow depending on current rewards earned
        if (borrowAmount > 0 && repayAmount > 0) {
            /// @custom:error BorrowAndRepayOverload Avoid borrowing and repaying on the same TX
            revert CygnusBorrow__BorrowAndRepayOverload({borrowAmount: borrowAmount, repayAmount: repayAmount});
        }

        // Update internal record for `borrower` at Cygnus Borrow Tracker
        (uint256 accountBorrowsPrior, uint256 accountBorrows, uint256 totalBorrowsStored) = updateBorrowInternal(
            borrower,
            borrowAmount,
            repayAmount
        );

        // If this is a borrow, check borrower's current liquidity/shortfall
        if (borrowAmount > repayAmount) {
            // Check if user can borrow and updates collateral totalBalance
            bool userCanBorrow = ICygnusCollateral(collateral).canBorrow(borrower, address(this), accountBorrows);

            /// @custom:error InsufficientLiquidity Avoid if borrower has insufficient liquidity for this `borrowAmount`
            if (!userCanBorrow) {
                revert CygnusBorrow__InsufficientLiquidity({
                    cygnusCollateral: collateral,
                    borrower: borrower,
                    borrowerBalance: accountBorrows
                });
            }
        } else afterDepositInternal(repayAmount);

        /// @custom:event Borrow
        emit Borrow(
            _msgSender(),
            receiver,
            borrower,
            borrowAmount,
            repayAmount,
            accountBorrowsPrior,
            accountBorrows,
            totalBorrowsStored
        );
    }

    /**
     *  @dev This low level function should only be called from `Altair` contract only
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function liquidate(
        address borrower,
        address liquidator
    ) external override nonReentrant update accrue returns (uint256 cygLPAmount) {
        // Underlying balance sent to this contract
        uint256 repayAmount = contractBalanceOf(underlying);

        // Borrow balance
        uint256 borrowerBalance = getBorrowBalance(borrower);

        // Avoid repaying more than borrower's borrow balance
        uint256 actualRepayAmount = borrowerBalance < repayAmount ? borrowerBalance : repayAmount;

        // Amount to seize
        cygLPAmount = ICygnusCollateral(collateral).seizeCygLP(liquidator, borrower, actualRepayAmount);

        // Update borrows
        (uint256 accountBorrowsPrior, uint256 accountBorrows, uint256 totalBorrowsStored) = updateBorrowInternal(
            borrower,
            0,
            repayAmount
        );

        // Deposit underlying in strategy
        afterDepositInternal(repayAmount);

        /// @custom:event Liquidate
        emit Liquidate(
            _msgSender(),
            borrower,
            liquidator,
            cygLPAmount,
            repayAmount,
            accountBorrowsPrior,
            accountBorrows,
            totalBorrowsStored
        );
    }
}
