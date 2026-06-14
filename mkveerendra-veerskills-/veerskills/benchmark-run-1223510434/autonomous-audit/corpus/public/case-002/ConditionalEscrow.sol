// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ConditionalEscrow {
    struct Escrow {
        address payable depositor;
        address payable recipient;
        uint256 amount;
        uint256 releaseBlock;
        bool settled;
        bool disputed;
    }

    address public arbitrator;
    mapping(uint256 => Escrow) public escrows;
    uint256 public nextId;

    event Created(uint256 indexed id, address depositor, address recipient, uint256 releaseBlock);
    event Released(uint256 indexed id);
    event Refunded(uint256 indexed id);
    event DisputeRaised(uint256 indexed id, address indexed initiator);
    event DisputeResolved(uint256 indexed id, bool releasedToRecipient);
    event ArbitratorSet(address indexed newArbitrator);

    error NotArbitrator();
    error NotDepositorOrRecipient();
    error AlreadySettled();
    error NotReady();
    error ZeroValue();
    error InvalidReleaseBlock();

    modifier onlyArbitrator() {
        if (msg.sender != arbitrator) revert NotArbitrator();
        _;
    }

    constructor(address _arbitrator) {
        arbitrator = _arbitrator;
    }

    function setArbitrator(address _arbitrator) external onlyArbitrator {
        arbitrator = _arbitrator;
        emit ArbitratorSet(_arbitrator);
    }

    function create(address payable recipient, uint256 releaseBlock) external payable returns (uint256 id) {
        if (msg.value == 0) revert ZeroValue();
        if (releaseBlock <= block.number) revert InvalidReleaseBlock();
        id = nextId++;
        escrows[id] = Escrow(payable(msg.sender), recipient, msg.value, releaseBlock, false, false);
        emit Created(id, msg.sender, recipient, releaseBlock);
    }

    function release(uint256 id) external {
        Escrow storage e = escrows[id];
        if (e.settled) revert AlreadySettled();
        require(block.number >= e.releaseBlock, "not ready");
        e.settled = true;
        e.recipient.transfer(e.amount);
        emit Released(id);
    }

    function refund(uint256 id) external {
        Escrow storage e = escrows[id];
        require(msg.sender == e.depositor, "not depositor");
        require(!e.settled, "settled");
        e.settled = true;
        e.depositor.transfer(e.amount);
        emit Refunded(id);
    }

    function raiseDispute(uint256 id) external {
        Escrow storage e = escrows[id];
        if (e.settled) revert AlreadySettled();
        require(msg.sender == e.depositor || msg.sender == e.recipient, "not party");
        e.disputed = true;
        emit DisputeRaised(id, msg.sender);
    }

    function resolveDispute(uint256 id, bool releaseToRecipient) external onlyArbitrator {
        Escrow storage e = escrows[id];
        require(e.disputed, "not disputed");
        if (e.settled) revert AlreadySettled();
        e.settled = true;
        if (releaseToRecipient) {
            e.recipient.transfer(e.amount);
        } else {
            e.depositor.transfer(e.amount);
        }
        emit DisputeResolved(id, releaseToRecipient);
    }

    function escrowCount() external view returns (uint256) {
        return nextId;
    }

    function isSettled(uint256 id) external view returns (bool) {
        return escrows[id].settled;
    }

    function isDisputed(uint256 id) external view returns (bool) {
        return escrows[id].disputed;
    }
}
