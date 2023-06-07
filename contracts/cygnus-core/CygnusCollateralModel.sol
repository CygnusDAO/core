// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusCollateralModel} from "./interfaces/ICygnusCollateralModel.sol";
import {CygnusCollateralControl} from "./CygnusCollateralControl.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";

/**
 *  @title  CygnusCollateralModel Main contract in Cygnus that calculates a borrower's liquidity or shortfall in
 *          borrowable`s underlying (stablecoins). All functions are marked as view to be queried by borrowers
 *          to check their positions
 *  @author CygnusDAO
 *  @notice Theres 2 main functions to calculate the liquidity of a user: `getDebtRatio` and `getAccountLiquidity`
 *
 *          `getDebtRatio` will return the percentage of the borrowed amount divided by the user's collateral,
 *          scaled to current `debtRatio`. If `getDebtRatio` returns higher than 100% (or 1e18) then the user
 *          has shortfall and can be liquidated. Else they have enough LPs to borrow more.
 *
 *          The same can be calculated with `getAccountLiquidity`, but instead of returning a percentage will
 *          return the actual amount of the user's liquidity or shortfall denominated in the borrowable's
 *          underlying (a stablecoin)
 *
 *          The last function `canBorrow` is called by the `borrowable` contract during borrows to confirm if a
 *          user can borrow or not and can be called by anyone, returning `false` if the account has shortfall,
 *          otherwise will return `true`.
 */
contract CygnusCollateralModel is ICygnusCollateralModel, CygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Calculate collateral needed for a loan factoring in debt ratio and liq incentive
     *  @param amountCollateral The collateral amount the borrower has deposited (CygLP * exchangeRate)
     *  @param borrowedAmount The total amount of stablecoins the user has borrowed (can be 0)
     */
    function _collateralNeeded(uint256 amountCollateral, uint256 borrowedAmount) internal view returns (uint256, uint256) {
        // Collateral Deposited * LP Token price
        uint256 collateralInUsd = amountCollateral.mulWad(getLPTokenPrice());

        // Adjust to this lending pool's current debt ratio parameter
        uint256 adjustedCollateralInUsd = collateralInUsd.mulWad(debtRatio);

        // If borrows is 0 then return collateral by liq params - Max liquidity
        if (borrowedAmount == 0) return (adjustedCollateralInUsd.divWad(liquidationIncentive + liquidationFee), 0);

        // Adjust borrowed admount with liquidation incentive, rounding up
        uint256 collateralNeededInUsd = borrowedAmount.mulWadUp(liquidationIncentive + liquidationFee);

        // Never underflows
        unchecked {
            // If account has collateral available to borrow against, return liquidity and 0 shortfall
            if (adjustedCollateralInUsd >= collateralNeededInUsd) {
                return (adjustedCollateralInUsd - collateralNeededInUsd, 0);
            }
            // else, return 0 liquidity and the account's shortfall
            else {
                return (0, collateralNeededInUsd - adjustedCollateralInUsd);
            }
        }
    }

    /**
     *  @notice Called by CygnusCollateral when a liquidation takes place
     *  @param borrower Address of the borrower
     *  @param borrowedAmount Borrowed amount of stablecoins by `borrower`
     *  @return liquidity The user's current LP liquidity priced in USD
     *  @return shortfall The user's current LP shortfall priced in USD (if positive they can be liquidated)
     */
    function _accountLiquidity(address borrower, uint256 borrowedAmount) internal view returns (uint256, uint256) {
        /// @custom:error BorrowerCantBeAddressZero Avoid borrower zero address
        if (borrower == address(0)) {
            revert CygnusCollateralModel__BorrowerCantBeAddressZero();
        }
        /// @custom:error BorrowerCantBeCollateral Avoid borrower collateral
        else if (borrower == address(this)) {
            revert CygnusCollateralModel__BorrowerCantBeCollateral();
        }

        // Check if called externally or borrowable. If called externally then borrowedAmount is always MaxUint256
        if (borrowedAmount == type(uint256).max) borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Get the CygLP balance of `borrower` and adjust with exchange rate
        uint256 amountCollateral = balanceOf(borrower).mulWad(exchangeRate());

        // Calculate user's liquidity or shortfall internally
        return _collateralNeeded(amountCollateral, borrowedAmount);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getLPTokenPrice() public view override returns (uint256 price) {
        // Get the price of 1 amount of the underlying, denominated in the borrowable's underlying (a stablecoin).
        // It returns the price in the borrowable`s decimals. ie If USDC, price in 6 deicmals, if DAI/BUSD in 18.
        // Note that price returned can be unexpectedly high depending on the liquidity token's assets decimals.
        price = cygnusNebulaOracle.lpTokenPriceUsd(underlying);

        // The oracle is already initialized or else the deployment of the lending pool would have failed.
        // We check for invalid price in case something goes wrong with the oracle's price feeds, reverting
        // any borrow or liquidation.
        /// @custom:error PriceCantBeZero Avoid invalid price from oracle
        if (price == 0) revert CygnusCollateralModel__PriceCantBeZero();
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function canRedeem(address borrower, uint256 redeemAmount) public view override returns (bool) {
        // Gas savings
        uint256 cygLPBalance = balanceOf(borrower);

        // Redeem amount can't be higher than account balance, return false
        if (redeemAmount > cygLPBalance) return false;

        // The borrower's final CygLP balance after redeeming `redeemAmount`
        uint256 finalBalance = cygLPBalance - redeemAmount;

        // Calculate the amount of underlying LPs the final balance is worth
        uint256 amountCollateral = finalBalance.mulWad(exchangeRate());

        // Get borrower's borrow balance from borrowable contract
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Get the LP price and calculate the needed collateral
        // prettier-ignore
        ( /*liquidity*/ , uint256 shortfall) = _collateralNeeded(amountCollateral, borrowedAmount);

        // If user has no shortfall after redeeming return true
        return shortfall == 0;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getAccountLiquidity(address borrower) external view override returns (uint256 liquidity, uint256 shortfall) {
        // Calculate if `borrower` has liquidity or shortfall
        return _accountLiquidity(borrower, type(uint256).max);
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getDebtRatio(address borrower) external view override returns (uint256) {
        // Get the borrower's deposited LP Tokens and adjust with current exchange Rate
        uint256 amountCollateral = balanceOf(borrower).mulWad(exchangeRate());

        // Multiply LP collateral by LP Token price
        uint256 collateralInUsd = amountCollateral.mulWad(getLPTokenPrice());

        // The borrower's stablecoin debt
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Adjust borrowed admount with liquidation incentive, rounding up
        uint256 collateralNeededInUsd = borrowedAmount.mulWadUp(liquidationIncentive + liquidationFee);

        // Prefer to do borrowedAmount / (collateral * debtRatio) instead of dividing by debtRatio for better precision
        return collateralInUsd == 0 ? 0 : collateralNeededInUsd.divWad(collateralInUsd.mulWad(debtRatio));
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function canBorrow(address borrower, uint256 borrowAmount) external view override returns (bool) {
        // prettier-ignore
        ( /* liquidity */ , uint256 shortfall) = _accountLiquidity(borrower, borrowAmount);

        // User has no shortfall and can borrow
        return shortfall == 0;
    }
}
