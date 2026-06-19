// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract BatchTransfer {
    IERC20 public token;
    address public owner;
    mapping(address => bool) public operators;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public spendingLimit;

    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event BatchSent(address indexed token, uint256 recipientCount, uint256 totalAmount);
    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event SpendingLimitSet(address indexed token, uint256 limitPerBatch);

    error NotOwner();
    error NotOperator();
    error LengthMismatch();
    error TokenNotSupported();
    error SpendingLimitExceeded(uint256 requested, uint256 limit);
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
        supportedTokens[_token] = true;
    }

    function addOperator(address op) external onlyOwner {
        if (op == address(0)) revert ZeroAddress();
        operators[op] = true;
        emit OperatorAdded(op);
    }

    function removeOperator(address op) external onlyOwner {
        operators[op] = false;
        emit OperatorRemoved(op);
    }

    function addSupportedToken(address _token) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();
        supportedTokens[_token] = true;
        emit TokenAdded(_token);
    }

    function removeSupportedToken(address _token) external onlyOwner {
        supportedTokens[_token] = false;
        emit TokenRemoved(_token);
    }

    function setSpendingLimit(address _token, uint256 limitPerBatch) external onlyOwner {
        spendingLimit[_token] = limitPerBatch;
        emit SpendingLimitSet(_token, limitPerBatch);
    }

    function batchSend(address[] calldata recipients, uint256[] calldata amounts) external {
        require(operators[tx.origin], "not operator");
        if (recipients.length != amounts.length) revert LengthMismatch();
        uint256 total;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        uint256 limit = spendingLimit[address(token)];
        if (limit > 0 && total > limit) revert SpendingLimitExceeded(total, limit);
        for (uint256 i = 0; i < recipients.length; i++) {
            token.transfer(recipients[i], amounts[i]);
        }
        emit BatchSent(address(token), recipients.length, total);
    }

    function batchSendToken(
        address _token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        if (!supportedTokens[_token]) revert TokenNotSupported();
        if (!operators[msg.sender]) revert NotOperator();
        if (recipients.length != amounts.length) revert LengthMismatch();
        uint256 total;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        uint256 limit = spendingLimit[_token];
        if (limit > 0 && total > limit) revert SpendingLimitExceeded(total, limit);
        IERC20 t = IERC20(_token);
        for (uint256 i = 0; i < recipients.length; i++) {
            t.transfer(recipients[i], amounts[i]);
        }
        emit BatchSent(_token, recipients.length, total);
    }

    function deposit(uint256 amount) external onlyOwner {
        token.transferFrom(msg.sender, address(this), amount);
        emit Deposited(address(token), amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        token.transfer(owner, amount);
        emit Withdrawn(address(token), amount);
    }

    function vaultBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
