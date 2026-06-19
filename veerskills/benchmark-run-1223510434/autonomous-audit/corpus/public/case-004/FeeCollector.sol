// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FeeCollector {
    address public admin;
    uint256 public constant BASIS_POINTS = 10000;

    mapping(uint8 => uint256) public feeTierBps;
    mapping(address => uint8) public depositorTier;
    mapping(address => uint256) public collectedFees;

    event FeeCollected(address indexed vault, address indexed depositor, uint256 feeAmount, uint8 tier);
    event FeeTierSet(uint8 tier, uint256 bps);
    event DepositorTierSet(address indexed depositor, uint8 tier);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event FeesWithdrawn(address indexed admin, uint256 amount);

    error NotAdmin();
    error InvalidTier();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor() {
        admin = msg.sender;
        feeTierBps[0] = 50;
        feeTierBps[1] = 30;
        feeTierBps[2] = 10;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function setFeeTier(uint8 tier, uint256 bps) external onlyAdmin {
        if (tier > 2) revert InvalidTier();
        require(bps <= BASIS_POINTS, "exceeds basis points");
        feeTierBps[tier] = bps;
        emit FeeTierSet(tier, bps);
    }

    function setDepositorTier(address depositor, uint8 tier) external onlyAdmin {
        if (depositor == address(0)) revert ZeroAddress();
        if (tier > 2) revert InvalidTier();
        depositorTier[depositor] = tier;
        emit DepositorTierSet(depositor, tier);
    }

    function collectFee(address depositor, uint256 withdrawalAmount) external payable returns (uint256 fee) {
        uint8 tier = depositorTier[depositor];
        fee = (withdrawalAmount * feeTierBps[tier]) / BASIS_POINTS;
        collectedFees[msg.sender] += fee;
        emit FeeCollected(msg.sender, depositor, fee, tier);
    }

    function computeFee(address depositor, uint256 amount) external view returns (uint256) {
        uint8 tier = depositorTier[depositor];
        return (amount * feeTierBps[tier]) / BASIS_POINTS;
    }

    function withdrawFees() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "nothing to withdraw");
        (bool ok,) = admin.call{value: balance}("");
        require(ok, "transfer failed");
        emit FeesWithdrawn(admin, balance);
    }

    receive() external payable {}
}
