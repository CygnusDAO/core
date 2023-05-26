// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusCollateralVoid} from "./ICygnusCollateralVoid.sol";

/**
 *  @title ICygnusCollateral Interface for the main collateral contract which handles collateral seizes
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
    error CygnusCollateral__InsufficientRedeemAmount();

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
