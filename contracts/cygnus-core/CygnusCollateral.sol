// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateral } from "./interfaces/ICygnusCollateral.sol";
import { CygnusCollateralModel } from "./CygnusCollateralModel.sol";

// Interfaces
import { ICygnusBorrow } from "./interfaces/ICygnusBorrow.sol";
import { ICygnusCallee } from "./interfaces/ICygnusCallee.sol";
import { ICygnusBorrowTracker } from "./interfaces/ICygnusBorrowTracker.sol";
import { IErc20, Erc20 } from "./Erc20.sol";
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";

// Libraries
import { SafeErc20 } from "./libraries/SafeErc20.sol";
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { VoidHelper } from "./libraries/VoidHelper.sol";

/**
 *  @title CygnusCollateral Main Collateral contract handles transfers and seizings of collateral
 */
contract CygnusCollateral is ICygnusCollateral, CygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeErc20 Low level handling of Erc20 tokens (redeemCollateral)
     */
    using SafeErc20 for IErc20;

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

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
        /// @custom:error CygnusCollateral__InsufficientLiquidity Avoid transfer if there's shortfall
        if (!tokensUnlocked(from, value)) {
            revert CygnusCollateral__InsufficientLiquidity({ from: from, to: to, value: value });
        }

        // Safe internal transfer
        super.transferInternal(from, to, value);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateral
     */
    function tokensUnlocked(address from, uint256 value) public override chargeVoid returns (bool) {
        // Gas savings
        uint256 _balance = balanceOf(from);

        // Value can't be higher than account balance, return false
        if (value > _balance) {
            return false;
        }

        // Update user's balance.
        uint256 finalBalance = _balance - value;

        // Calculate final balance against the underlying's exchange rate / scale
        uint256 amountCollateral = finalBalance.mul(exchangeRate());

        // Borrow balance, calls BorrowDAITokenA contract
        uint256 amountDAI = ICygnusBorrowTracker(cygnusDai).getBorrowBalance(from);

        // prettier-ignore
        ( /*liquidity*/, uint256 shortfall) = accountLiquidityInternal(amountCollateral, amountDAI);

        return shortfall == 0;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This function should only be called from `CygnusBorrow` contracts only
     *  @inheritdoc ICygnusCollateral
     */
    function seizeDeneb(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external override chargeVoid returns (uint256 denebAmount) {
        // @custom:error LiquidatingSelf Avoid liquidating self
        if (_msgSender() == borrower) {
            revert CygnusCollateral__LiquidatingSelf(borrower);
        }
        // @custom:error NotBorrowable Avoid unless msg sender is this shuttle's CygnusBorrow contract
        else if (_msgSender() != cygnusDai) {
            revert CygnusCollateral__MsgSenderNotBorrowable({ sender: _msgSender(), borrowable: cygnusDai });
        }

        (uint256 liquidity, uint256 shortfall) = getAccountLiquidity(borrower);

        // @custom:error NotLiquidatable Avoid unless borrower's loan is in liquidatable state
        if (shortfall <= 0) {
            revert CygnusCollateral__NotLiquidatable({ userLiquidity: liquidity, userShortfall: 0 });
        }

        uint256 denebPrice;

        // Get the LP Token price if caller is CygnusBorrow.sol
        if (_msgSender() == cygnusDai) {
            denebPrice = cygnusNebulaOracle.lpTokenPriceDai(underlying);
        }
        // else return
        else {
            return 0;
        }

        // Factor in liquidation incentive and current exchange rate
        denebAmount = (repayAmount.div(denebPrice) * liquidationIncentive) / exchangeRate();

        // Update borrower's balance
        balances[borrower] -= denebAmount;

        // Update liquidator's balance
        balances[liquidator] += denebAmount;

        /// @custom:event SeizeCollateral
        emit SeizeCollateral(borrower, liquidator, denebAmount);

        // Check for protocol fee
        if (liquidationFee > 0) {
            // Get the liquidation fee amount that is kept by the protocol
            uint256 denebFee = denebAmount.mul(liquidationFee);

            // Assign reserves account
            address vegaTokenManager = ICygnusFactory(hangar18).vegaTokenManager();

            // update borrower's balance
            balances[borrower] -= denebFee;

            // update reserve's balance
            balances[vegaTokenManager] += denebFee;

            /// @custom:event SeizeCollateral
            emit SeizeCollateral(borrower, vegaTokenManager, denebAmount);
        }
    }

    /**
     *  @dev This low level function should only be called from `Altair` contract only
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function redeemDeneb(
        address redeemer,
        uint256 redeemAmount,
        bytes calldata data
    ) external override nonReentrant update {
        /// @custom:error ValueExceedsBalance Avoid redeeming more than there is in the pool
        if (redeemAmount > totalBalance) {
            revert CygnusCollateral__ValueExceedsBalance({ redeemValue: redeemAmount, redeemBalance: totalBalance });
        }

        // Optimistically transfer funds
        IErc20(underlying).safeTransfer(redeemer, redeemAmount);

        // Pass to callee
        if (data.length > 0) {
            ICygnusCallee(redeemer).cygnusRedeem(_msgSender(), redeemAmount, data);
        }

        // Total balance of deneb tokens in this contract
        uint256 denebTokens = balanceOf(address(this));

        // Calculate user's redeem (amount * scale / exch)
        uint256 redeemableDeneb = redeemAmount.div(exchangeRate());

        /// @custom:error InsufficientRedeemAmount Avoid if there's less tokens than declared
        if (denebTokens < redeemableDeneb) {
            revert CygnusCollateral__InsufficientRedeemAmount(denebTokens);
        }

        // Burn tokens and emit a Transfer event
        burnInternal(address(this), denebTokens);

        /// @custom:event RedeemCollateral
        emit RedeemCollateral(_msgSender(), redeemer, redeemAmount, denebTokens);
    }
}
