// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusCollateralControl} from "./ICygnusCollateralControl.sol";

/**
 *  @title ICygnusCollateralModel The interface for querying any borrower's positions and find liquidity/shortfalls
 */
interface ICygnusCollateralModel is ICygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the borrower is the zero address
     *
     *  @param sender The original sender of the transaction.
     *  @param origin The contract address that initiated the transaction.
     *
     *  @custom:error PriceTokenBInvalid
     */
    error CygnusCollateralModel__BorrowerCantBeAddressZero(address sender, address origin);

    /**
     *  @dev Reverts when the price returned from the oracle is 0
     *
     *  @custom:error PriceCantBeZero
     */
    error CygnusCollateralModel__PriceCantBeZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Checks if the given user is able to redeem the specified amount of LP tokens.
     *
     *  @param borrower The address of the user to check.
     *  @param redeemAmount The amount of LP tokens to be redeemed.
     *  @return True if the user can redeem, false otherwise.
     *
     */
    function canRedeem(address borrower, uint256 redeemAmount) external view returns (bool);

    /**
     *  @notice Get the price of 1 amount of the underlying in stablecoins. Note: It returns the price in the borrowable`s
     *          decimals. ie If USDC, returns price in 6 deicmals, if DAI/BUSD in 18
     *  @notice Calls the oracle to return the price of the underlying LP Token of this shuttle
     *
     *  @return lpTokenPrice The price of 1 LP Token in USDC
     */
    function getLPTokenPrice() external view returns (uint256);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Gets an account's liquidity or shortfall
     *
     *  @param borrower The address of the borrower
     *  @return liquidity The account's liquidity in USDC
     *  @return shortfall If user has no liquidity, return the shortfall in USDC
     */
    function getAccountLiquidity(address borrower) external view returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Calculates the ratio of the amount of stablecoin the borrower has borrowed to collateral price, adjusted with
     *          liquidation incentive and fee,
     *
     *  @param borrower Address of the borrower
     *  @return The debt ratio of the borrower to the value of the borrower's deposited LP tokens
     *          adjusted by current exchange rate and LP Token price.
     */
    function getDebtRatio(address borrower) external view returns (uint256);

    /**
     *  @notice Check if a borrower can borrow a specified amount of an asset from CygnusBorrow.
     *  @dev Throws a custom error message if the borrowableToken is invalid.
     *  @dev Calls the internal accountLiquidityInternal function to calculate the borrower's liquidity and shortfall.
     *
     *  @param borrower The address of the borrower to check.
     *  @param borrowAmount The amount the borrower wishes to borrow.
     *  @return A boolean indicating whether the borrower can borrow the specified amount.
     */
    function canBorrow(address borrower, uint256 borrowAmount) external view returns (bool);
}
