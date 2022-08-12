// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralModel } from "./interfaces/ICygnusCollateralModel.sol";
import { CygnusCollateralVoid } from "./CygnusCollateralVoid.sol";

// Libraries
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusBorrowTracker } from "./interfaces/ICygnusBorrowTracker.sol";

/**
 *  @title  CygnusCollateralModel Main contract in Cygnus that calculates a borrower's liquidity or shortfall
 *          in DAI (how much LP Token the user has deposited, and then we use the oracle to return what the LP
 *          Token deposited amount is worth in DAI)
 *  @author CygnusDAO
 *  @notice Theres 2 main functions to calculate the liquidity of a user: `getDebtRatio` and `getAccountLiquidity`
 *          `getDebtRatio` will return the percentage of the loan divided by the user's collateral, scaled by 1e18.
 *          If `getDebtRatio` returns higher than the collateral contract's max `debtRatio` then the user has shortfall
 *          and can be liquidated.
 *
 *          The same can be calculated but instead of returning a percentage will return the actual amount of the user's
 *          liquidity or shortfall but denominated in DAI, by calling `getAccountLiquidity`
 *          The last function `canBorrow` is called by the `borrowable` contract (the borrow arm) to confirm if a user
 *          can borrow or not.
 */
contract CygnusCollateralModel is ICygnusCollateralModel, CygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 For uint256 fixed point math, also imports the main library `PRBMath`.
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Calculate collateral needed for a loan factoring in debt ratio and liq incentive
     *  @param amountCollateral The collateral amount that is required for a loan
     *  @param borrowedAmount The LP Token denominated in DAI
     *  @return liquidity The account's liquidity in DAI, if any
     *  @return shortfall The account's shortfall in DAI, if any
     */
    function collateralNeededInternal(uint256 amountCollateral, uint256 borrowedAmount)
        internal
        view
        returns (uint256 liquidity, uint256 shortfall)
    {
        // Get the price of 1 LP Token from the oracle, denominated in DAI
        uint256 lpTokenPrice = getLPTokenPrice();

        // Collateral Deposited * LP Token price
        uint256 collateralInDai = amountCollateral.mul(lpTokenPrice);

        // Adjust to max debt ratio for this shuttle
        uint256 adjustedCollateralInDai = collateralInDai.mul(debtRatio);

        // Collateral needed for the borrowed amount
        uint256 collateralNeededInDai = borrowedAmount.mul(liquidationIncentive + liquidationFee);

        // Never underflows
        unchecked {
            // If account has collateral available to borrow against, return liquidity and 0 shortfall
            if (adjustedCollateralInDai >= collateralNeededInDai) {
                return (adjustedCollateralInDai - collateralNeededInDai, 0);
            }
            // else, return 0 liquidity and the account's shortfall
            else {
                return (0, collateralNeededInDai - adjustedCollateralInDai);
            }
        }
    }

    /**
     *  @param borrower Address of the borrower
     *  @param borrowedAmount Borrowed amount of DAI by `borrower`
     *  @return liquidity If user has more collateral than needed, return liquidity amount and 0 shortfall
     *  @return shortfall If user has less collateral than needed, return 0 liquidity and shortfall amount
     */
    function accountLiquidityInternal(address borrower, uint256 borrowedAmount)
        internal
        view
        returns (uint256 liquidity, uint256 shortfall)
    {
        /// @custom:error BorrowerCantBeAddressZero Avoid borrower zero address
        if (borrower == address(0)) {
            // solhint-disable-next-line
            revert CygnusCollateralModel__BorrowerCantBeAddressZero({ sender: borrower, origin: tx.origin });
        }

        // User's Token A borrow balance
        if (borrowedAmount == type(uint256).max) {
            borrowedAmount = ICygnusBorrowTracker(borrowable).getBorrowBalance(borrower);
        }

        // (balance of borrower * present exchange rate) / scale
        uint256 amountCollateral = balances[borrower].mul(exchangeRate());

        // Calculate user's liquidity or shortfall internally
        return collateralNeededInternal(amountCollateral, borrowedAmount);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getLPTokenPrice() public view override returns (uint256) {
        // Get the price of 1 amount of the underlying in DAI
        return cygnusNebulaOracle.lpTokenPriceDai(underlying);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getAccountLiquidity(address borrower)
        external
        view
        override
        returns (uint256 liquidity, uint256 shortfall)
    {
        // Calculate if `borrower` has liquidity or shortfall
        return accountLiquidityInternal(borrower, type(uint256).max);
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getDebtRatio(address borrower) external view override returns (uint256) {
        // Get the borrower's deposited collateral
        uint256 amountCollateral = balances[borrower].mul(exchangeRate());

        // Multiply LP collateral by LP Token price
        uint256 collateralInDai = amountCollateral.mul(getLPTokenPrice());

        // The borrower's DAI debt
        uint256 borrowedAmount = ICygnusBorrowTracker(borrowable).getBorrowBalance(borrower);

        // Adjust borrowed admount with liquidation incentive
        uint256 adjustedBorrowedAmount = borrowedAmount.mul(liquidationIncentive + liquidationFee);

        // Account for 0 collateral to avoid divide by 0
        return collateralInDai == 0 ? 0 : adjustedBorrowedAmount.div(collateralInDai).div(debtRatio);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function canBorrow_J2u(
        address borrower,
        address borrowableToken,
        uint256 accountBorrows
    ) external view override returns (bool) {
        /// @custom:error BorrowableInvalid Avoid calculating borrowable amount unless contract is CygnusBorrow
        if (borrowableToken != borrowable) {
            revert CygnusCollateralModel__BorrowableInvalid({
                invalidBorrowable: borrowableToken,
                validBorrowable: borrowable
            });
        }

        // prettier-ignore
        (/* liquidity */, uint256 shortfall) = accountLiquidityInternal(borrower, accountBorrows);

        return shortfall == 0;
    }
}
