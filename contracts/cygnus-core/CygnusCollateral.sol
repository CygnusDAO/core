// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusCollateral} from "./interfaces/ICygnusCollateral.sol";
import {CygnusCollateralVoid} from "./CygnusCollateralVoid.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";
import {ICygnusAltairCall} from "./interfaces/ICygnusAltairCall.sol";

// Overrides
import {ERC20} from "./ERC20.sol";

/**
 *  @title  CygnusCollateral Main Collateral contract handles transfers and seizings of collateral
 *  @author CygnusDAO
 *  @notice This is the main Collateral contract which is used for liquidations and for flash redeeming the
 *          underlying. It also overrides the `burn` internal function, calling the borrowable arm to query
 *          the redeemer's current borrow balance to check if the user can redeem the LP Tokens.
 *
 *          When a user's position gets liquidated, it is initially called by the borrow arm. The liquidator
 *          first repays back stables to the borrowable arm and then calls `liquidate` which then calls `seizeCygLP`
 *          in this contract to seize the amount of CygLP being repaid + the liquidation incentive. There is a
 *          liquidation fee which can be set to go to DAO Reserves taken from the user being liquidated this
 *          fee is set to default as 0.
 *
 *          The last function `flashRedeemAltair` allows users to deleverage their positions. Anyone can flash
 *          redeem the underlying LP Tokens, as long as they are paid back by the end of the function call.
 */
contract CygnusCollateral is ICygnusCollateral, CygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using FixedPointMathLib for uint256;

    /**
     *  @custom:library SafeTransferLib Low level handling of Erc20 tokens
     */
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice ERC20 Overrides
     *  @notice Before burning we check whether the user has sufficient liquidity (no debt) to redeem `burnAmount`
     */
    function burnInternal(address holder, uint256 burnAmount) internal override(ERC20) {
        /// @custom:error InsufficientLiquidity Avoid burning supply if there's shortfall
        if (!canRedeem(holder, burnAmount)) {
            revert CygnusCollateral__InsufficientLiquidity({from: holder, to: address(0), value: burnAmount});
        }

        // Safe internal burn
        super.burnInternal(holder, burnAmount);
    }

    /**
     *  @notice ERC20 Overrides
     *  @notice Before transfering we check whether the user has sufficient liquidity (no debt) to transfer `amount`
     */
    function transferInternal(address sender, address recipient, uint256 amount) internal override(ERC20) {
        /// @custom:error InsufficientLiquidity Avoid transfering CygLP if there's shortfall
        if (!canRedeem(sender, amount)) {
            revert CygnusCollateral__InsufficientLiquidity({from: sender, to: recipient, value: amount});
        }

        // Safe internal burn
        super.transferInternal(sender, recipient, amount);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This function should only be called from this collateral's `borrowable` contracts only
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function seizeCygLP(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external override nonReentrant returns (uint256 cygLPAmount) {
        /// @custom:error MsgSenderNotBorrowable Avoid unless msg sender is this shuttle's CygnusBorrow contract
        if (_msgSender() != borrowable) {
            revert CygnusCollateral__MsgSenderNotBorrowable({sender: _msgSender(), borrowable: borrowable});
        }
        /// @custom:erro CantLiquidateZero Avoid liquidating 0 repayAmount
        else if (repayAmount == 0) {
            revert CygnusCollateral__CantLiquidateZero();
        }

        // Get user's liquidity or shortfall
        (uint256 liquidity, uint256 shortfall) = accountLiquidityInternal(borrower, type(uint256).max);

        // @custom:error NotLiquidatable Avoid unless borrower's loan is in liquidatable state
        if (shortfall <= 0) {
            revert CygnusCollateral__NotLiquidatable({liquidity: liquidity, shortfall: shortfall});
        }

        // Get price from oracle
        uint256 lpTokenPrice = getLPTokenPrice();

        // Factor in liquidation incentive and current exchange rate to add/decrease collateral token balance
        cygLPAmount = (repayAmount.divWad(lpTokenPrice) * liquidationIncentive) / exchangeRate();

        // Decrease borrower's balance of cygnus collateral tokens
        balances[borrower] -= cygLPAmount;

        // Increase liquidator's balance of cygnus collateral tokens
        balances[liquidator] += cygLPAmount;

        // Take into account protocol fee
        uint256 cygnusFee;

        // Check for protocol fee
        if (liquidationFee > 0) {
            // Get the liquidation fee amount that is kept by the protocol
            cygnusFee = cygLPAmount.mulWad(liquidationFee);

            // Assign reserves account
            address daoReserves = IHangar18(hangar18).daoReserves();

            // update borrower's balance
            balances[borrower] -= cygnusFee;

            // update reserve's balance
            balances[daoReserves] += cygnusFee;
        }

        /// @custom:event Transfer
        emit Transfer(borrower, liquidator, cygLPAmount);
    }

    /**
     *  @dev This low level function should only be called from periphery contract only
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(
        address redeemer,
        uint256 assets,
        bytes calldata data
    ) external override nonReentrant update {
        /// @custom:error CantRedeemZero Avoid redeem unless is positive amount
        if (assets <= 0) {
            revert CygnusCollateral__CantRedeemZero();
        }
        /// @custom:error BurnAmountInvalid Avoid redeeming more than shuttle's balance
        else if (assets > totalBalance) {
            revert CygnusCollateral__RedeemAmountInvalid({assets: assets, totalBalance: totalBalance});
        }

        // Withdraw hook to withdraw from the strategy (if any)
        beforeWithdrawInternal(assets);

        // Optimistically transfer funds
        underlying.safeTransfer(redeemer, assets);

        // Pass data to router
        if (data.length > 0) {
            ICygnusAltairCall(redeemer).altairRedeem_u91A(_msgSender(), assets, token0, token1, data);
        }

        // Total balance of CygLP tokens in this contract
        uint256 cygLPTokens = balances[address(this)];


        // Calculate user's redeem (amount * scale / exch)
        uint256 shares = assets.divWad(exchangeRate());

        /// @custom:error InsufficientRedeemAmount Avoid if there's less tokens than declared
        if (cygLPTokens < shares) {
            revert CygnusCollateral__InsufficientRedeemAmount({cygLPTokens: cygLPTokens, shares: shares});
        }

        // Burn tokens and emit a Transfer event
        burnInternal(address(this), cygLPTokens);
    }
}
