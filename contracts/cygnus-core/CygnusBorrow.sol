// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrow } from "./interfaces/ICygnusBorrow.sol";
import { CygnusBorrowTracker } from "./CygnusBorrowTracker.sol";

// Libraries
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusCollateral } from "./interfaces/ICygnusCollateral.sol";
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { ICygnusAltairCall } from "./interfaces/ICygnusAltairCall.sol";

/**
 *  @title  CygnusBorrow Main borrow contract for Cygnus which handles borrows, liquidations and reserves.
 *  @notice This is the main Borrow contract which is used for borrowing USDC and liquidating shortfall positions.
 *          It also overrides the `exchangeRate` function at CygnusTerminal and we add the accrue modifiers,
 *          to accrue interest during deposits and redeems.
 *
 *          Reserves are also minted to the address `daoReserves` of the CygnusFactory (`hangar18`). The way
 *          the DAO accumulates reserves is not through USDC but through the minting of CygUSD.
 *
 *          The `borrow` function allows anyone to borrow or leverage USDc to buy more LP Tokens. If calldata is
 *          passed, then the function calls the `altairBorrow` function on the router, and leverages users'
 *          position. If there is no calldata, the user can simply borrow instead of leveraging. The same borrow
 *          function is used to repay a loan, by checking the totalBalance held of USDC (the router handles this).
 */
contract CygnusBorrow is ICygnusBorrow, CygnusBorrowTracker {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*
     *  @custom:library SafeTransferLib Low level handling of Erc20 tokens
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
         6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice mints reserves to CygnusReservesManager. Uses the mintedReserves variable to keep internal track
     *          of reserves instead of balanceOf
     *  @param _exchangeRate The latest calculated exchange rate (totalBalance / totalSupply) not yet stored
     *  @return Latest exchange rate
     */
    function mintReservesInternal(uint256 _exchangeRate) internal returns (uint256) {
        // Get current exchange rate stored for borrow contract
        uint256 exchangeRateLast = exchangeRateStored;

        // Calculate new exchange rate, if different to last mint reserves
        if (_exchangeRate > exchangeRateLast) {
            // Calculate new exchange rate taking reserves into account
            uint256 newExchangeRate = _exchangeRate - ((_exchangeRate - exchangeRateLast).mul(reserveFactor));

            // Calculate new reserves if any
            uint256 newReserves = totalReserves - mintedReserves;

            // if there are no new reserves to mint, just return exchangeRate
            if (newReserves == 0) {
                return _exchangeRate;
            }

            // Get the current DAO reserves contract
            address daoReserves = ICygnusFactory(hangar18).daoReserves();

            // Mint new resereves and upate the exchange rate
            mintInternal(daoReserves, newReserves);

            // Add to internal record of reserves
            mintedReserves += newReserves;

            // Update exchange rate
            exchangeRateStored = newExchangeRate;

            // Return new exchange rate
            return newExchangeRate;
        }
        // Else return the previous exchange rate
        else return _exchangeRate;
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
        if (_totalSupply == 0) {
            return 1e18;
        }

        // newExchangeRate = (totalBalance + totalBorrows - reserves) / totalSupply
        // Factor in reserves in next mint function
        uint256 _totalBalance = totalBalance + totalBorrows;

        // totalBalance * scale / total supply
        uint256 _exchangeRate = _totalBalance.div(_totalSupply);

        // Check if there are new reserves to mint and thus new exchange rate, else just returns this _exchangeRate
        return mintReservesInternal(_exchangeRate);
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

        /// @custom:error BorrowExceedsTotalBalance Avoid borrowing more than pool's USDC balance
        if (borrowAmount > totalBalanceStored) {
            revert CygnusBorrow__BorrowExceedsTotalBalance({
                invalidBorrowAmount: borrowAmount,
                contractBalance: totalBalanceStored
            });
        }

        // Check borrow allowance at Cygnus Borrow Approve
        borrowApproveUpdate(borrower, _msgSender(), borrowAmount);

        // Optimistically transfer borrowAmount to `receiver`
        if (borrowAmount > 0) {
            underlying.safeTransfer(receiver, borrowAmount);
        }

        // For leverage functionality pass data to the router
        if (data.length > 0) {
            ICygnusAltairCall(receiver).altairBorrow_O9E(_msgSender(), borrowAmount, data);
        }

        // Get total balance of the underlying asset
        uint256 balance = IERC20(underlying).balanceOf(address(this));

        // Calculate the user's amount outstanding
        uint256 repayAmount = (balance + borrowAmount) - totalBalanceStored;

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
        }

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
    function liquidate(address borrower, address liquidator)
        external
        override
        nonReentrant
        update
        accrue
        returns (uint256 cygLPAmount)
    {
        // Latest balance after accrue's sync
        uint256 balance = IERC20(underlying).balanceOf(address(this));

        // Borrow balance
        uint256 borrowerBalance = getBorrowBalance(borrower);

        // Get amount liquidator is repaying
        uint256 repayAmount = balance - totalBalance;

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
