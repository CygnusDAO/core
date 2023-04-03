// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.4;

interface IStargateLPStaking {
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    function userInfo(uint256 _poolId, address _userAddress) external view returns (uint256 amount, uint256 rewardDebt);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingStargate(uint256 _pid, address _user) external view returns (uint256);
}
