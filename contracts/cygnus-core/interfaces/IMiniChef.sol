// SPDX-License-Identifier: Unlicensed
import "./IErc20.sol";

pragma solidity >=0.8.4;

interface IMiniChef {
    function poolInfo(uint256)
        external
        view
        returns (
            address lpToken,
            uint96 allocPoint,
            uint256 accJoePerShare,
            uint256 accJoePerFactorPerShare,
            uint64 lastRewardTimestamp,
            IRewarder rewarderContract,
            uint32 veJoeShareBp,
            uint256 totalFactor,
            uint256 totalLpSupply
        );

    function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt);

    function totalAllocPoint() external view returns (uint256);

    function rewarder(uint256) external view returns (address);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;
}

interface IRewarder {
    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IErc20);
}
