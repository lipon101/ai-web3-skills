// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FeeDistributor is Ownable, ReentrancyGuard {
    IERC20 public tokenA;
    IERC20 public tokenB;
    IERC20 public lpToken;

    uint256 public totalFeesA;
    uint256 public totalFeesB;
    mapping(address => uint256) public claimedFeesA;
    mapping(address => uint256) public claimedFeesB;
    mapping(address => uint256) public lastSnapshotA;
    mapping(address => uint256) public lastSnapshotB;

    uint256 public accFeesPerLpA;
    uint256 public accFeesPerLpB;
    uint256 private constant PRECISION = 1e18;

    event FeesDeposited(uint256 amountA, uint256 amountB);
    event FeesClaimed(address indexed staker, uint256 amountA, uint256 amountB);

    error ZeroAddress();
    error NothingToClaim();

    constructor(address _tokenA, address _tokenB, address _lpToken) Ownable(msg.sender) {
        if (_tokenA == address(0) || _tokenB == address(0) || _lpToken == address(0)) revert ZeroAddress();
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        lpToken = IERC20(_lpToken);
    }

    function depositFees(uint256 amountA, uint256 amountB) external nonReentrant {
        uint256 lpSupply = lpToken.totalSupply();
        if (amountA > 0 && lpSupply > 0) {
            tokenA.transferFrom(msg.sender, address(this), amountA);
            accFeesPerLpA += (amountA * PRECISION) / lpSupply;
            totalFeesA += amountA;
        }
        if (amountB > 0 && lpSupply > 0) {
            tokenB.transferFrom(msg.sender, address(this), amountB);
            accFeesPerLpB += (amountB * PRECISION) / lpSupply;
            totalFeesB += amountB;
        }
        emit FeesDeposited(amountA, amountB);
    }

    function claimFees() external nonReentrant {
        uint256 lpBalance = lpToken.balanceOf(msg.sender);
        uint256 pendingA = (lpBalance * accFeesPerLpA) / PRECISION - lastSnapshotA[msg.sender];
        uint256 pendingB = (lpBalance * accFeesPerLpB) / PRECISION - lastSnapshotB[msg.sender];
        if (pendingA == 0 && pendingB == 0) revert NothingToClaim();
        lastSnapshotA[msg.sender] = (lpBalance * accFeesPerLpA) / PRECISION;
        lastSnapshotB[msg.sender] = (lpBalance * accFeesPerLpB) / PRECISION;
        if (pendingA > 0) tokenA.transfer(msg.sender, pendingA);
        if (pendingB > 0) tokenB.transfer(msg.sender, pendingB);
        emit FeesClaimed(msg.sender, pendingA, pendingB);
    }

    function pendingFees(address staker) external view returns (uint256 pendingA, uint256 pendingB) {
        uint256 lpBalance = lpToken.balanceOf(staker);
        pendingA = (lpBalance * accFeesPerLpA) / PRECISION - lastSnapshotA[staker];
        pendingB = (lpBalance * accFeesPerLpB) / PRECISION - lastSnapshotB[staker];
    }
}
