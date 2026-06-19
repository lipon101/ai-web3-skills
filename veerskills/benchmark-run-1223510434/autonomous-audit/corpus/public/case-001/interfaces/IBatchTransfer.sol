// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBatchTransfer {
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event BatchSent(address indexed token, uint256 recipientCount, uint256 totalAmount);
    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event SpendingLimitSet(address indexed token, uint256 limitPerBatch);

    function addOperator(address op) external;
    function removeOperator(address op) external;
    function batchSend(address[] calldata recipients, uint256[] calldata amounts) external;
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function addSupportedToken(address token) external;
    function removeSupportedToken(address token) external;
    function setSpendingLimit(address token, uint256 limitPerBatch) external;
    function batchSendToken(address token, address[] calldata recipients, uint256[] calldata amounts) external;
}
