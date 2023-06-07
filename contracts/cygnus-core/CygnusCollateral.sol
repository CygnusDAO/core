// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

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
 *          first repays back stables to the borrowable arm and then calls `liquidate` which then calls
 *         `seizeCygLP` in this contract to seize the amount of CygLP being repaid + the liquidation incentive.
 *          There is a liquidation fee which can be set by the hangar18 admin that goes to the DAO Reserves,
 *          taken directly from the user being liquidated. This fee is set to 0 as default.
 *
 *          The last function `flashRedeemAltair` allows users to deleverage their positions. Anyone can flash
 *          redeem the underlying LP Tokens, as long as they are paid back by the end of the function call.
 */
contract CygnusCollateral is ICygnusCollateral, CygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers.
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice ERC20 Overrides
     *  @notice Before burning we check whether the user has sufficient liquidity (no debt) to redeem `burnAmount`
     */
    function _beforeTokenTransfer(address from, address, uint256 amount) internal view override(ERC20) {
        // Escape in case of flash redeem
        if (from == address(this)) return;

        /// @custom:error InsufficientLiquidity Avoid burning supply if there's shortfall
        if (!canRedeem(from, amount)) revert CygnusCollateral__InsufficientLiquidity();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This function should only be called from this collateral's `borrowable` contracts only
     *  @notice Not marked as non-reentrant since only the borrowable may call it through the non-reentrant `liquidate()`
     *  @inheritdoc ICygnusCollateral
     */
    function seizeCygLP(address liquidator, address borrower, uint256 repayAmount) external override returns (uint256 cygLPAmount) {
        /// @custom:error MsgSenderNotBorrowable Avoid unless msg sender is this shuttle's CygnusBorrow contract
        if (msg.sender != borrowable) {
            revert CygnusCollateral__MsgSenderNotBorrowable();
        }
        /// @custom:erro CantLiquidateZero Avoid liquidating 0 repayAmount
        else if (repayAmount == 0) {
            revert CygnusCollateral__CantLiquidateZero();
        }

        // Get user's shortfall (if any)
        // prettier-ignore
        ( /* liquidity */ , uint256 shortfall) = _accountLiquidity(borrower, type(uint256).max);

        // @custom:error NotLiquidatable Avoid unless borrower's loan is in liquidatable state
        if (shortfall <= 0) revert CygnusCollateral__NotLiquidatable();

        // Get price from oracle
        uint256 lpTokenPrice = getLPTokenPrice();

        // Factor in liquidation incentive and current exchange rate to add/decrease collateral token balance
        cygLPAmount = (repayAmount.divWad(lpTokenPrice) * liquidationIncentive) / exchangeRate();

        // Transfer the repaid amount + liq. incentive to the liquidator
        // Use the transfer at erc20 bypassing `canRedeem`
        _transfer(borrower, liquidator, cygLPAmount);

        // Initialize and check if liquidation fee is set
        uint256 daoFee;

        // Check for protocol fee
        if (liquidationFee > 0) {
            // Get the liquidation fee amount that is kept by the protocol
            daoFee = cygLPAmount.mulWad(liquidationFee);

            // Assign reserves account
            address daoReserves = hangar18.daoReserves();

            // If applicable, seize daoFee from the borrower
            // Use the transfer at erc20 bypassing `canRedeem`
            _transfer(borrower, daoReserves, daoFee);
        }

        // Total CygLP seized from the borrower
        uint256 totalSeized = cygLPAmount + daoFee;

        /// @custom:event SeizeCygLP
        emit SeizeCygLP(liquidator, borrower, cygLPAmount, daoFee, totalSeized);
    }

    /**
     *  @dev This low level function should only be called from periphery contract only
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(address redeemer, uint256 assets, bytes calldata data) external override nonReentrant update {
        /// @custom:error CantRedeemZero Avoid redeem unless is positive amount
        if (assets <= 0) revert CygnusCollateral__CantRedeemZero();

        // Withdraw hook to withdraw from the strategy (if any)
        _beforeWithdraw(assets);

        // Optimistically transfer funds
        underlying.safeTransfer(redeemer, assets);

        // Pass data to router
        if (data.length > 0) {
            ICygnusAltairCall(msg.sender).altairRedeem_u91A(msg.sender, assets, data);
        }

        // CygLP tokens received by thsi contract
        uint256 cygLPTokens = balanceOf(address(this));

        // Calculate the equivalent of the flash-redeemed assets in shares
        uint256 shares = assets.divWad(exchangeRate());

        /// @custom:error InsufficientRedeemAmount Avoid if we have received less CygLP than declared
        if (cygLPTokens < shares) revert CygnusCollateral__InsufficientCygLPReceived();

        // Burn tokens and emit a Transfer event
        // Use the burn at ERC20 since we don't have to check for `canRedeem`
        _burn(address(this), cygLPTokens);
    }

    /**
     *  @inheritdoc ICygnusCollateral
     *  @custom:security non-reentrant
     */
    function sync() external override nonReentrant update {}
}
