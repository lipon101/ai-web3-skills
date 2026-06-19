// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TokenRegistry {
    address public admin;
    mapping(address => bool) public allowedTokens;
    address[] private _tokenList;
    mapping(address => uint256) public dailyTransferLimit;

    event TokenRegistered(address indexed token, uint256 dailyLimit);
    event TokenDeregistered(address indexed token);
    event DailyLimitUpdated(address indexed token, uint256 newLimit);
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

    function registerToken(address token, uint256 dailyLimit) external onlyAdmin {
        if (token == address(0)) revert ZeroAddress();
        if (allowedTokens[token]) revert AlreadyRegistered();
        allowedTokens[token] = true;
        dailyTransferLimit[token] = dailyLimit;
        _tokenList.push(token);
        emit TokenRegistered(token, dailyLimit);
    }

    function deregisterToken(address token) external onlyAdmin {
        if (!allowedTokens[token]) revert NotRegistered();
        allowedTokens[token] = false;
        emit TokenDeregistered(token);
    }

    function setDailyLimit(address token, uint256 newLimit) external onlyAdmin {
        if (!allowedTokens[token]) revert NotRegistered();
        dailyTransferLimit[token] = newLimit;
        emit DailyLimitUpdated(token, newLimit);
    }

    function isAllowed(address token) external view returns (bool) {
        return allowedTokens[token];
    }

    function getTokenCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (allowedTokens[_tokenList[i]]) count++;
        }
    }

    function getAllowedTokens() external view returns (address[] memory active) {
        uint256 count;
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (allowedTokens[_tokenList[i]]) count++;
        }
        active = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (allowedTokens[_tokenList[i]]) {
                active[idx++] = _tokenList[i];
            }
        }
    }
}
