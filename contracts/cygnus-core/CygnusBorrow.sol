//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusBorrow.sol
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

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
    
           █████████                🛸                                       🛸          .                    
          ███░░░░░███                                              📡                                     🌔   
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .             
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .           
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .
                       ███ ░███  ███ ░███                .                 .         🛸           ⠀             
         .      *     ░░██████  ░░██████   .                         🛰️                 .          .        
                       ░░░░░░    ░░░░░░                                                 ⠀
           .                            .       .         ------======*             .                          
    
        BORROWABLE (CygUSD) - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════

     Smart contracts to lend stablecoins to liquidity providers.

     Deposit USD, earn USD.

     Structure of all Cygnus Contracts:

     Contract                        ⠀Interface                                             
        ├ 1. Libraries                   ├ 1. Custom Errors                                               
        ├ 2. Storage                     ├ 2. Custom Events
        │     ├ Private             ⠀    ├ 3. Constant Functions                          ⠀        
        │     ├ Internal                 │     ├ Public                            ⠀       
        │     └ Public                   │     └ External                        ⠀⠀⠀              
        ├ 3. Constructor                 └ 4. Non-Constant Functions  
        ├ 4. Modifiers              ⠀          ├ Public
        ├ 5. Constant Functions     ⠀          └ External
        │     ├ Private             ⠀                      
        │     ├ Internal            
        │     ├ Public              
        │     └ External            
        └ 6. Non-Constant Functions 
              ├ Private             
              ├ Internal            
              ├ Public              
              └ External            

    @dev: Inspired by Impermax, follows similar architecture and code but with significant edits. It should 
          only be tested with Solidity >=0.8 as some functions don't check for overflow/underflow and all errors
          are handled with the new `custom errors` feature among other small things...                           */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";
import {CygnusBorrowVoid} from "./CygnusBorrowVoid.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {ICygnusCollateral} from "./interfaces/ICygnusCollateral.sol";
import {ICygnusAltairCall} from "./interfaces/ICygnusAltairCall.sol";
import {ICygnusTerminal} from "./interfaces/ICygnusTerminal.sol";
import {IPillarsOfCreation} from "./interfaces/IPillarsOfCreation.sol";

// Overrides
import {CygnusTerminal} from "./CygnusTerminal.sol";
import {ERC20} from "./ERC20.sol";

