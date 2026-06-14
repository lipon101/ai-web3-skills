// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EscrowFactory {
    address public admin;
    address[] public deployedEscrows;
    mapping(address => bool) public isEscrow;

    event EscrowDeployed(address indexed escrow, address indexed deployer, uint256 indexed escrowId);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    error NotAdmin();
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

    function deployEscrow(address payable recipient, uint256 releaseBlock) external payable returns (address escrow) {
        require(msg.value > 0, "no value");
        require(releaseBlock > block.number, "invalid block");
        ConditionalEscrowMinimal newEscrow = new ConditionalEscrowMinimal{value: msg.value}(
            payable(msg.sender),
            recipient,
            releaseBlock
        );
        escrow = address(newEscrow);
        deployedEscrows.push(escrow);
        isEscrow[escrow] = true;
        emit EscrowDeployed(escrow, msg.sender, deployedEscrows.length - 1);
    }

    function escrowCount() external view returns (uint256) {
        return deployedEscrows.length;
    }

    function getEscrow(uint256 index) external view returns (address) {
        return deployedEscrows[index];
    }
}

contract ConditionalEscrowMinimal {
    address payable public depositor;
    address payable public recipient;
    uint256 public releaseBlock;
    bool public settled;

    constructor(address payable _depositor, address payable _recipient, uint256 _releaseBlock) payable {
        depositor = _depositor;
        recipient = _recipient;
        releaseBlock = _releaseBlock;
    }

    function release() external {
        require(!settled, "settled");
        require(block.number >= releaseBlock, "not ready");
        settled = true;
        recipient.transfer(address(this).balance);
    }

    function refundToDepositor() external {
        require(msg.sender == depositor, "not depositor");
        require(!settled, "settled");
        require(block.number < releaseBlock, "release block passed");
        settled = true;
        depositor.transfer(address(this).balance);
    }
}
