//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusCollateral.sol
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
import {ICygnusCollateralVoid} from "./ICygnusCollateralVoid.sol";

/**
 *  @title ICygnusCollateral
 *  @notice Interface for the main collateral contract which handles collateral seizes and flash redeems
 */
interface ICygnusCollateral is ICygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the user doesn't have enough liquidity to redeem
     *
     *  @custom:error InsufficientLiquidity
     */
    error CygnusCollateral__InsufficientLiquidity();

    /**
     *  @dev Reverts when the msg.sender of the liquidation is not this contract`s borrowable
     *
     *  @custom:error MsgSenderNotBorrowable
     */
    error CygnusCollateral__MsgSenderNotBorrowable();

    /**
     *  @dev Reverts when the repayAmount in a liquidation is 0
     *
     *  @custom:error CantLiquidateZero
     */
    error CygnusCollateral__CantLiquidateZero();

    /**
     *  @dev Reverts when trying to redeem 0 tokens
     *
     *  @custom:error CantRedeemZero
     */
    error CygnusCollateral__CantRedeemZero();

    /**
     * @dev Reverts when liquidating an account that has no shortfall
     *
     * @custom:error NotLiquidatable
     */
    error CygnusCollateral__NotLiquidatable();

    /**
     *  @dev Reverts when redeeming more than pool's totalBalance
     *
     *  @custom:error RedeemAmountInvalid
     */
    error CygnusCollateral__RedeemAmountInvalid();

    /**
     *  @dev Reverts when redeeming more shares than CygLP in this contract
     *
     *  @custom:error InsufficientRedeemAmount
     */
    error CygnusCollateral__InsufficientCygLPReceived();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when collateral is seized from the borrower and sent to the liquidator
     *
     *  @param liquidator The address of the liquidator
     *  @param borrower The address of the borrower being liquidated
     *  @param cygLPAmount The amount of CygLP seized and sent to the liquidator
     *  @param daoFee The amount of CygLP sent to the DAO Reserves
     *  @param seized The total amount of CygLP seized from the borrower
     */
    event SeizeCygLP(
        address indexed liquidator,
        address indexed borrower,
        uint256 cygLPAmount,
        uint256 daoFee,
        uint256 seized
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Seizes CygLP from borrower and adds it to the liquidator's account.
     *  @notice Not marked as non-reentrant
     *
     *  @dev This should be called from `borrowable` contract, else it reverts
     *
     *  @param liquidator The address repaying the borrow and seizing the collateral
     *  @param borrower The address of the borrower
     *  @param repayAmount The number of collateral tokens to seize
     *
     *  @return cygLPAmount The amount of CygLP seized
     */
    function seizeCygLP(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 cygLPAmount);

    /**
     *  @notice Flash redeems the underlying LP Token
     *
     *  @dev This should be called from `Altair` contract
     *
     *  @param redeemer The address redeeming the tokens (Altair contract)
     *  @param assets The amount of the underlying assets to redeem
     *  @param data Calldata passed from and back to router contract
     *
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(address redeemer, uint256 assets, bytes calldata data) external;

    /**
     *  @notice Force the internal balance of this contract to match underlying's balanceOf
     *
     *  @custom:security non-reentrant only-eoa
     */
    function sync() external;
}
