// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.4;

interface ICygnusCallee {
    function cygnusBorrow(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external;

    function cygnusRedeem(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external;
}
