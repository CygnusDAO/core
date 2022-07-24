// SPDX-License-Identifier: Unlicensed

import "./PRBMath.sol";
import "./IErc20.sol";

/**
 *  @title VoidHelper
 *  @dev Provides functions for harvesting and reinvesting rewards (if any)
 */
pragma solidity >=0.8.4;

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

    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
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
