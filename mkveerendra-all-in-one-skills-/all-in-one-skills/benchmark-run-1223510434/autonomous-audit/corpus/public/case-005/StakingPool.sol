// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract StakingPool {
    IERC20 public token;
    address public owner;
    bool public emergencyStopped;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public pendingRewards;
    mapping(address => uint256) public lastUpdateBlock;
    mapping(address => uint8) public lockupTier;

    uint256 public rewardPerBlock = 1e18;
    uint256 public totalStaked;
    address public treasury;

    uint256[3] public lockupDuration = [0, 7200, 28800];
    uint256[3] public lockupMultiplierBps = [10000, 12500, 15000];
    mapping(address => uint256) public lockupStart;

    event Staked(address indexed user, uint256 amount, uint8 tier);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardPerBlockUpdated(uint256 newRate);
    event EmergencyStop(bool stopped);
    event Slashed(address indexed user, uint256 amount, address indexed treasury_);

    error NotOwner();
    error EmergencyActive();
    error InsufficientStake();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier notStopped() {
        if (emergencyStopped) revert EmergencyActive();
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
        treasury = msg.sender;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    function setEmergencyStop(bool stop) external onlyOwner {
        emergencyStopped = stop;
        emit EmergencyStop(stop);
    }

    function stake(uint256 amount) external notStopped {
        _updateRewards(msg.sender);
        token.transferFrom(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        lockupStart[msg.sender] = block.number;
        emit Staked(msg.sender, amount, lockupTier[msg.sender]);
    }

    function stakeWithTier(uint256 amount, uint8 tier) external notStopped {
        require(tier <= 2, "invalid tier");
        _updateRewards(msg.sender);
        token.transferFrom(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        lockupTier[msg.sender] = tier;
        lockupStart[msg.sender] = block.number;
        emit Staked(msg.sender, amount, tier);
    }

    function _updateRewards(address user) internal {
        if (lastUpdateBlock[user] == 0) {
            lastUpdateBlock[user] = block.number;
            return;
        }
        uint256 blocks = block.number - lastUpdateBlock[user];
        uint256 userShare = (stakedBalance[user] * 1e18) / totalStaked;
        uint256 reward = (blocks * rewardPerBlock * userShare) / 1e18;
        pendingRewards[user] += reward;
        lastUpdateBlock[user] = block.number;
    }

    function claimRewards() external notStopped {
        _updateRewards(msg.sender);
        uint256 reward = pendingRewards[msg.sender];
        pendingRewards[msg.sender] = 0;
        uint8 tier = lockupTier[msg.sender];
        uint256 boostedReward = (reward * lockupMultiplierBps[tier]) / 10000;
        token.transfer(msg.sender, boostedReward);
        emit RewardClaimed(msg.sender, boostedReward);
    }

    function unstake(uint256 amount) external {
        if (stakedBalance[msg.sender] < amount) revert InsufficientStake();
        uint8 tier = lockupTier[msg.sender];
        if (tier > 0) {
            require(block.number >= lockupStart[msg.sender] + lockupDuration[tier], "lockup active");
        }
        _updateRewards(msg.sender);
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;
        token.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function slash(address user, uint256 amount) external onlyOwner {
        if (stakedBalance[user] < amount) revert InsufficientStake();
        stakedBalance[user] -= amount;
        totalStaked -= amount;
        token.transfer(treasury, amount);
        emit Slashed(user, amount, treasury);
    }

    function setRewardPerBlock(uint256 _rewardPerBlock) external {
        rewardPerBlock = _rewardPerBlock;
        emit RewardPerBlockUpdated(_rewardPerBlock);
    }

    function pendingReward(address user) external view returns (uint256) {
        return pendingRewards[user];
    }
}