/**
 *  @title  CygnusBorrow Main borrow contract for Cygnus which handles borrows, repays, liquidations & flash liqudiations
 *  @author CygnusDAO
 *  @notice This is the main Borrow contract which is used for borrowing stablecoins and liquidating shortfall
 *          positions.
 *
 *          The `borrow` function allows anyone to borrow or leverage USD to buy more LP Tokens. If calldata is
 *          passed, then the function calls the `altairBorrow` function on the sender, which should be used to
 *          leverage positions. If there is no calldata, the user can simply borrow instead of leveraging. The
 *          same borrow function is used to repay a loan, by checking the totalBalance held of underlying. 
 *          The function also allows anyone to perform a flash loan, as long as the amount repaid is greater
 *          than or equal the borrowed amount.
 *
 *          The `liquidate` function allows anyone to liquidate or flash liquidate a position. When using
 *          this function with no calldata then the liquidator must have sent an amount of USDC to repay the loan.
 *          When using the function with calldata it allows the user to liquidate a position, and pass this data
 *          to a periphery contract, where it should implement the logic to sell the collateral to the market,
 *          receive USDC and finally repay this contract. The function does the check at the end to ensure
 *          we have received a correct amount of USDC.
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
     *  @notice ERC20 Override
     *  @notice Tracks lender's position AFTER any transfer/mint/burn/etc. CygUSD is the lender token and should always
     *          be tracked at core and updated on any interaction.
     */
    function _afterTokenTransfer(address from, address to, uint256) internal override(ERC20) {
        // Check for zero address (in case of mints)
        if (from != address(0)) trackLender(from);

        // Check for zero address (in case of burns)
        if (to != address(0)) trackLender(to);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This low level function should be called from a periphery contract only
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function borrow(
        address borrower,
        address receiver,
        uint256 borrowAmount,
        bytes calldata data
    ) external override nonReentrant update returns (uint256 liquidity) {
        // Check if msg.sender can borrow on behalf of borrower, we use the same spend allowance as redeem
        if (borrower != msg.sender) _spendAllowance(borrower, msg.sender, borrowAmount);

        // ────────── 1. Check amount and optimistically send `borrowAmount` to `receiver`
        // We optimistically transfer borrow amounts and check in step 5 if borrower has enough liquidity to borrow.
        if (borrowAmount > 0) {
            // Withdraw `borrowAmount` from strategy
            _beforeWithdraw(borrowAmount);

            // Transfer stablecoin to receiver
            underlying.safeTransfer(receiver, borrowAmount);
        }

        // ────────── 2. Pass data to the router if needed
        // Check data for leverage transaction, if any pass data to router. `liquidity` is the amount of LP received
        if (data.length > 0) liquidity = ICygnusAltairCall(msg.sender).altairBorrow_O9E(msg.sender, borrowAmount, data);

        // ────────── 3. Get the repay amount (if any)
        // Borrow/Repay use this same function. To repay the loan the user must have sent back stablecoins to this contract.
        // Any stablecoin sent directly here is not deposited in the strategy yet.
        uint256 repayAmount = _checkBalance(underlying);

        // ────────── 4. Update borrow internally with borrowAmount and repayAmount
        // IMPORTANT: During tests we want to keep track here of what was actually withdrawn from the strategy
        //            and what was the borrowAmount passed. Always check that withdrawing is correct and ensure
        //            there is no rounding errors.

        // Update internal record for `borrower` with borrow and repay amount
        uint256 accountBorrows = _updateBorrow(borrower, borrowAmount, repayAmount);

        // ────────── 5. Do checks for borrow and repay transactions
        // Borrow transaction. Check that the borrower has sufficient collateral after borrowing `borrowAmount` by
        // passing `accountBorrows` to the collateral contract
        if (borrowAmount > repayAmount) {
            // Check borrower's current liquidity/shortfall
            bool userCanBorrow = ICygnusCollateral(twinstar).canBorrow(borrower, accountBorrows);

            /// @custom:error InsufficientLiquidity Avoid if borrower has insufficient liquidity for this amount
            if (!userCanBorrow) revert CygnusBorrow__InsufficientLiquidity();
        }

        // Deposit repay amount (if any) in strategy
        if (repayAmount > 0) _afterDeposit(repayAmount);

        /// @custom:event Borrow
        emit Borrow(msg.sender, borrower, receiver, borrowAmount, repayAmount);
    }

    /**
     *  @dev This low level function should be called from a periphery contract only
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function liquidate(
        address borrower,
        address receiver,
        uint256 repayAmount,
        bytes calldata data
    ) external override nonReentrant update returns (uint256 amountUsd) {
        // ────────── 1. Get borrower's USD debt - The `update` modifier will accrue interest before this call
        // Latest borrow balance
        (, uint256 borrowBalance) = getBorrowBalance(borrower);

        // Adjust declared amount to max liquidatable, this is the actual repaid amount
        uint256 max = borrowBalance < repayAmount ? borrowBalance : repayAmount;

        // ────────── 2. Seize CygLP from borrower
        // CygLP = (max * liq. incentive) / lp price.
        // Reverts at Collateral if:
        // - `max` is 0.
        // - `borrower`'s position is not in liquidatable state
        uint256 cygLPAmount = ICygnusCollateral(twinstar).seizeCygLP(receiver, borrower, max);

        // ────────── 3. Check for data length in case sender sells the collateral to market
        // If the `receiver` was the router used to flash liquidate then we call the router with the data passed,
        // allowing the collateral to be sold to the market
        if (data.length > 0) ICygnusAltairCall(msg.sender).altairLiquidate_f2x(msg.sender, cygLPAmount, max, data);

        // ────────── 4. Get the repaid amount of USD
        // Current balance of USD not deposited in strategy (if sell to market then router must have sent back USD).
        // The amount received back would have to be equal at least to `max`, allowing liquidator to keep the liquidation incentive
        amountUsd = _checkBalance(underlying);

        /// @custom:error InsufficientUsdReceived Avoid liquidating if we received less usd than declared
        if (amountUsd < max) revert CygnusBorrow__InsufficientUsdReceived();

        // ────────── 5. Update borrow internally with 0 borrow amount and the amount of usd received
        // Pass to CygnusBorrowModel
        _updateBorrow(borrower, 0, amountUsd);

        // ────────── 6. Deposit in strategy
        // Deposit underlying in strategy, if 0 then would've reverted by now
        _afterDeposit(amountUsd);

        /// @custom:event Liquidate
        emit Liquidate(msg.sender, borrower, receiver, cygLPAmount, max, amountUsd);
    }

    /**
     *  @inheritdoc ICygnusBorrow
     *  @custom:security non-reentrant
     */
    function sync() external override nonReentrant update {}
}
