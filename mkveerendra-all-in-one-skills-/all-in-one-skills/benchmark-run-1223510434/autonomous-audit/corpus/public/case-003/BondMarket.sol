// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BondToken.sol";

contract BondMarket {
    struct Market {
        address owner;
        uint256 price;
        uint256 discountBps;
        uint256 sold;
        uint256 capacity;
        bool settled;
        uint256 proceeds;
        address bondToken;
    }

    address public admin;
    mapping(uint256 => Market) public markets;
    uint256 public nextId;
    mapping(address => bool) public authorizedIssuers;

    event MarketCreated(uint256 indexed id, address indexed issuer, uint256 price, uint256 discountBps, uint256 capacity);
    event BondPurchased(uint256 indexed marketId, address indexed buyer, uint256 amount, uint256 paid);
    event MarketSettled(uint256 indexed id, uint256 proceeds);
    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);
    event Withdrawn(uint256 indexed marketId, address indexed issuer, uint256 amount);

    error NotAdmin();
    error NotMarketOwner();
    error AlreadySettled();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function addIssuer(address issuer) external onlyAdmin {
        if (issuer == address(0)) revert ZeroAddress();
        authorizedIssuers[issuer] = true;
        emit IssuerAdded(issuer);
    }

    function removeIssuer(address issuer) external onlyAdmin {
        authorizedIssuers[issuer] = false;
        emit IssuerRemoved(issuer);
    }

    function createMarket(
        uint256 price,
        uint256 discountBps,
        uint256 capacity
    ) external returns (uint256 id) {
        require(authorizedIssuers[msg.sender], "not issuer");
        require(price > 0, "zero price");
        require(capacity > 0, "zero capacity");
        id = nextId++;
        BondToken bt = new BondToken(
            string(abi.encodePacked("Bond-", _toString(id))),
            string(abi.encodePacked("BND", _toString(id))),
            id,
            address(this)
        );
        markets[id] = Market(msg.sender, price, discountBps, 0, capacity, false, 0, address(bt));
        emit MarketCreated(id, msg.sender, price, discountBps, capacity);
    }

    function purchase(uint256 marketId, uint256 amount) external payable {
        Market storage m = markets[marketId];
        require(!m.settled, "settled");
        require(m.sold + amount <= m.capacity, "sold out");
        uint256 ep = m.price * (10000 - m.discountBps) / 10000;
        require(msg.value >= ep * amount, "insufficient payment");
        m.sold += amount;
        m.proceeds += msg.value;
        BondToken(m.bondToken).mint(msg.sender, amount);
        emit BondPurchased(marketId, msg.sender, amount, msg.value);
    }

    function settleMarket(uint256 marketId) external {
        Market storage m = markets[marketId];
        if (msg.sender != m.owner) revert NotMarketOwner();
        if (m.settled) revert AlreadySettled();
        m.settled = true;
        emit MarketSettled(marketId, m.proceeds);
    }

    function withdraw(uint256 marketId) external {
        Market storage m = markets[marketId];
        if (msg.sender != m.owner) revert NotMarketOwner();
        require(m.settled, "not settled");
        uint256 amount = m.proceeds;
        m.proceeds = 0;
        (bool ok,) = m.owner.call{value: amount}("");
        require(ok, "transfer failed");
        emit Withdrawn(marketId, msg.sender, amount);
    }

    function effectivePrice(uint256 marketId) external view returns (uint256) {
        Market storage m = markets[marketId];
        return m.price * (10000 - m.discountBps) / 10000;
    }

    function availableCapacity(uint256 marketId) external view returns (uint256) {
        Market storage m = markets[marketId];
        return m.capacity - m.sold;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
