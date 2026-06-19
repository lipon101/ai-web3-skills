// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BondToken is ERC20, Ownable {
    uint256 public immutable marketId;
    address public immutable bondMarket;
    bool public redeemable;

    event RedeemableSet(bool status);

    error NotBondMarket();
    error NotRedeemable();

    modifier onlyBondMarket() {
        if (msg.sender != bondMarket) revert NotBondMarket();
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        uint256 _marketId,
        address _bondMarket
    ) ERC20(name, symbol) Ownable(msg.sender) {
        marketId = _marketId;
        bondMarket = _bondMarket;
    }

    function mint(address to, uint256 amount) external onlyBondMarket {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyBondMarket {
        _burn(from, amount);
    }

    function setRedeemable(bool status) external onlyOwner {
        redeemable = status;
        emit RedeemableSet(status);
    }

    function totalBondsIssued() external view returns (uint256) {
        return totalSupply();
    }
}
