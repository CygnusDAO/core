// SPDX-License-Identifier: Unlicensed

import "./PRBMath.sol";

/**
 *  @title CygnusChefHelper
 *  @dev Provides functions for harvesting and reinvesting rewards (if any)
 */
pragma solidity >=0.8.4;

library ChefHelper {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice The address of Wrapped AVAX
     */
    address internal constant wAvax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

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
}
