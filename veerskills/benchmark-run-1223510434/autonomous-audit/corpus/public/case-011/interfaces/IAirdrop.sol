// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAirdrop {
    event Claimed(address indexed account, uint256 amount, uint256 window);
    event WindowAdded(uint256 indexed windowId, bytes32 merkleRoot, uint256 startTime, uint256 endTime, uint256 totalAllocation);
    event VestingAccelerated(address indexed account, uint256 windowId);
    event Revoked(uint256 indexed windowId, uint256 unclaimedAmount);

    function claim(uint256 windowId, uint256 totalAllocation, bytes32[] calldata proof) external;
    function claimable(uint256 windowId, address account, uint256 totalAllocation) external view returns (uint256);
    function addWindow(bytes32 merkleRoot, uint256 startTime, uint256 endTime, uint256 totalAllocation) external;
    function revokeWindow(uint256 windowId) external;
    function accelerateVesting(uint256 windowId, address account, uint256 totalAllocation, bytes32[] calldata proof) external;
}
