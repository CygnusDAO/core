// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralModel } from "./interfaces/ICygnusCollateralModel.sol";
import { CygnusCollateralControl } from "./CygnusCollateralControl.sol";

// Libraries
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusBorrow } from "./interfaces/ICygnusBorrow.sol";

/**
 *  @title  CygnusCollateralModel Main contract in Cygnus that calculates a borrower's liquidity or shortfall in
 *          USDC (how much LP Token the user has deposited, and then we use the oracle to return what the LP Token
 *          deposited amount is worth in USDC).
 *  @author CygnusDAO
 *  @notice Theres 2 main functions to calculate the liquidity of a user: `getDebtRatio` and `getAccountLiquidity`
 *          `getDebtRatio` will return the percentage of the borrowed amount divided by the user's collateral,
 *          scaled by 1e18. If `getDebtRatio` returns higher than 100% (or 1e18) then the user has shortfall and
 *          can be liquidated.
 *
 *          The same can be calculated with `getAccountLiquidity`, but instead of returning a percentage will
 *          return the actual amount of the user's liquidity or shortfall denominated in USDC.
 *
 *          The last function `canBorrow` is called by the `borrowable` contract (the borrow arm) to confirm if a
 *          user can borrow or not and can be called by anyone, returning `false` if the account has shortfall,
 *          otherwise will return `true`.
 */
contract CygnusCollateralModel is ICygnusCollateralModel, CygnusCollateralControl {
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
     *  @param amountCollateral The collateral amount the borrower has deposited (CygLP * exchangeRate)
     *  @param borrowedAmount The total amount of USDC the user has borrowed (can be 0)
     *  @return liquidity The account's liquidity in USDC, if any
     *  @return shortfall The account's shortfall in USDC, if any
     */
    function collateralNeededInternal(
        uint256 amountCollateral,
        uint256 borrowedAmount
    ) internal view returns (uint256 liquidity, uint256 shortfall) {
        // Get the price of 1 LP Token from the oracle, denominated in USDC
        uint256 lpTokenPrice = getLPTokenPrice();

        // Collateral Deposited * LP Token price
        uint256 collateralInUsdc = amountCollateral.mul(lpTokenPrice);

        // Adjust to this lending pool's current debt ratio parameter
        uint256 adjustedCollateralInUsdc = collateralInUsdc.mul(debtRatio);

        // Collateral needed for the borrowed amount
        uint256 collateralNeededInUsdc = borrowedAmount.mul(liquidationIncentive + liquidationFee);

        // Never underflows
        unchecked {
            // If account has collateral available to borrow against, return liquidity and 0 shortfall
            if (adjustedCollateralInUsdc >= collateralNeededInUsdc) {
                return (adjustedCollateralInUsdc - collateralNeededInUsdc, 0);
            }
            // else, return 0 liquidity and the account's shortfall
            else {
                return (0, collateralNeededInUsdc - adjustedCollateralInUsdc);
            }
        }
    }

    /**
     *  @notice Called by CygnusCollateral when a liquidation takes place
     *  @param borrower Address of the borrower
     *  @param borrowedAmount Borrowed amount of USDC by `borrower`
     *  @return liquidity If user has more collateral than needed, return liquidity amount and 0 shortfall
     *  @return shortfall If user has less collateral than needed, return 0 liquidity and shortfall amount
     */
    function accountLiquidityInternal(
        address borrower,
        uint256 borrowedAmount
    ) internal view returns (uint256 liquidity, uint256 shortfall) {
        /// @custom:error BorrowerCantBeAddressZero Avoid borrower zero address
        if (borrower == address(0)) {
            // solhint-disable avoid-tx-origin
            revert CygnusCollateralModel__BorrowerCantBeAddressZero({ sender: borrower, origin: tx.origin });
        }

        // User's USDC borrow balance
        if (borrowedAmount == type(uint256).max) {
            borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);
        }

        // Get the CygLP balance of `borrower` and adjust with exchange rate (= how many LP Tokens the amount is worth)
        uint256 amountCollateral = balances[borrower].mul(exchangeRate());

        // Calculate user's liquidity or shortfall internally
        return collateralNeededInternal(amountCollateral, borrowedAmount);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getLPTokenPrice() public view override returns (uint256) {
        // Get the price of 1 amount of the underlying in USDC, adjust oracle price for 6 decimals
        return cygnusNebulaOracle.lpTokenPriceUsdc(underlying) / 1e12;
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function canRedeem(address borrower, uint256 redeemAmount) public view override returns (bool) {
        // Gas savings
        uint256 cygLPBalance = balances[borrower];

        // Value can't be higher than account balance, return false
        if (redeemAmount > cygLPBalance) {
            return false;
        }

        // Update user's balance
        uint256 finalBalance = cygLPBalance - redeemAmount;

        // Calculate final balance against the underlying's exchange rate / scale
        uint256 amountCollateral = finalBalance.mul(exchangeRate());

        // Get borrower's borrow balance from borrowable contract
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // prettier-ignore
        ( /*liquidity*/, uint256 shortfall) = collateralNeededInternal(amountCollateral, borrowedAmount);

        // Return true if user has no shortfall
        return shortfall == 0;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getAccountLiquidity(
        address borrower
    ) external view override returns (uint256 liquidity, uint256 shortfall) {
        // Calculate if `borrower` has liquidity or shortfall
        return accountLiquidityInternal(borrower, type(uint256).max);
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getDebtRatio(address borrower) external view override returns (uint256) {
        // Get the borrower's deposited LP Tokens and adjust with current exchange Rate
        uint256 amountCollateral = balances[borrower].mul(exchangeRate());

        // Multiply LP collateral by LP Token price
        uint256 collateralInUsdc = amountCollateral.mul(getLPTokenPrice());

        // The borrower's USDC debt
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Adjust borrowed admount with liquidation incentive
        uint256 adjustedBorrowedAmount = borrowedAmount.mul(liquidationIncentive + liquidationFee);

        // Account for 0 collateral to avoid divide by 0
        return borrowedAmount == 0 ? 0 : adjustedBorrowedAmount.div(collateralInUsdc).div(debtRatio);
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function canBorrow(
        address borrower,
        address borrowableToken,
        uint256 borrowAmount
    ) external view override returns (bool) {
        /// @custom:error BorrowableInvalid Avoid calculating borrowable amount unless contract is CygnusBorrow
        if (borrowableToken != borrowable) {
            revert CygnusCollateralModel__BorrowableInvalid({
                invalidBorrowable: borrowableToken,
                validBorrowable: borrowable
            });
        }

        // prettier-ignore
        (/* liquidity */, uint256 shortfall) = accountLiquidityInternal(borrower, borrowAmount);

        // Return true if user has no shortfall
        return shortfall == 0;
    }
}
