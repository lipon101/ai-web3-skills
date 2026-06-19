// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MintPass is ERC20, Ownable {
    address public minter;
    uint256 public constant PASS_PRICE = 0.01 ether;

    event MinterSet(address indexed newMinter);
    event PassPurchased(address indexed buyer, uint256 amount);

    error NotMinter();
    error ZeroAddress();
    error WrongPayment(uint256 expected, uint256 sent);

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    constructor() ERC20("Mint Pass", "PASS") Ownable(msg.sender) {}

    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert ZeroAddress();
        minter = _minter;
        emit MinterSet(_minter);
    }

    function purchase(uint256 amount) external payable {
        uint256 expected = PASS_PRICE * amount;
        if (msg.value != expected) revert WrongPayment(expected, msg.value);
        _mint(msg.sender, amount * 1e18);
        emit PassPurchased(msg.sender, amount);
    }

    function mintTo(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    function withdraw() external onlyOwner {
        (bool ok,) = owner().call{value: address(this).balance}("");
        require(ok, "failed");
    }

    receive() external payable {}
}
