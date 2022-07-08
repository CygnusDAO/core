// SPDX-License-Identifier: Unlicensed
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
     *  @custom:error PriceTokenBInvalid Emitted when the borrower is the zero address
     */
    error CygnusCollateralModel__BorrowerCantBeAddressZero(address sender, address origin);

    /**
     *  @custom:error BorrowableInvalid Emitted when borrowable is not one of the pool's allowed borrow tokens.
     */
    error CygnusCollateralModel__BorrowableInvalid(address invalidBorrowable, address validBorrowable);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Checks an account's liquidity or shortfall
     *  @param borrower The address of the borrower, reverts if address(0)
     *  @param amountDAI The total amount of DAI the user can borrow
     *  @return liquidity the account liquidity. If none, return 0
     *  @return shortfall the account shortfall. If none, return 0
     */
    function accountLiquidity(address borrower, uint256 amountDAI)
        external
        returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Gets an account's liquidity or shortfall
     *  @param borrower The address of the borrower.
     *  @return liquidity The account's liquidity.
     *  @return shortfall If user has no liquidity, return the shortfall.
     */
    function getAccountLiquidity(address borrower) external returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Calls the oracle to return the price of the underlying LP Token of this shuttle
     *  @return lpTokenPrice The price of 1 LP Token in DAI
     */
    function getLPTokenPrice() external view returns (uint256 lpTokenPrice);

    /**
     *  @notice Whether or not an account can borrow
     *  @param borrower The address of the borrower.
     *  @param borrowableToken The address of the token the user wants to borrow.
     *  @param accountBorrows The amount the user wants to borrow.
     *  @return Whether the account can borrow.
     */
    function canBorrow(
        address borrower,
        address borrowableToken,
        uint256 accountBorrows
    ) external returns (bool);

    /**
     *  @notice Returns the debt ratio of a borrower, denoted by borrowed DAI / collateral price in DAI
     *  @param borrower The address of the borrower
     *  @return borrowersDebtRatio The debt ratio of the borrower, with max being 1 mantissa
     */
    function getDebtRatio(address borrower) external returns (uint256 borrowersDebtRatio);
}
