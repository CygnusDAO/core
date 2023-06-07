// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

interface IVeloGauge {
    function getReward(address, address[] memory) external;

    function balanceOf(address) external view returns (uint256);

    function deposit(uint256, uint256) external;

    function withdraw(uint256) external;

    function earned(address, address) external view returns (uint256);

    function rewardsListLength() external view returns (uint256);

    function rewards(uint256) external view returns (address);
}
