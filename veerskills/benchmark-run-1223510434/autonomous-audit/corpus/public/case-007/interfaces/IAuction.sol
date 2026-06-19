// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAuction {
    event AuctionCreated(address indexed auction, address indexed seller, address token, uint256 tokensForSale);
    event TokensPurchased(address indexed buyer, uint256 tokenAmount, uint256 ethPaid);
    event AuctionSettled(address indexed seller, uint256 proceeds);
    event UnsoldTokensRecovered(address indexed seller, uint256 amount);

    function buy(uint256 tokenAmount) external payable;
    function withdrawProceeds() external;
    function recoverUnsoldTokens() external;
    function currentPrice() external view returns (uint256);
    function remainingTokens() external view returns (uint256);
    function isFinished() external view returns (bool);
}
