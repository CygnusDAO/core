// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrow } from "./interfaces/ICygnusBorrow.sol";
import { CygnusBorrowTracker } from "./CygnusBorrowTracker.sol";

// Interfaces
import { ICygnusCollateral } from "./interfaces/ICygnusCollateral.sol";
import { ICygnusCallee } from "./interfaces/ICygnusCallee.sol";
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { IErc20 } from "./interfaces/IErc20.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";

// Libraries
import { SafeErc20 } from "./libraries/SafeErc20.sol";
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

/**
 *  @title CygnusBorrow Main borrow contract for Cygnus which handles borrows, liquidations and reserves
 */
contract CygnusBorrow is ICygnusBorrow, CygnusBorrowTracker {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeErc20 For safe transfers of Erc20 tokens
     */
    using SafeErc20 for IErc20;

    /**
     *  @custom:library PRBMathUD60x18 for uint256 fixed point math, also imports the main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
         6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice mints reserves to CygnusReservesManager
     *  @param _exchangeRate The latest calculated exchange rate (totalBalance / totalSupply) not yet stored
     *  @param _totalSupply The latest stored total supply
     *  @return Latest exchange rate
     */
    function mintReservesInternal(uint256 _exchangeRate, uint256 _totalSupply) internal returns (uint256) {
        // Get current exchange rate stored for borrow contract
        uint256 _exchangeRateLast = exchangeRateStored;

        if (_exchangeRate > _exchangeRateLast) {
            // Calculate new exchange rate taking reserves int oaccount
            uint256 newExchangeRate = _exchangeRate - ((_exchangeRate - _exchangeRateLast).mul(reserveFactor));

            // Calculate new reserves if any
            uint256 newReserves = PRBMath.mulDiv(_totalSupply, _exchangeRate, newExchangeRate) - _totalSupply;

            // if there are no new reserves to mint, just return exchangeRate
            if (newReserves == 0) {
                return _exchangeRate;
            }
            // Mint new reserves and update the exchange rate
            address vegaTokenManager = ICygnusFactory(hangar18).vegaTokenManager();

            // Safe internal mint
            mintInternal(vegaTokenManager, newReserves);

            // Store new exchange rate
            exchangeRateStored = newExchangeRate;

            // Return new exchange rate
            return newExchangeRate;
        } else {
            // Return the previous exchange rate
            return _exchangeRate;
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Overrides the previous exchange rate from CygnusTerminal
     *  @inheritdoc ICygnusBorrow
     */
    function exchangeRate() public override(ICygnusBorrow, ICygnusTerminal) accrue returns (uint256) {
        // Save an SLOAD if non zero
        uint256 _totalSupply = totalSupply;

        // If there are no tokens in circulation, return initial (1e18), else calculate new exchange rate
        if (_totalSupply == 0) {
            return INITIAL_EXCHANGE_RATE;
        }

        // newExchangeRate = (totalBalance + totalBorrows - reserves) / totalSupply
        // Factor in reserves in next mint function
        uint256 _totalBalance = totalBalance + totalBorrows;

        // totalBalance * scale / total supply
        uint256 _exchangeRate = _totalBalance.div(_totalSupply);

        // Check if there are new reserves to mint and thus new exchange rate, else just returns this _exchangeRate
        return mintReservesInternal(_exchangeRate, _totalSupply);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This low level function should only be called from `Altair` contract only.
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function borrow(
        address borrower,
        address receiver,
        uint256 borrowAmount,
        bytes calldata data
    ) external override nonReentrant update accrue {
        uint256 totalBalanceStored = totalBalance;

        /// @custom:error BorrowExceedsTotalBalance Avoid if there's not enough cash
        if (borrowAmount > totalBalanceStored) {
            revert CygnusBorrow__BorrowExceedsTotalBalance(totalBalanceStored);
        }

        // Internally update the account's borrow approvals (balance - borrow amount)
        borrowApproveUpdate(borrower, _msgSender(), borrowAmount);

        // Optimistically transfer borrowAmount
        if (borrowAmount > 0) {
            IErc20(underlying).safeTransfer(receiver, borrowAmount);
        }

        // For leverage functionality, if data is not empty then callback to the router
        if (data.length > 0) {
            ICygnusCallee(receiver).cygnusBorrow(_msgSender(), borrower, borrowAmount, data);
        }

        // Get total balance of the underlying asset.
        uint256 balance = IErc20(underlying).balanceOf(address(this));

        // Calculate the user's amount outstanding.
        uint256 repayAmount = (balance + borrowAmount) - totalBalanceStored;

        // Update borrows internally.
        (uint256 accountBorrowsPrior, uint256 accountBorrows, uint256 totalBorrowsStored) = updateBorrowInternal(
            borrower,
            borrowAmount,
            repayAmount
        );

        if (borrowAmount > repayAmount) {
            /// @custom:error InsufficientLiquidity Avoid if borrower shortfall
            if (!ICygnusCollateral(collateral).canBorrow(borrower, address(this), accountBorrows)) {
                revert CygnusBorrow__InsufficientLiquidity();
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
        returns (uint256 denebAmount)
    {
        // Latest balance after accrue's sync
        uint256 balance = IErc20(underlying).balanceOf(address(this));

        // Borrow balance
        uint256 borrowerBalance = getBorrowBalance(borrower);

        uint256 repayAmount = balance - totalBalance;

        uint256 actualRepayAmount = borrowerBalance < repayAmount ? borrowerBalance : repayAmount;

        // Amount to seize
        denebAmount = ICygnusCollateral(collateral).seizeDeneb(liquidator, borrower, actualRepayAmount);

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
            denebAmount,
            repayAmount,
            accountBorrowsPrior,
            accountBorrows,
            totalBorrowsStored
        );
    }

    /**
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function sync() external override(ICygnusBorrow, ICygnusTerminal) nonReentrant update accrue {}
}
