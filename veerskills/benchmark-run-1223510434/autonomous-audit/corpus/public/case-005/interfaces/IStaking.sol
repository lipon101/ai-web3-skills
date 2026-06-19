// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaking {
    event Staked(address indexed user, uint256 amount, uint8 tier);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardPerBlockUpdated(uint256 newRate);
    event EmergencyStop(bool stopped);
    event Slashed(address indexed user, uint256 amount, address indexed treasury);

    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claimRewards() external;
    function setRewardPerBlock(uint256 _rewardPerBlock) external;
    function pendingReward(address user) external view returns (uint256);
    function totalStaked() external view returns (uint256);
}
