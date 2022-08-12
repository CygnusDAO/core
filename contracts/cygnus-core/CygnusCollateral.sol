// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateral } from "./interfaces/ICygnusCollateral.sol";
import { CygnusCollateralModel } from "./CygnusCollateralModel.sol";

// Libraries
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusBorrow } from "./interfaces/ICygnusBorrow.sol";
import { ICygnusAltairCall } from "./interfaces/ICygnusAltairCall.sol";
import { ICygnusBorrowTracker } from "./interfaces/ICygnusBorrowTracker.sol";
import { IErc20, Erc20 } from "./Erc20.sol";
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";

/**
 *  @title CygnusCollateral Main Collateral contract handles transfers and seizings of collateral
 */
contract CygnusCollateral is ICygnusCollateral, CygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @custom:library SafeTransferLib Solady`s library for low level handling of Erc20 tokens
     */
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks whether user has enough liquidity and calls safe internal transfer at CygnusTerminal
     *  @notice Overrides Erc20
     */
    function transferInternal(
        address from,
        address to,
        uint256 value
    ) internal override(Erc20) {
        /// @custom:error InsufficientLiquidity Avoid transfer if there's shortfall
        if (!canRedeem(from, value)) {
            revert CygnusCollateral__InsufficientLiquidity({ from: from, to: to, value: value });
        }

        // Safe internal transfer
        super.transferInternal(from, to, value);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateral
     */
    function canRedeem(address borrower, uint256 redeemAmount) public view override returns (bool) {
        // Gas savings
        uint256 cygLPBalance = balances[borrower];

        // Value can't be higher than account balance, return false
        if (redeemAmount > cygLPBalance) {
            return false;
        }

        // Update user's balance.
        uint256 finalBalance = cygLPBalance - redeemAmount;

        // Calculate final balance against the underlying's exchange rate / scale
        uint256 amountCollateral = finalBalance.mul(exchangeRate());

        // Borrow balance, calls BorrowDAITokenA contract
        uint256 amountDAI = ICygnusBorrowTracker(borrowable).getBorrowBalance(borrower);

        // prettier-ignore
        ( /*liquidity*/, uint256 shortfall) = collateralNeededInternal(amountCollateral, amountDAI);

        // Return true if user has no shortfall
        return shortfall == 0;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This function should only be called from `CygnusBorrow` contracts only - No possible reentrancy
     *  @inheritdoc ICygnusCollateral
     */
    function seizeCygLP(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external override returns (uint256 cygLPAmount) {
        /// @custom:error CantLiquidateSelf Avoid liquidating self
        if (_msgSender() == borrower) {
            revert CygnusCollateral__CantLiquidateSelf({ borrower: borrower, liquidator: liquidator });
        }
        /// @custom:error MsgSenderNotCygnusDai Avoid unless msg sender is this shuttle's CygnusBorrow contract
        else if (_msgSender() != borrowable) {
            revert CygnusCollateral__MsgSenderNotCygnusDai({ sender: _msgSender(), borrowable: borrowable });
        }
        /// @custom:erro CantLiquidateZero Avoid liquidating 0 repayAmount
        else if (repayAmount == 0) {
            revert CygnusCollateral__CantLiquidateZero();
        }

        // Get user's liquidity or shortfall
        (uint256 liquidity, uint256 shortfall) = accountLiquidityInternal(borrower, type(uint256).max);

        // @custom:error NotLiquidatable Avoid unless borrower's loan is in liquidatable state
        if (shortfall <= 0) {
            revert CygnusCollateral__NotLiquidatable({ userLiquidity: liquidity, userShortfall: 0 });
        }

        // Get price from oracle
        uint256 lpTokenPrice = getLPTokenPrice();

        // Factor in liquidation incentive and current exchange rate to add/decrease collateral token balance
        cygLPAmount = (repayAmount.div(lpTokenPrice) * liquidationIncentive) / exchangeRate();

        // Decrease borrower's balance of cygnus collateral tokens
        balances[borrower] -= cygLPAmount;

        // Increase liquidator's balance of cygnus collateral tokens
        balances[liquidator] += cygLPAmount;

        // Take into account protocol fee
        uint256 cygnusFee;

        // Check for protocol fee
        if (liquidationFee > 0) {
            // Get the liquidation fee amount that is kept by the protocol
            cygnusFee = cygLPAmount.mul(liquidationFee);

            // Assign reserves account
            address daoReserves = ICygnusFactory(hangar18).daoReserves();

            // update borrower's balance
            balances[borrower] -= cygnusFee;

            // update reserve's balance
            balances[daoReserves] += cygnusFee;
        }

        /// @custom:event Transfer
        emit Transfer(borrower, liquidator, cygLPAmount);
    }

    /**
     *  @dev This low level function should only be called from `Altair` contract only
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(
        address redeemer,
        uint256 redeemAmount,
        bytes calldata data
    ) external override nonReentrant update {
        /// @custom:error CantRedeemZero Avoid redeem unless is positive amount
        if (redeemAmount <= 0) {
            revert CygnusCollateral__CantRedeemZero();
        }
        /// @custom:error BurnAmountInvalid Avoid redeeming more than shuttle's balance
        else if (redeemAmount > totalBalance) {
            revert CygnusCollateral__RedeemAmountInvalid({ redeemAmount: redeemAmount, totalBalance: totalBalance });
        }

        // Withdraw hook to withdraw from the strategy (if any)
        beforeWithdraw(redeemAmount, 0);

        // Optimistically transfer funds
        underlying.safeTransfer(redeemer, redeemAmount);

        // Pass data to router
        if (data.length > 0) {
            ICygnusAltairCall(redeemer).altairRedeem_u91A(_msgSender(), redeemAmount, token0, token1, data);
        }

        // Total balance of CygLP tokens in this contract
        uint256 cygLPTokens = balances[address(this)];

        // Calculate user's redeem (amount * scale / exch)
        uint256 redeemableAmount = redeemAmount.div(exchangeRate());

        /// @custom:error InsufficientRedeemAmount Avoid if there's less tokens than declared
        if (cygLPTokens < redeemableAmount) {
            revert CygnusCollateral__InsufficientRedeemAmount({
                cygLPTokens: cygLPTokens,
                redeemableAmount: redeemableAmount
            });
        }

        // Burn tokens and emit a Transfer event
        burnInternal(address(this), cygLPTokens);
    }
}
