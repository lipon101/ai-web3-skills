// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SignatureValidator.sol";

contract MultiSigWallet {
    using SignatureValidator for bytes32;

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public threshold;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 approvalCount;
    }

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approved;
    uint256 public nonce;

    event Submitted(uint256 indexed txId);
    event Approved(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event Revoked(uint256 indexed txId, address indexed owner);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event ThresholdChanged(uint256 newThreshold);

    error NotOwner();
    error InvalidTransaction();
    error AlreadyExecuted();
    error AlreadyApproved();
    error NotApproved();
    error BelowThreshold();
    error ExecutionFailed();
    error InvalidThreshold();
    error ZeroAddress();
    error DuplicateOwner();

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    constructor(address[] memory _owners, uint256 _threshold) {
        require(_owners.length > 0, "no owners");
        if (_threshold == 0 || _threshold > _owners.length) revert InvalidThreshold();
        for (uint256 i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            if (o == address(0)) revert ZeroAddress();
            if (isOwner[o]) revert DuplicateOwner();
            isOwner[o] = true;
            owners.push(o);
        }
        threshold = _threshold;
    }

    function submit(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256 txId) {
        txId = transactions.length;
        transactions.push(Transaction(to, value, data, false, 0));
        emit Submitted(txId);
    }

    function approve(uint256 txId) external onlyOwner {
        if (txId >= transactions.length) revert InvalidTransaction();
        if (transactions[txId].executed) revert AlreadyExecuted();
        if (approved[txId][msg.sender]) revert AlreadyApproved();
        approved[txId][msg.sender] = true;
        transactions[txId].approvalCount += 1;
        emit Approved(txId, msg.sender);
    }

    function revoke(uint256 txId) external onlyOwner {
        if (transactions[txId].executed) revert AlreadyExecuted();
        if (!approved[txId][msg.sender]) revert NotApproved();
        approved[txId][msg.sender] = false;
        transactions[txId].approvalCount -= 1;
        emit Revoked(txId, msg.sender);
    }

    function execute(uint256 txId) external onlyOwner {
        Transaction storage t = transactions[txId];
        if (t.executed) revert AlreadyExecuted();
        if (t.approvalCount < threshold) revert BelowThreshold();
        t.executed = true;
        nonce++;
        (bool ok,) = t.to.call{value: t.value}(t.data);
        if (!ok) revert ExecutionFailed();
        emit Executed(txId);
    }

    function addOwner(address owner) external onlySelf {
        if (owner == address(0)) revert ZeroAddress();
        if (isOwner[owner]) revert DuplicateOwner();
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAdded(owner);
    }

    function removeOwner(address owner) external onlySelf {
        if (!isOwner[owner]) revert NotOwner();
        require(owners.length - 1 >= threshold, "would break threshold");
        isOwner[owner] = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoved(owner);
    }

    function changeThreshold(uint256 newThreshold) external onlySelf {
        if (newThreshold == 0 || newThreshold > owners.length) revert InvalidThreshold();
        threshold = newThreshold;
        emit ThresholdChanged(newThreshold);
    }

    function getTransaction(uint256 txId) external view returns (
        address to, uint256 value, bytes memory data, bool executed, uint256 approvalCount
    ) {
        Transaction storage t = transactions[txId];
        return (t.to, t.value, t.data, t.executed, t.approvalCount);
    }

    function isApproved(uint256 txId, address owner) external view returns (bool) {
        return approved[txId][owner];
    }

    function transactionCount() external view returns (uint256) {
        return transactions.length;
    }

    function ownerCount() external view returns (uint256) {
        return owners.length;
    }

    receive() external payable {}
}
