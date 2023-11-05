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
     *  @dev Reverts if the borrower has insufficient liquidity for this borrow
     *  @custom:error InsufficientLiquidity
     */
    error CygnusBorrow__InsufficientLiquidity();

    /**
     *  @dev Reverts if usd received is less than repaid after liquidating
     *  @custom:error InsufficientUsdReceived
     */
    error CygnusBorrow__InsufficientUsdReceived();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a borrower borrows or repays a loan.
     *  @param sender Indexed address of msg.sender
     *  @param borrower Indexed address of the borrower
     *  @param receiver Indexed address of receiver
     *  @param borrowAmount The amount of stablecoins borrowed (if any)
     *  @param repayAmount The amount of stablecoins repaid (if any)
     *  @custom:event Borrow
     */
    event Borrow(address indexed sender, address indexed borrower, address indexed receiver, uint256 borrowAmount, uint256 repayAmount);

    /**
     *  @dev Logs when a liquidator repays and seizes collateral
     *  @param sender Indexed address of msg.sender (should be `Altair` address)
     *  @param borrower Indexed address of the borrower
     *  @param receiver Indexed address of receiver
     *  @param repayAmount The amount of USD repaid
     *  @param cygLPAmount The amount of CygLP seized
     *  @param usdAmount The total amount of underlying deposited
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

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice This low level function should be called from a periphery contract only
     *  @notice Main function used to borrow stablecoins or repay loans.
     *  @param borrower The address of the borrower
     *  @param receiver The address of the receiver of the borrow amount.
     *  @param borrowAmount The amount of the underlying asset to borrow.
     *  @param data Calldata passed to a router contract
     *  @custom:security non-reentrant
     */
    function borrow(address borrower, address receiver, uint256 borrowAmount, bytes calldata data) external returns (uint256);

    /**
     *  @notice This low level function should be called from a periphery contract only
     *  @notice Main function used to liquidate or flash liquidation positions.
     *  @param borrower The address of the borrower being liquidated
     *  @param receiver The address of the receiver of the collateral
     *  @param repayAmount USD amount covering the loan
     *  @param data Calldata passed to a router contract
     *  @return usdAmount The amount of USD deposited after taking into account liq. incentive
     *  @custom:security non-reentrant
     */
    function liquidate(address borrower, address receiver, uint256 repayAmount, bytes calldata data) external returns (uint256 usdAmount);
}
