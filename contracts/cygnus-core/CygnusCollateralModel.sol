// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralModel } from "./interfaces/ICygnusCollateralModel.sol";
import { CygnusCollateralVoid } from "./CygnusCollateralVoid.sol";

// Libraries
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { IDexPair } from "./interfaces/IDexPair.sol";
import { ICygnusBorrowTracker } from "./interfaces/ICygnusBorrowTracker.sol";

/**
 *  @title CygnusCollateralModel Uses oracle to get price of LP Token and calculates collateral needed for a loan
 *  @author CygnusDAO
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
     *  @return liquidity The account's liquidity, if any
     *  @return shortfall The account's shortfall, if any
     */
    function accountLiquidityInternal(uint256 amountCollateral, uint256 borrowedAmount)
        internal
        view
        returns (uint256 liquidity, uint256 shortfall)
    {
        // Get the price of 1 LP Token from the oracle, denominated in DAI
        uint256 lpTokenPrice = getLPTokenPrice();

        // Collateral in DAI
        uint256 totalCollateralInDai = amountCollateral.mul(lpTokenPrice);

        // Collateral * Debt Ratio(80%)
        uint256 adjustedCollateral = totalCollateralInDai.mul(debtRatio);

        // Collateral Needed
        uint256 collateralNeededInDai = borrowedAmount.mul(liquidationIncentive);

        // If account has collateral available to borrow against, return liquidity and 0 shortfall
        if (adjustedCollateral >= collateralNeededInDai) {
            return (adjustedCollateral - collateralNeededInDai, 0);
        }
        // else, return 0 liquidity and the account's shortfall
        else {
            return (0, collateralNeededInDai - adjustedCollateral);
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getLPTokenPrice() public view override returns (uint256 lpTokenPrice) {
        // Get the price of 1 LP Token in DAI
        lpTokenPrice = cygnusNebulaOracle.lpTokenPriceDai(underlying);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function accountLiquidity(address borrower, uint256 borrowedAmount)
        public
        view
        override
        returns (uint256 liquidity, uint256 shortfall)
    {
        /// @custom:error Avoid borrower zero address
        if (borrower == address(0)) {
            revert CygnusCollateralModel__BorrowerCantBeAddressZero(borrower);
        }

        // User's Token A borrow balance
        if (borrowedAmount == type(uint256).max) {
            borrowedAmount = ICygnusBorrowTracker(cygnusDai).getBorrowBalance(borrower);
        }

        // (balance of borrower * present exchange rate) / scale
        uint256 amountCollateral = balanceOf(borrower).mul(exchangeRate());

        // Calculate user's liquidity or shortfall internally
        return accountLiquidityInternal(amountCollateral, borrowedAmount);
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getAccountLiquidity(address borrower) public view override returns (uint256 liquidity, uint256 shortfall) {
        // Calculate liquidity or shortfall
        return accountLiquidity(borrower, type(uint256).max);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function canBorrow(
        address borrower,
        address borrowableToken,
        uint256 accountBorrows
    ) external override chargeVoid returns (bool) {
        // Gas savings
        address _borrowDAITokenA = cygnusDai;

        /// @custom:error BorrowableInvalid Avoid calculating borrowable amount unless contract is CygnusBorrow
        if (borrowableToken != cygnusDai) {
            revert CygnusCollateralModel__BorrowableInvalid(borrowableToken);
        }

        // Amount of borrowable token A
        uint256 amountTokenA = borrowableToken == _borrowDAITokenA ? accountBorrows : type(uint256).max;

        // prettier-ignore
        (/* liquidity */, uint256 shortfall) = accountLiquidity(borrower, amountTokenA);

        return shortfall == 0;
    }

    /**
     *  @inheritdoc ICygnusCollateralModel
     */
    function getDebtRatio(address borrower) external view override returns (uint256 borrowersDebtRatio) {
        // Get the borrower's deposited collateral
        uint256 amountCollateral = balanceOf(borrower).mul(exchangeRate());

        // Multiply LP collateral by LP Token price
        uint256 collateralInDai = amountCollateral.mul(getLPTokenPrice());

        // The borrower's DAI debt
        uint256 borrowedAmount = ICygnusBorrowTracker(cygnusDai).getBorrowBalance(borrower);

        // Adjust borrowed admount with liquidation incentive
        uint256 adjustedBorrowedAmount = borrowedAmount.mul(liquidationIncentive);

        // borrowed funds in DAI / collateral in DAI
        borrowersDebtRatio = collateralInDai == 0 ? 0 : adjustedBorrowedAmount.div(collateralInDai);
    }
}
