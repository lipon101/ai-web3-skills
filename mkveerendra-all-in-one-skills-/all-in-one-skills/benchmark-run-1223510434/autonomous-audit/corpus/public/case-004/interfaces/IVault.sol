// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVault {
    event Deposited(address indexed depositor, address indexed recipient, uint256 amount);
    event Withdrawn(address indexed depositor, address indexed to, uint256 amount, uint256 fee);
    event Cancelled(address indexed depositor, uint256 amount);
    event RecipientUpdated(address indexed depositor, address indexed newRecipient);
    event FeeTierSet(address indexed depositor, uint8 tier);

    function deposit(address payable recipient) external payable;
    function withdrawTo(address payable to) external;
    function cancel() external;
    function updateRecipient(address payable newRecipient) external;
    function getBalance(address depositor) external view returns (uint256);
    function getFee(address depositor) external view returns (uint256);
}
