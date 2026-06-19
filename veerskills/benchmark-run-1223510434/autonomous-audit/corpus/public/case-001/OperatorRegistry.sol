// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OperatorRegistry {
    address public admin;
    mapping(address => bool) public registeredOperators;
    mapping(address => uint256) public operatorSince;
    address[] private _operatorList;

    event OperatorRegistered(address indexed operator, uint256 timestamp);
    event OperatorDeregistered(address indexed operator);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    error NotAdmin();
    error AlreadyRegistered();
    error NotRegistered();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function register(address operator) external onlyAdmin {
        if (operator == address(0)) revert ZeroAddress();
        if (registeredOperators[operator]) revert AlreadyRegistered();
        registeredOperators[operator] = true;
        operatorSince[operator] = block.timestamp;
        _operatorList.push(operator);
        emit OperatorRegistered(operator, block.timestamp);
    }

    function deregister(address operator) external onlyAdmin {
        if (!registeredOperators[operator]) revert NotRegistered();
        registeredOperators[operator] = false;
        emit OperatorDeregistered(operator);
    }

    function isAuthorized(address caller) external view returns (bool) {
        return registeredOperators[caller];
    }

    function operatorCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < _operatorList.length; i++) {
            if (registeredOperators[_operatorList[i]]) count++;
        }
    }

    function getOperators() external view returns (address[] memory active) {
        uint256 count;
        for (uint256 i = 0; i < _operatorList.length; i++) {
            if (registeredOperators[_operatorList[i]]) count++;
        }
        active = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < _operatorList.length; i++) {
            if (registeredOperators[_operatorList[i]]) {
                active[idx++] = _operatorList[i];
            }
        }
    }
}
