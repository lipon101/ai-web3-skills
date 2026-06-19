// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./PriceLib.sol";

contract LiquidityPool is ERC20, Ownable, ReentrancyGuard {
    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    uint256 public constant FEE_BPS = 30;
    uint256 public accumulatedFeesA;
    uint256 public accumulatedFeesB;

    address public feeDistributor;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event SwapAForB(address indexed trader, uint256 amountIn, uint256 amountOut);
    event SwapBForA(address indexed trader, uint256 amountIn, uint256 amountOut);
    event FeesDistributed(address indexed distributor, uint256 amountA, uint256 amountB);
    event FeeDistributorSet(address indexed distributor);

    error InsufficientLiquidity();
    error ZeroAmount();
    error ZeroAddress();

    constructor(address _tokenA, address _tokenB)
        ERC20("LP Token", "LP")
        Ownable(msg.sender)
    {
        if (_tokenA == address(0) || _tokenB == address(0)) revert ZeroAddress();
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function setFeeDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) revert ZeroAddress();
        feeDistributor = _distributor;
        emit FeeDistributorSet(_distributor);
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external nonReentrant returns (uint256 lpTokens) {
        if (amountA == 0 || amountB == 0) revert ZeroAmount();
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        uint256 supply = totalSupply();
        if (supply == 0) {
            lpTokens = PriceLib.sqrt(amountA * amountB);
        } else {
            lpTokens = PriceLib.min(
                (amountA * supply) / reserveA,
                (amountB * supply) / reserveB
            );
        }
        if (lpTokens == 0) revert InsufficientLiquidity();

        reserveA += amountA;
        reserveB += amountB;
        _mint(msg.sender, lpTokens);
        emit LiquidityAdded(msg.sender, amountA, amountB, lpTokens);
    }

    function removeLiquidity(uint256 lpTokens) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (lpTokens == 0) revert ZeroAmount();
        uint256 supply = totalSupply();
        amountA = (lpTokens * reserveA) / supply;
        amountB = (lpTokens * reserveB) / supply;
        if (amountA == 0 || amountB == 0) revert InsufficientLiquidity();

        _burn(msg.sender, lpTokens);
        reserveA -= amountA;
        reserveB -= amountB;

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);
        emit LiquidityRemoved(msg.sender, amountA, amountB, lpTokens);
    }

    function swapAForB(uint256 amountAIn) external nonReentrant returns (uint256 amountBOut) {
        if (amountAIn == 0) revert ZeroAmount();
        amountBOut = PriceLib.getAmountOut(amountAIn, reserveA, reserveB, FEE_BPS);

        uint256 feeA = (amountAIn * FEE_BPS) / 10000;
        accumulatedFeesA += feeA;

        tokenA.transferFrom(msg.sender, address(this), amountAIn);
        reserveA += amountAIn;
        reserveB -= amountBOut;
        tokenB.transfer(msg.sender, amountBOut);
        emit SwapAForB(msg.sender, amountAIn, amountBOut);
    }

    function swapBForA(uint256 amountBIn) external nonReentrant returns (uint256 amountAOut) {
        if (amountBIn == 0) revert ZeroAmount();
        amountAOut = PriceLib.getAmountOut(amountBIn, reserveB, reserveA, FEE_BPS);

        uint256 feeB = (amountBIn * FEE_BPS) / 10000;
        accumulatedFeesB += feeB;

        tokenB.transferFrom(msg.sender, address(this), amountBIn);
        reserveB += amountBIn;
        reserveA -= amountAOut;
        tokenA.transfer(msg.sender, amountAOut);
        emit SwapBForA(msg.sender, amountBIn, amountAOut);
    }

    function distributeFees() external nonReentrant {
        require(feeDistributor != address(0), "no distributor");
        uint256 feesA = accumulatedFeesA;
        uint256 feesB = accumulatedFeesB;
        accumulatedFeesA = 0;
        accumulatedFeesB = 0;
        if (feesA > 0) tokenA.transfer(feeDistributor, feesA);
        if (feesB > 0) tokenB.transfer(feeDistributor, feesB);
        emit FeesDistributed(feeDistributor, feesA, feesB);
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    function spotPrice() external view returns (uint256) {
        return PriceLib.spotPrice(reserveA, reserveB);
    }

    function quoteAmountB(uint256 amountA) external view returns (uint256) {
        return PriceLib.quoteProportional(amountA, reserveA, reserveB);
    }
}
