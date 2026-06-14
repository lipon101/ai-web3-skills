// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FeeCollector.sol";

contract EscrowVault {
    FeeCollector public feeCollector;
    mapping(address => uint256) public deposits;
    mapping(address => address payable) public recipients;
    bool private _locked;

    event Deposited(address indexed depositor, address indexed recipient, uint256 amount);
    event Withdrawn(address indexed depositor, address indexed to, uint256 amount, uint256 fee);
    event Cancelled(address indexed depositor, uint256 amount);
    event RecipientUpdated(address indexed depositor, address indexed newRecipient);

    error EmptyDeposit();
    error ZeroAddress();
    error Reentrant();

    modifier nonReentrant() {
        if (_locked) revert Reentrant();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address _feeCollector) {
        feeCollector = FeeCollector(_feeCollector);
    }

    function deposit(address payable recipient) external payable nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        deposits[msg.sender] += msg.value;
        recipients[msg.sender] = recipient;
        emit Deposited(msg.sender, recipient, msg.value);
    }

    function withdrawTo(address payable to) external {
        uint256 amount = deposits[msg.sender];
        require(amount > 0, "empty");
        uint256 fee = feeCollector.computeFee(msg.sender, amount);
        (bool ok,) = to.call{value: amount - fee}("");
        require(ok, "failed");
        deposits[msg.sender] = 0;
        if (fee > 0) {
            (bool feeOk,) = address(feeCollector).call{value: fee}("");
            require(feeOk, "fee transfer failed");
        }
        emit Withdrawn(msg.sender, to, amount - fee, fee);
    }

    function cancel() external nonReentrant {
        uint256 amount = deposits[msg.sender];
        if (amount == 0) revert EmptyDeposit();
        deposits[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "failed");
        emit Cancelled(msg.sender, amount);
    }

    function updateRecipient(address payable newRecipient) external {
        if (newRecipient == address(0)) revert ZeroAddress();
        if (deposits[msg.sender] == 0) revert EmptyDeposit();
        recipients[msg.sender] = newRecipient;
        emit RecipientUpdated(msg.sender, newRecipient);
    }

    function getBalance(address depositor) external view returns (uint256) {
        return deposits[depositor];
    }

    function getFee(address depositor) external view returns (uint256) {
        return feeCollector.computeFee(depositor, deposits[depositor]);
    }
}
