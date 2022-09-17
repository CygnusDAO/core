// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// dependencies
import { ICygnusCollateralModel } from "./ICygnusCollateralModel.sol";

/**
 *  @title ICygnusCollateral Interface for the main collateral contract which handles collateral seizes
 */
interface ICygnusCollateral is ICygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error InsufficientLiquidity Reverts when the user doesn't have enough liquidity to transfer out
     */
    error CygnusCollateral__InsufficientLiquidity(address from, address to, uint256 value);

    /**
     *  @custom:error LiquiditingSelf Reverts when liquidator address is the borrower address
     */
    error CygnusCollateral__CantLiquidateSelf(address borrower, address liquidator);

    /**
     *  @custom:error MsgSenderNotBorrowable Reverts when the msg.sender of the liquidation is not `borrowable`
     */
    error CygnusCollateral__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @custom:error CantLiquidateZero Reverts when the repayAmount in a liquidation is 0
     */
    error CygnusCollateral__CantLiquidateZero();

    /**
     *  @custom:error NotLiquidatable Reverts when liquidating an account that has no shortfall
     */
    error CygnusCollateral__NotLiquidatable(uint256 userLiquidity, uint256 userShortfall);

    /**
     *  @custom:error CantRedeemZero Reverts when trying to redeem 0 tokens
     */
    error CygnusCollateral__CantRedeemZero();

    /**
     *  @custom:error RedeemAmountInvalid Reverts when redeeming more than pool's totalBalance
     */
    error CygnusCollateral__RedeemAmountInvalid(uint256 redeemAmount, uint256 totalBalance);

    /**
     *  @custom:error InsufficientRedeemAmount Reverts when redeeming more than user balance of redeem Tokens
     */
    error CygnusCollateral__InsufficientRedeemAmount(uint256 cygLPTokens, uint256 redeemableAmount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @param borrower The address of the borrower
     *  @param redeemAmount The amount of CygLP to redeem
     *  @return Whether the `borrower` account can redeem - if user has shortfall, returns false
     */
    function canRedeem(address borrower, uint256 redeemAmount) external returns (bool);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This should be called from `borrowable` contract
     *  @param liquidator The address repaying the borrow and seizing the collateral
     *  @param borrower The address of the borrower
     *  @param repayAmount The number of collateral tokens to seize
     *  @return cygLPAmount The amount of CygLP seized
     */
    function seizeCygLP(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 cygLPAmount);

    /**
     *  @dev This should be called from `Altair` contract
     *  @param redeemer The address redeeming the tokens (Altair contract)
     *  @param redeemAmount The amount of the underlying asset being redeemed
     *  @param data Calldata passed from and back to router contract
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(
        address redeemer,
        uint256 redeemAmount,
        bytes calldata data
    ) external;
}
