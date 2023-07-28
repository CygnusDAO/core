// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

interface ICometRewards {
    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
    }

    struct RewardOwed {
        address token;
        uint owed;
    }

    function claim(address comet, address src, bool shouldAccrue) external;

    function claimTo(address comet, address src, address to, bool shouldAccrue) external;

    function getRewardOwed(address comet, address account) external returns (RewardOwed memory);
}
