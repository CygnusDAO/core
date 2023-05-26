// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

/// Pool contracts on other chains and managed by the Stargate protocol.
interface IStargatePool {
    function amountLPtoLD(uint256 _amountLP) external view returns (uint256);

    function totalLiquidity() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function token() external view returns (address);
}
