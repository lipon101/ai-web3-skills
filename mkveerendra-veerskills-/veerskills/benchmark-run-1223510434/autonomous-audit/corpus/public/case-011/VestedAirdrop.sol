// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleLib.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract VestedAirdrop {
    IERC20 public token;
    address public admin;

    struct Window {
        bytes32 merkleRoot;
        uint256 startTime;
        uint256 endTime;
        uint256 totalAllocation;
        uint256 claimed;
        bool revoked;
    }

    mapping(uint256 => Window) public windows;
    uint256 public windowCount;
    mapping(uint256 => mapping(address => uint256)) public windowClaimed;
    mapping(uint256 => mapping(address => bool)) public accelerated;

    uint256 public constant ACCELERATION_BONUS_BPS = 500;

    event Claimed(address indexed account, uint256 amount, uint256 window);
    event WindowAdded(uint256 indexed windowId, bytes32 merkleRoot, uint256 startTime, uint256 endTime, uint256 totalAllocation);
    event VestingAccelerated(address indexed account, uint256 windowId);
    event Revoked(uint256 indexed windowId, uint256 unclaimedAmount);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    error NotAdmin();
    error WindowRevoked();
    error WindowNotActive();
    error InvalidProof();
    error NothingToClaim();
    error AlreadyAccelerated();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(address _token) {
        if (_token == address(0)) revert ZeroAddress();
        token = IERC20(_token);
        admin = msg.sender;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function addWindow(
        bytes32 merkleRoot,
        uint256 startTime,
        uint256 endTime,
        uint256 totalAllocation
    ) external onlyAdmin returns (uint256 windowId) {
        require(endTime > startTime, "invalid window");
        require(totalAllocation > 0, "zero allocation");
        windowId = windowCount++;
        windows[windowId] = Window(merkleRoot, startTime, endTime, totalAllocation, 0, false);
        emit WindowAdded(windowId, merkleRoot, startTime, endTime, totalAllocation);
    }

    function claimable(uint256 windowId, address account, uint256 totalAllocation) public view returns (uint256) {
        Window storage w = windows[windowId];
        if (w.revoked || block.timestamp < w.startTime) return 0;
        uint256 elapsed = block.timestamp - w.startTime;
        uint256 duration = w.endTime - w.startTime;
        if (elapsed >= duration) elapsed = duration;
        uint256 vested = (totalAllocation * elapsed) / duration;
        if (accelerated[windowId][account]) {
            uint256 bonus = (totalAllocation * ACCELERATION_BONUS_BPS) / 10000;
            vested = vested + bonus > totalAllocation ? totalAllocation : vested + bonus;
        }
        uint256 alreadyClaimed = windowClaimed[windowId][account];
        return vested > alreadyClaimed ? vested - alreadyClaimed : 0;
    }

    function claim(uint256 windowId, uint256 totalAllocation, bytes32[] calldata proof) external {
        Window storage w = windows[windowId];
        if (w.revoked) revert WindowRevoked();
        if (block.timestamp < w.startTime) revert WindowNotActive();
        bytes32 leaf = MerkleLib.leafHash(msg.sender, totalAllocation);
        if (!MerkleLib.verify(proof, w.merkleRoot, leaf)) revert InvalidProof();
        uint256 amount = claimable(windowId, msg.sender, totalAllocation);
        if (amount == 0) revert NothingToClaim();
        windowClaimed[windowId][msg.sender] += amount;
        w.claimed += amount;
        token.transfer(msg.sender, amount);
        emit Claimed(msg.sender, amount, windowId);
    }

    function accelerateVesting(
        uint256 windowId,
        address account,
        uint256 totalAllocation,
        bytes32[] calldata proof
    ) external onlyAdmin {
        Window storage w = windows[windowId];
        if (w.revoked) revert WindowRevoked();
        if (accelerated[windowId][account]) revert AlreadyAccelerated();
        bytes32 leaf = MerkleLib.leafHash(account, totalAllocation);
        if (!MerkleLib.verify(proof, w.merkleRoot, leaf)) revert InvalidProof();
        accelerated[windowId][account] = true;
        emit VestingAccelerated(account, windowId);
    }

    function revokeWindow(uint256 windowId) external onlyAdmin {
        Window storage w = windows[windowId];
        require(!w.revoked, "already revoked");
        w.revoked = true;
        uint256 unclaimed = w.totalAllocation - w.claimed;
        if (unclaimed > 0) {
            token.transfer(admin, unclaimed);
        }
        emit Revoked(windowId, unclaimed);
    }
}
