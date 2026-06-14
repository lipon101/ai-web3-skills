// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PriceLib {
    uint256 internal constant PRECISION = 1e18;

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeBps
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "zero input");
        require(reserveIn > 0 && reserveOut > 0, "empty reserves");
        uint256 amountInWithFee = amountIn * (10000 - feeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeBps
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "zero output");
        require(reserveIn > 0 && reserveOut > 0, "empty reserves");
        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = (reserveOut - amountOut) * (10000 - feeBps);
        amountIn = numerator / denominator + 1;
    }

    function quoteProportional(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "zero amount");
        require(reserveA > 0, "zero reserve");
        amountB = (amountA * reserveB) / reserveA;
    }

    function spotPrice(uint256 reserveA, uint256 reserveB) internal pure returns (uint256) {
        require(reserveA > 0, "zero reserve");
        return (reserveB * PRECISION) / reserveA;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
