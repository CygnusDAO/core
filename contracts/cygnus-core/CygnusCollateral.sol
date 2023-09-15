//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusCollateral.sol
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
    .              .            .               .      🛰️     .           .                .           .
           █████████     🛰️      ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                      . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .           .
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                           .⠀
                       ███ ░███  ███ ░███                .                 .                 .⠀
        .             ░░██████  ░░██████        🛰️                        🛰️             .                 .     
                       ░░░░░░    ░░░░░░      -------=========*                      .                     ⠀
           .                            .       .          .            .                        .             .⠀
        
        COLLATERAL (CygLP) - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════

     Smart contracts to `go long` on your liquidity.

     Deposit liquidity, borrow USD.

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
import {ICygnusCollateral} from "./interfaces/ICygnusCollateral.sol";
import {CygnusCollateralVoid} from "./CygnusCollateralVoid.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";
import {ICygnusAltairCall} from "./interfaces/ICygnusAltairCall.sol";

// Overrides
import {ERC20} from "./ERC20.sol";

/**
 *  @title  CygnusCollateral Main Collateral contract handles transfers and seizings of collateral
 *  @author CygnusDAO
 *  @notice This is the main Collateral contract which is used for liquidations and for flash redeeming the
 *          underlying. It also overrides the `burn` internal function, calling the borrowable arm to query
 *          the redeemer's current borrow balance to check if the user can redeem the LP Tokens.
 *
 *          When a user's position gets liquidated, it is initially called by the borrow arm. The liquidator
 *          first repays back stables to the borrowable arm and then calls `liquidate` which then calls
 *         `seizeCygLP` in this contract to seize the equivalent of the repaid amount + the liquidation
 *          incentive in CygLP.
 *
 *          There is a liquidation fee which can be set by the hangar18 admin that goes to the DAO Reserves,
 *          taken directly from the user being liquidated. This fee is set to 0 as default.
 *
 */
contract CygnusCollateral is ICygnusCollateral, CygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers.
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice ERC20 Overrides transfers of CygLP
     *  @notice Before any token transfer we check whether the user has sufficient liquidity (no debt) to transfer
     *  @inheritdoc ERC20
     */
    function _beforeTokenTransfer(address from, address, uint256 amount) internal view override(ERC20) {
        // Escape in case of `flashRedeemAltair()` and `mint()`
        // 1. This contract should never have CygLP outside of flash redeeming. If a user is flash redeeming it requires them
        // to `transfer()` or `transferFrom()` to this address first, and it will check `canRedeem` before transfer.
        if (from == address(this)) return;

        /// @custom:error InsufficientLiquidity Avoid transfers or burns if there's shortfall
        if (!canRedeem(from, amount)) revert CygnusCollateral__InsufficientLiquidity();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev No reason to update since there are no new balance updates
     *  @notice Not marked as non-reentrant since only the borrowable can call it through the non-reentrant `liquidate()`
     *  @inheritdoc ICygnusCollateral
     */
    function seizeCygLP(address liquidator, address borrower, uint256 repayAmount) external override returns (uint256 cygLPAmount) {
        /// @custom:error MsgSenderNotBorrowable Avoid unless msg sender is this shuttle's CygnusBorrow contract
        if (msg.sender != twinstar) revert CygnusCollateral__MsgSenderNotBorrowable();
        /// @custom:erro CantLiquidateZero Avoid liquidating 0 repayAmount
        else if (repayAmount == 0) revert CygnusCollateral__CantLiquidateZero();

        // Get user's shortfall (if any)
        (, uint256 shortfall) = _accountLiquidity(borrower, type(uint256).max);

        // @custom:error NotLiquidatable Avoid unless borrower's loan is in liquidatable state
        if (shortfall == 0) revert CygnusCollateral__NotLiquidatable();

        // Get price from oracle
        uint256 lpTokenPrice = getLPTokenPrice();

        // Get the equivalent of the repaid amount + liquidation bonus, in the underlying LP
        uint256 seizedLPs = repayAmount.fullMulDiv(liquidationIncentive, lpTokenPrice);

        // Convert the LP amount seized to CygLP shares to seize this amount
        cygLPAmount = _convertToShares(seizedLPs);

        // Transfer the repaid amount + liq. incentive to the liquidator, escapes canRedeem
        _transfer(borrower, liquidator, cygLPAmount);

        // Initialize and check if liquidation fee is set
        uint256 daoFee;

        // Check for protocol fee
        if (liquidationFee > 0) {
            // Get the liquidation fee amount that is kept by the protocol
            daoFee = cygLPAmount.mulWad(liquidationFee);

            // Assign reserves account
            address daoReserves = hangar18.daoReserves();

            // If applicable, seize daoFee from the borrower, escapes can redeem
            _transfer(borrower, daoReserves, daoFee);
        }

        // Total CygLP seized from the borrower
        uint256 totalSeized = cygLPAmount + daoFee;

        /// @custom:event SeizeCygLP
        emit SeizeCygLP(liquidator, borrower, cygLPAmount, daoFee, totalSeized);
    }

    /**
     *  @dev This low level function should be called from a periphery contract only
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(
        address redeemer,
        uint256 assets,
        bytes calldata data
    ) external override nonReentrant update returns (uint256 usdAmount) {
        /// @custom:error CantRedeemZero Avoid redeem no LP
        if (assets <= 0) revert CygnusCollateral__CantRedeemZero();

        // Compute shares of assets redeemed, rounding up
        // Total supply and total assets are both cached (totalAssets = totalBalance)
        uint256 shares = assets.fullMulDivUp(totalSupply(), totalAssets());

        // Withdraw hook to withdraw from the strategy (if any)
        _beforeWithdraw(assets);

        // Optimistically transfer LP amount to redeemer
        underlying.safeTransfer(redeemer, assets);

        // If data exists then pass to router - `usdAmount` return var is helpful when flash redeeming via a router
        // with a staticCall before hand, it has no effect on the function itself. In case of deleveraging
        // (converting LP to USDC), the router would first call this function and flashRedeem the LP, sell the LP for USDC, 
        // repay user loans (if any) and transfer back the equivalent of the LP redeemed in CygLP to this contract. 
        // Doing a static call on a deleverage will give us an estimate of the USDC received 
        if (data.length > 0) usdAmount = ICygnusAltairCall(msg.sender).altairRedeem_u91A(msg.sender, assets, data);

        // CygLP tokens received by this contract
        uint256 cygLPReceived = balanceOf(address(this));

        /// @custom:error InsufficientCygLPReceived Avoid if we have received less CygLP than declared
        if (cygLPReceived < shares) revert CygnusCollateral__InsufficientCygLPReceived();

        // Burn tokens and emit a Transfer event
        // Escapes `canRedeem` since we are burning tokens from this address
        _burn(address(this), cygLPReceived);
    }

    /**
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function sync() external override nonReentrant update {}
}
