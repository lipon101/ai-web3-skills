// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiSig {
    event Submitted(uint256 indexed txId);
    event Approved(uint256 indexed txId, address indexed owner);
    event Revoked(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event ThresholdChanged(uint256 newThreshold);

    function submit(address to, uint256 value, bytes calldata data) external returns (uint256 txId);
    function approve(uint256 txId) external;
    function revoke(uint256 txId) external;
    function execute(uint256 txId) external;
    function addOwner(address owner) external;
    function removeOwner(address owner) external;
    function changeThreshold(uint256 newThreshold) external;
    function getTransaction(uint256 txId) external view returns (address to, uint256 value, bytes memory data, bool executed, uint256 approvalCount);
    function isApproved(uint256 txId, address owner) external view returns (bool);
}
