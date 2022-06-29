// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

import { ICygnusBorrowTracker } from "./ICygnusBorrowTracker.sol";

/**
 *  @title ICygnusBorrow Interface for the main Borrow contract which handles borrows/liquidations
 */
interface ICygnusBorrow is ICygnusBorrowTracker {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error Emitted when the borrow amount is higher than total balance
     */
    error CygnusBorrow__BorrowExceedsTotalBalance(uint256);

    /**
     *  @custom:error Emitted if there is a shortfall in the account's balances.
     */
    error CygnusBorrow__InsufficientLiquidity();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when an account liquidates a borrower
     *  @param sender Indexed address of msg.sender (should be `Router` address
     *  @param borrower Indexed address the account with negative account liquidity that shall be liquidated
     *  @param liquidator Indexed address of the liquidator
     *  @param denebAmount The amount of the underlying asset to be seized
     *  @param repayAmount The amount of the underlying asset to be repaid (factors in liquidation incentive)
     *  @param accountBorrowsPrior Record of borrower's total borrows before this event
     *  @param accountBorrows Record of borrower's present borrows (accountBorrowsPrior + borrowAmount)
     *  @param totalBorrowsStored Record of the protocol's cummulative total borrows after this event
     *  @custom:event Liquidate Emitted upon a successful liquidation
     */
    event Liquidate(
        address indexed sender,
        address indexed borrower,
        address indexed liquidator,
        uint256 denebAmount,
        uint256 repayAmount,
        uint256 accountBorrowsPrior,
        uint256 accountBorrows,
        uint256 totalBorrowsStored
    );

    /**
     *  @notice Event for account borrows and repays indexed by periphery, borrower and receiver addresses
     *  @param sender Indexed address of msg.sender (should be `Router` address)
     *  @param receiver Indexed address of receiver (if repay = this is address(0), if borrow `Router` address)
     *  @param borrower Indexed address of the borrower
     *  @param borrowAmount If borrow calldata, the amount of the underlying asset to be borrowed, else 0
     *  @param repayAmount If repay calldata, the amount of the underlying borrowed asset to be repaid, else 0
     *  @param accountBorrowsPrior Record of borrower's total borrows before this event
     *  @param accountBorrows Record of borrower's total borrows after this event ( + borrowAmount) or ( - repayAmount)
     *  @param totalBorrowsStored Record of the protocol's cummulative total borrows after this event.
     *  @custom:event Borrow Emitted upon a successful borrow or repay
     */
    event Borrow(
        address indexed sender,
        address indexed borrower,
        address indexed receiver,
        uint256 borrowAmount,
        uint256 repayAmount,
        uint256 accountBorrowsPrior,
        uint256 accountBorrows,
        uint256 totalBorrowsStored
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *  @param borrower The address of the borrower being liquidated
     *  @param liquidator The address of the liquidator
     *  @return seizeTokens The amount of tokens to liquidate
     */
    function liquidate(address borrower, address liquidator) external returns (uint256 seizeTokens);

    /**
     *  @notice This low level function should only be called from Router contract only.
     *  @param borrower The address of the Borrow contract.
     *  @param receiver The address of the receiver of the borrow amount.
     *  @param borrowAmount The amount of the underlying asset to borrow.
     *  @param data Calltype data passed to Router contract.
     */
    function borrow(
        address borrower,
        address receiver,
        uint256 borrowAmount,
        bytes calldata data
    ) external;

    /**
     *  @notice Overrides the exchange rate of `CygnusTerminal` for borrow contracts to mint reserves
     */
    function exchangeRate() external override returns (uint256);

    /**
     *  @notice Overrides the sync of `CygnusTerminal`
     */
    function sync() external override;
}
