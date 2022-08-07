// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

import "./PRBMath.sol";
import "./IErc20.sol";

/**
 *  @title VoidHelper
 *  @dev Provides functions for harvesting and reinvesting rewards (if any)
 */
library VoidHelper {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @dev Compute optimal deposit amount helper
    function optimalDepositA(
        uint256 amountA,
        uint256 reservesA,
        uint256 _swapFeeFactor
    ) internal pure returns (uint256) {
        uint256 a = (1000 + _swapFeeFactor) * reservesA;

        uint256 b = amountA * 1000 * reservesA * 4 * _swapFeeFactor;

        uint256 c = PRBMath.sqrt(a * a + b);

        uint256 d = 2 * _swapFeeFactor;

        return (c - a) / d;
    }

    // From: https://github.com/Vectorized/solady/tree/main/src/utils
    function safeApprove(
        address token,
        address to,
        uint256 amount
    ) internal {
        assembly {
            // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0x00, 0x095ea7b3)
            mstore(0x20, to) // Append the "to" argument.
            mstore(0x40, amount) // Append the "amount" argument.

            if iszero(
                and(
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(eq(mload(0x00), 1), iszero(returndatasize())),
                    // We use 0x44 because that's the total length of our calldata (0x04 + 0x20 * 2)
                    // Counterintuitively, this call() must be positioned after the or() in the
                    // surrounding and() because and() evaluates its arguments from right to left.
                    call(gas(), token, 0, 0x1c, 0x44, 0x00, 0x20)
                )
            ) {
                // Store the function selector of `ApproveFailed()`.
                mstore(0x00, 0x3e3f8f73)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            mstore(0x40, memPointer) // Restore the memPointer.
        }
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return This contract's balance
     */
    function contractBalanceOf(address token) internal view returns (uint256) {
        return IErc20(token).balanceOf(address(this));
    }

    /**
     *  @notice Grants allowance to the dex' router to handle our rewards
     *  @param token The address of the token we are approving
     *  @param amount The amount to approve
     */
    function approveDexRouter(
        address token,
        address router,
        uint256 amount
    ) internal {
        if (IErc20(token).allowance(address(this), router) >= amount) {
            return;
        } else {
            safeApprove(token, router, type(uint256).max);
        }
    }
}
