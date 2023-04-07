// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

library CygnusDexLib {
    /**
     *  @dev Compute optimal deposit amount (https://blog.alphaventuredao.io/onesideduniswap/)
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     *  @param swapFee The fee charged by this dex for a swap (ie Uniswap = 997/1000 = 0.3%)
     *  @return optimal swap amount of tokenA to tokenB to then hold the same proportion of assets as in pool reserves
     */
    function optimalDepositA(uint256 amountA, uint256 reservesA, uint256 swapFee) internal pure returns (uint256) {
        uint256 _a = 10000 - swapFee;
        // Calculate with dex swap fee
        uint256 a = (10000 + _a) * reservesA;
        uint256 b = amountA * 10000 * reservesA * 4 * _a;
        uint256 c = FixedPointMathLib.sqrt(a * a + b);
        uint256 d = 2 * _a;
        return (c - a) / d;
    }

    /**
     *  @dev Take from UniswapV2Library
     *  @notice Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
     */
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut,
        uint256 swapFee
    ) internal pure returns (uint amountOut) {
        uint amountInWithFee = amountIn * swapFee;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
