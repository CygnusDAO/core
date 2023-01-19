// SPDX-License-Identifier: Unlicense
import "./IERC20.sol";

pragma solidity >=0.8.4;

interface IMiniChef {
    function lpToken(uint256) external view returns (address);

    function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt);

    function rewarder(uint256) external view returns (address);

    function deposit(uint256 _pid, uint256 _amount, address _to) external;

    function withdraw(uint256 _pid, uint256 _amount, address _to) external;

    function harvest(uint256 _pid, address _to) external;
}

interface IRewarder {
    function pendingTokens(
        uint256 pid,
        address user,
        uint256 sushiAmount
    ) external view returns (address[] memory, uint256[] memory);
}
