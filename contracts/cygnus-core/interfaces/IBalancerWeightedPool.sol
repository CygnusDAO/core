// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import {IERC20} from "./IERC20.sol";

interface IBalancerWeightedPool {
    // Weights
    function getNormalizedWeights() external view returns (uint256[] memory);

    // Supply
    function totalSupply() external view returns (uint256);

    // invariant
    function getLastInvariant() external view returns (uint256);

    // Last invariant?
    function getLastPostJoinExitInvariant() external view returns (uint256);

    function getPoolId() external view returns (bytes32);

    function getVault() external view returns (address);
}

interface IBalancerVault {
    // Get pool tokens
    function getPoolTokens(
        bytes32 poolId
    ) external view returns (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}
