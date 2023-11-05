//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusCollateralModel.sol
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
 *  @notice There are 2 main functions in the modelto calculate the liquidity of a user:
 *          `getBorrowerPosition` and `getAccountLiquidity`
 *
 *          `getBorrowerPosition` will return all the data related to the borrower's current position, including
 *          amount of CygLP, collateral value in USD, LP price and Health. The health is the percentage of the
 *          borrowed amount divided by the user's collateral (ie. Debt Ratio), Note that this health is scaled
 *          to the current `debtRatio` param. If `health` returns higher than 100% (or 1e18) then the user
 *          has shortfall and can be liquidated. If `health` returns lower than 100% then the user can borrow
 *          more.
 *
 *          The same can be calculated with `getAccountLiquidity`, but instead of returning a percentage will
 *          return the total amount of USD that the borrower can borrow before their position is in shortfall.
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

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Calculate collateral needed for a loan factoring in debt ratio and liq incentive
     *  @param amountCollateral The collateral amount the borrower has deposited (CygLP * exchangeRate)
     *  @param borrowedAmount The total amount of stablecoins the user has borrowed (can be 0)
     */
    function collateralNeededPrivate(uint256 amountCollateral, uint256 borrowedAmount) private view returns (uint256, uint256) {
        // User LP deposited * LP Token price
        // ie. convertToAssets(cygLPBalance) * lpPrice
        uint256 collateralInUsd = amountCollateral.mulWad(getLPTokenPrice());

        // Adjust the collateral by the pool`s debt ratio and liquidation incentives to get the max liquidity
        uint256 maxLiquidity = collateralInUsd.fullMulDiv(debtRatio, liquidationIncentive + liquidationFee);

        // Never underflows
        unchecked {
            // If account has collateral available to borrow against, return liquidity and 0 shortfall
            if (maxLiquidity >= borrowedAmount) return (maxLiquidity - borrowedAmount, 0);
            // else, return 0 liquidity and the account's shortfall, position can be liquidated
            else return (0, borrowedAmount - maxLiquidity);
        }
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Called by CygnusCollateral when a liquidation takes place
     *  @param borrower Address of the borrower
     *  @param borrowBalance Borrowed amount of stablecoins by `borrower`
     *  @return liquidity The user's current LP liquidity priced in USD
     *  @return shortfall The user's current LP shortfall priced in USD (if positive they can be liquidated)
     */
    function _accountLiquidity(address borrower, uint256 borrowBalance) internal view returns (uint256, uint256) {
        // Borrower can never be address zero or Collateral. When doing a `borrow` from the borrowable contract, this function
        // gets called to check for account liquidity. If the borrower passed is either, we revert the tx
        /// @custom:error InvalidBorrower Avoid borrower zero address or this contract
        if (borrower == address(0) || borrower == address(this)) revert CygnusCollateralModel__InvalidBorrower();

        // Check if called externally or from borrowable. If called externally (via `getAccountLiquidity`) then borrowedAmount
        // is always MaxUint256. If called by borrowable ( `borrow` function calls the `canBorrow` function below) then its the
        // account's total borrows (including the new tx borrow amount if any).
        // Simulate accrue as borrowable calls this function with borrower's account borrows and not max uint256
        if (borrowBalance == type(uint256).max) (, borrowBalance) = ICygnusBorrow(twinstar).getBorrowBalance(borrower);

        // Get the CygLP balance of `borrower` and adjust with exchange rate
        uint256 amountCollateral = _convertToAssets(balanceOf(borrower));

        // Calculate user's liquidity or shortfall internally
        return collateralNeededPrivate(amountCollateral, borrowBalance);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getLPTokenPrice() public view override returns (uint256 price) {
        // Get the price of 1 amount of the underlying, denominated in the borrowable's underlying (a stablecoin).
        // It returns the price in the borrowable`s decimals. ie If USDC, price in 6 deicmals, if DAI/BUSD in 18.
        // Note that price returned can be unexpectedly high depending on the liquidity token's assets decimals.
        price = nebula.lpTokenPriceUsd(underlying);

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
        if (redeemAmount > cygLPBalance || redeemAmount == 0) return false;

        // The borrower's final CygLP balance after redeeming `redeemAmount`
        uint256 finalBalance = cygLPBalance - redeemAmount;

        // Calculate the amount of underlying LPs the final balance is worth
        uint256 amountCollateral = _convertToAssets(finalBalance);

        // Get borrower's borrow balance from borrowable contract
        (, uint256 borrowBalance) = ICygnusBorrow(twinstar).getBorrowBalance(borrower);

        // Get the LP price and calculate the needed collateral
        (, uint256 shortfall) = collateralNeededPrivate(amountCollateral, borrowBalance);

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
    function canBorrow(address borrower, uint256 borrowAmount) external view override returns (bool) {
        // Called by CygnusBorrow at the end of the `borrow` function to check if a `borrower` can borrow `borrowAmount`
        (, uint256 shortfall) = _accountLiquidity(borrower, borrowAmount);

        // User has no shortfall and can borrow
        return shortfall == 0;
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getBorrowerPosition(address borrower) external view override returns (uint256 lpBalance, uint256 positionUsd, uint256 health) {
        // The amount of LP tokens that is owned by the borrower's position
        lpBalance = balanceOf(borrower).mulWad(exchangeRate());

        // Borrower's position in USD
        positionUsd = lpBalance.mulWad(getLPTokenPrice());

        // Max user's liquidity (in USD) = The position's USD adjusted by the debt ratio and liquidation incentives
        uint256 maxLiquidity = positionUsd.fullMulDiv(debtRatio, liquidationIncentive + liquidationFee);

        // Get the latest borrow balance (uses borrow indices)
        (, uint256 borrowBalance) = ICygnusBorrow(twinstar).getBorrowBalance(borrower);

        // The position's health is borrowBalance / maxLiquidity, liquidatable at 100% (ie 1e18)
        health = positionUsd == 0 ? 0 : borrowBalance.divWad(maxLiquidity);
    }
}
