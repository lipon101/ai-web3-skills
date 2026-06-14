// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBondMarket {
    event MarketCreated(uint256 indexed id, address indexed issuer, uint256 price, uint256 discountBps, uint256 capacity);
    event BondPurchased(uint256 indexed marketId, address indexed buyer, uint256 amount, uint256 paid);
    event MarketSettled(uint256 indexed id);
    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);
    event Withdrawn(uint256 indexed marketId, address indexed issuer, uint256 amount);

    function createMarket(uint256 price, uint256 discountBps, uint256 capacity) external returns (uint256 id);
    function purchase(uint256 marketId, uint256 amount) external payable;
    function settleMarket(uint256 marketId) external;
    function withdraw(uint256 marketId) external;
    function addIssuer(address issuer) external;
    function removeIssuer(address issuer) external;
    function effectivePrice(uint256 marketId) external view returns (uint256);
    function availableCapacity(uint256 marketId) external view returns (uint256);
}
