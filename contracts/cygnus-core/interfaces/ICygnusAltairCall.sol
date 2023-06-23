//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusAltairCall.sol
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

/**
 *  @title ICygnusAltairCall
 *  @notice Simple callee contract for leverage, deleverage and flash liquidations
 */
interface ICygnusAltairCall {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the leverage
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param borrowAmount The amount to leverage
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function altairBorrow_O9E(address sender, uint256 borrowAmount, bytes calldata data) external;

    /**
     *  @notice Function that is called by the CygnusCollateral contract and decodes data to carry out the deleverage
     *  @notice Will only succeed if: Caller is collateral contract & collateral contract was called by router
     *
     *  @param sender Address of the contract that initialized the redeem transaction (address of the router)
     *  @param redeemAmount The amount to deleverage
     *  @param data The encoded byte data passed from the CygnusCollateral contract to the router
     */
    function altairRedeem_u91A(address sender, uint256 redeemAmount, bytes calldata data) external;

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the liquidation
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param cygLPAmount The cygLP Amount seized
     *  @param actualRepayAmount The usd amount the contract must have for the liquidate function to finish
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function altairLiquidate_f2x(
        address sender,
        uint256 cygLPAmount,
        uint256 actualRepayAmount,
        bytes calldata data
    ) external;
}
