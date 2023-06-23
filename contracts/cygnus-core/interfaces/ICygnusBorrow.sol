//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusBorrow.sol
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
import {ICygnusBorrowVoid} from "./ICygnusBorrowVoid.sol";

// Overrides
import {ICygnusTerminal} from "./ICygnusTerminal.sol";

/**
 *  @title ICygnusBorrow Interface for the main Borrow contract which handles borrows/liquidations
 *  @notice Main interface to borrow against collateral or liquidate positions
 */
interface ICygnusBorrow is ICygnusBorrowVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the borrow amount is higher than total balance
     *
     *  @custom:error BorrowExceedsTotalBalance
     */
    error CygnusBorrow__BorrowExceedsTotalBalance();

    /**
     *  @dev Reverts if the borrower has insufficient liquidity for this borrow
     *
     *  @custom:error InsufficientLiquidity
     */
    error CygnusBorrow__InsufficientLiquidity();

    /**
     *  @dev Reverts if borrowAmount is higher than 0 during a repay tx
     *
     *  @custom:error BorrowAndRepayOverload
     */
    error CygnusBorrow__BorrowRepayOverload();

    /**
     *  @dev Reverts if usd received is less than repaid after liquidating
     *
     *  @custom:error InsufficientUsdReceived
     */
    error CygnusBorrow__InsufficientUsdReceived();

    /**
     *  @dev Reverts if liquidating 0 USD
     *
     *  @custom:error CantRepayZero Reverts if liquidating 0 USD
     */
    error CygnusBorrow__CantRepayZero();

    /**
     *  @dev Reverts if repay is more than total borrows
     *
     *  @custom:error InvalidRepayAmount
     */
    error CygnusBorrow__InvalidRepayAmount();

    /**
     *  @dev Reverts if msg.sender is not allowed to borrow on behalf of `borrower`
     *
     *  @custom:error MasterApprovalDisabled
     */
    error CygnusBorrow__MasterApprovalDisabled();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a liquidator repays and seizes collateral
     *
     *  @param sender Indexed address of msg.sender (should be `Altair` address)
     *  @param borrower Indexed address of the borrower
     *  @param receiver Indexed address of receiver
     *  @param repayAmount The amount of USD repaid
     *  @param cygLPAmount The amount of CygLP seized
     *  @param usdAmount The total amount of underlying deposited
     *
     *  @custom:event Liquidate
     */
    event Liquidate(
        address indexed sender,
        address indexed borrower,
        address indexed receiver,
        uint256 repayAmount,
        uint256 cygLPAmount,
        uint256 usdAmount
    );

    /**
     *  @dev Logs when a borrower takes out a loan
     *
     *  @param sender Indexed address of msg.sender (should be `Altair` address)
     *  @param borrower Indexed address of the borrower
     *  @param receiver Indexed address of receiver
     *  @param borrowAmount The amount of USD borrowed
     *  @param repayAmount The amount of USD repaid
     *
     *  @custom:event Borrow
     */
    event Borrow(
        address indexed sender,
        address indexed borrower,
        address indexed receiver,
        uint256 borrowAmount,
        uint256 repayAmount
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *
     *  @param borrower The address of the Borrow contract.
     *  @param receiver The address of the receiver of the borrow amount.
     *  @param borrowAmount The amount of the underlying asset to borrow.
     *  @param data Calltype data passed to Router contract.
     *
     *  @custom:security non-reentrant
     */
    function borrow(address borrower, address receiver, uint256 borrowAmount, bytes calldata data) external;

    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *
     *  @param borrower The address of the borrower being liquidated
     *  @param receiver The address of the receiver of the collateral
     *  @param repayAmount USD amount covering the loan
     *  @param data Calltype data passed to Router contract.
     *  @return usdAmount The amount of USD deposited after taking into account liq. incentive
     *
     *  @custom:security non-reentrant
     */
    function liquidate(
        address borrower,
        address receiver,
        uint256 repayAmount,
        bytes calldata data
    ) external returns (uint256 usdAmount);

    /**
     *  @notice Syncs internal balance with totalBalance
     *
     *  @custom:security non-reentrant
     */
    function sync() external;
}
