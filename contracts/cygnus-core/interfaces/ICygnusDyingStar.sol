// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

interface ICygnusDyingStar {
    function trackBorrow(uint256 shuttle, address borrower, uint256 borrowBalance, uint256 borrowIndex) external;
}
