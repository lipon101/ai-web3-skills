// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AuctionFactory {
    address public admin;
    address[] public auctions;
    mapping(address => bool) public isAuction;

    event AuctionDeployed(address indexed auction, address indexed seller, address indexed token);
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

    function createAuction(
        address token,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 tokensForSale
    ) external returns (address auction) {
        if (token == address(0)) revert ZeroAddress();
        require(startPrice >= reservePrice, "start below reserve");
        require(duration > 0, "zero duration");
        require(tokensForSale > 0, "zero tokens");
        DutchAuction newAuction = new DutchAuction(
            token,
            msg.sender,
            startPrice,
            reservePrice,
            duration,
            tokensForSale
        );
        auction = address(newAuction);
        auctions.push(auction);
        isAuction[auction] = true;
        emit AuctionDeployed(auction, msg.sender, token);
    }

    function auctionCount() external view returns (uint256) {
        return auctions.length;
    }

    function getAuction(uint256 index) external view returns (address) {
        return auctions[index];
    }
}

interface DutchAuctionLike {
    function buy(uint256 tokenAmount) external payable;
    function currentPrice() external view returns (uint256);
    function remainingTokens() external view returns (uint256);
}
