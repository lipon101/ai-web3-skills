// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityPool {
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event SwapAForB(address indexed trader, uint256 amountIn, uint256 amountOut);
    event SwapBForA(address indexed trader, uint256 amountIn, uint256 amountOut);
    event FeesCollected(address indexed distributor, uint256 amountA, uint256 amountB);

    function addLiquidity(uint256 amountA, uint256 amountB) external returns (uint256 lpTokens);
    function removeLiquidity(uint256 lpTokens) external returns (uint256 amountA, uint256 amountB);
    function swapAForB(uint256 amountAIn) external returns (uint256 amountBOut);
    function swapBForA(uint256 amountBIn) external returns (uint256 amountAOut);
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB);
    function spotPrice() external view returns (uint256 priceAInB);
}
