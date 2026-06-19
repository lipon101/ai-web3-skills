// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract DutchAuction {
    IERC20 public token;
    address public seller;

    uint256 public startPrice;
    uint256 public reservePrice;
    uint256 public startTime;
    uint256 public duration;
    uint256 public tokensForSale;
    uint256 public tokensSold;
    bool public settled;

    event TokensPurchased(address indexed buyer, uint256 tokenAmount, uint256 ethPaid, uint256 refund);
    event AuctionSettled(address indexed seller, uint256 proceeds);
    event UnsoldTokensRecovered(address indexed seller, uint256 amount);

    error AuctionFinished();
    error SoldOut();
    error Underpaid();
    error NotSeller();
    error AlreadySettled();
    error RefundFailed();
    error TransferFailed();

    constructor(
        address _token,
        address _seller,
        uint256 _startPrice,
        uint256 _reservePrice,
        uint256 _duration,
        uint256 _tokensForSale
    ) {
        token = IERC20(_token);
        seller = _seller;
        startPrice = _startPrice;
        reservePrice = _reservePrice;
        startTime = block.timestamp;
        duration = _duration;
        tokensForSale = _tokensForSale;
    }

    function currentPrice() public view returns (uint256) {
        if (block.timestamp >= startTime + duration) return reservePrice;
        uint256 elapsed = block.timestamp - startTime;
        uint256 priceDrop = ((startPrice - reservePrice) * elapsed) / duration;
        return startPrice - priceDrop;
    }

    function buy(uint256 tokenAmount) external payable {
        require(tokensSold + tokenAmount <= tokensForSale, "sold out");
        uint256 price = currentPrice();
        uint256 cost = (tokenAmount * price) / 1e18;
        require(msg.value >= cost, "underpaid");
        uint256 excess = msg.value - cost;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "refund failed");
        }
        tokensSold += tokenAmount;
        token.transfer(msg.sender, tokenAmount);
        emit TokensPurchased(msg.sender, tokenAmount, cost, excess);
    }

    function withdrawProceeds() external {
        if (msg.sender != seller) revert NotSeller();
        uint256 balance = address(this).balance;
        (bool ok,) = seller.call{value: balance}("");
        require(ok, "failed");
        emit AuctionSettled(seller, balance);
    }

    function recoverUnsoldTokens() external {
        if (msg.sender != seller) revert NotSeller();
        require(block.timestamp >= startTime + duration, "auction active");
        uint256 unsold = tokensForSale - tokensSold;
        if (unsold > 0) {
            token.transfer(seller, unsold);
            emit UnsoldTokensRecovered(seller, unsold);
        }
    }

    function remainingTokens() external view returns (uint256) {
        return tokensForSale - tokensSold;
    }

    function isFinished() external view returns (bool) {
        return block.timestamp >= startTime + duration || tokensSold == tokensForSale;
    }

    receive() external payable {}
}
