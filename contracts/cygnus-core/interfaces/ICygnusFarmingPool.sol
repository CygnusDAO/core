// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

interface ICygnusFarmingPool {
    function trackBorrow(
        address borrower,
        uint256 borrowBalance,
        uint256 borrowIndex
    ) external;
}
