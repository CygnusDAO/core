// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralVoid } from "./ICygnusCollateralVoid.sol";

/**
 *  @title ICygnusCollateralModel The interface for querying any borrower's positions and find liquidity/shortfalls
 */
interface ICygnusCollateralModel is ICygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error PriceTokenBInvalid Reverts when the borrower is the zero address
     */
    error CygnusCollateralModel__BorrowerCantBeAddressZero(address sender, address origin);

    /**
     *  @custom:error BorrowableInvalid Reverts when borrowable is not this collateral`s borrowable contract
     */
    error CygnusCollateralModel__BorrowableInvalid(address invalidBorrowable, address validBorrowable);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Gets an account's liquidity or shortfall
     *  @param borrower The address of the borrower
     *  @return liquidity The account's liquidity in USDC
     *  @return shortfall If user has no liquidity, return the shortfall in USDC
     */
    function getAccountLiquidity(address borrower) external view returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Calls the oracle to return the price of the underlying LP Token of this shuttle
     *  @return lpTokenPrice The price of 1 LP Token in USDC
     */
    function getLPTokenPrice() external view returns (uint256 lpTokenPrice);

    /**
     *  @notice Returns the debt ratio of a borrower, denoted by borrowed USDC / total collateral price in USDC
     *  @param borrower The address of the borrower
     *  @return borrowersDebtRatio The debt ratio of the borrower, with max being 1e18
     */
    function getDebtRatio(address borrower) external view returns (uint256 borrowersDebtRatio);

    /**
     *  @param borrower The address of the borrower
     *  @param borrowableToken The address of the borrowable contract the `borrower` wants to borrow from
     *  @param borrowAmount The amount the user wants to borrow
     *  @return Whether the account can borrow
     */
    function canBorrow(
        address borrower,
        address borrowableToken,
        uint256 borrowAmount
    ) external view returns (bool);

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @param borrower The address of the borrower
     *  @param redeemAmount The amount of CygLP to redeem
     *  @return Whether the `borrower` account can redeem - if user has shortfall, returns false
     */
    function canRedeem(address borrower, uint256 redeemAmount) external view returns (bool);
}
