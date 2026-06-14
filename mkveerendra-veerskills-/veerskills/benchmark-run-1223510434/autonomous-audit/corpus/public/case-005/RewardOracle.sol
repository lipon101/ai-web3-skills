// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RewardOracle {
    address public admin;
    uint256 public baseRewardPerBlock;
    uint256 public lastUpdated;
    uint256 public constant MAX_REWARD_PER_BLOCK = 100e18;
    uint256 public constant UPDATE_COOLDOWN = 100;

    mapping(uint8 => uint256) public tierMultiplierBps;

    event BaseRateUpdated(uint256 oldRate, uint256 newRate);
    event TierMultiplierSet(uint8 tier, uint256 multiplierBps);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    error NotAdmin();
    error CooldownActive();
    error ExceedsMaxRate();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(uint256 _initialRate) {
        admin = msg.sender;
        baseRewardPerBlock = _initialRate;
        lastUpdated = block.number;
        tierMultiplierBps[0] = 10000;
        tierMultiplierBps[1] = 12500;
        tierMultiplierBps[2] = 15000;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function updateBaseRate(uint256 newRate) external onlyAdmin {
        if (block.number < lastUpdated + UPDATE_COOLDOWN) revert CooldownActive();
        if (newRate > MAX_REWARD_PER_BLOCK) revert ExceedsMaxRate();
        emit BaseRateUpdated(baseRewardPerBlock, newRate);
        baseRewardPerBlock = newRate;
        lastUpdated = block.number;
    }

    function setTierMultiplier(uint8 tier, uint256 multiplierBps) external onlyAdmin {
        require(tier <= 2, "invalid tier");
        tierMultiplierBps[tier] = multiplierBps;
        emit TierMultiplierSet(tier, multiplierBps);
    }

    function getRecommendedRate(uint8 tier) external view returns (uint256) {
        return (baseRewardPerBlock * tierMultiplierBps[tier]) / 10000;
    }

    function currentRate() external view returns (uint256) {
        return baseRewardPerBlock;
    }
}
