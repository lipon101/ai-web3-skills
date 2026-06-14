// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC2981/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract NFTMinter is ERC721, ERC2981, Ownable {
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant MAX_PER_WALLET = 5;
    uint256 public constant PRICE = 0.05 ether;

    uint256 public totalMinted;
    bytes32 public whitelistRoot;
    bool public publicSaleOpen;
    bool public whitelistSaleOpen;
    bool public revealed;
    string public baseURI;
    string public unrevealedURI;

    mapping(address => uint256) public mintedCount;

    event WhitelistMinted(address indexed minter, uint256 amount, uint256 startId);
    event PublicMinted(address indexed minter, uint256 amount, uint256 startId);
    event SalePhaseChanged(string phase, bool open);
    event RoyaltyConfigured(address indexed receiver, uint96 feeBps);
    event Revealed(string newBaseURI);
    event Withdrawn(address indexed owner_, uint256 amount);

    error SaleClosed();
    error NotWhitelisted();
    error ExceedsSupply();
    error ExceedsWalletCap();
    error WrongPayment();
    error ZeroAmount();
    error AlreadyRevealed();

    constructor(string memory _unrevealedURI)
        ERC721("MyNFT", "MNFT")
        Ownable(msg.sender)
    {
        unrevealedURI = _unrevealedURI;
    }

    function setWhitelistRoot(bytes32 root) external onlyOwner {
        whitelistRoot = root;
    }

    function setPublicSaleOpen(bool open) external onlyOwner {
        publicSaleOpen = open;
        emit SalePhaseChanged("public", open);
    }

    function setWhitelistSaleOpen(bool open) external onlyOwner {
        whitelistSaleOpen = open;
        emit SalePhaseChanged("whitelist", open);
    }

    function setRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        _setDefaultRoyalty(receiver, feeBps);
        emit RoyaltyConfigured(receiver, feeBps);
    }

    function reveal(string calldata newBaseURI) external onlyOwner {
        if (revealed) revert AlreadyRevealed();
        revealed = true;
        baseURI = newBaseURI;
        emit Revealed(newBaseURI);
    }

    function whitelistMint(uint256 amount, bytes32[] calldata proof) external payable {
        if (!whitelistSaleOpen) revert SaleClosed();
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(proof, whitelistRoot, leaf)) revert NotWhitelisted();
        _mintChecked(amount);
        emit WhitelistMinted(msg.sender, amount, totalMinted - amount);
    }

    function publicMint(uint256 amount) external payable {
        if (!publicSaleOpen) revert SaleClosed();
        _mintChecked(amount);
        emit PublicMinted(msg.sender, amount, totalMinted - amount);
    }

    function _mintChecked(uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        if (totalMinted + amount > MAX_SUPPLY) revert ExceedsSupply();
        if (mintedCount[msg.sender] + amount > MAX_PER_WALLET) revert ExceedsWalletCap();
        if (msg.value != PRICE * amount) revert WrongPayment();
        mintedCount[msg.sender] += amount;
        uint256 startId = totalMinted;
        totalMinted += amount;
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, startId + i);
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (!revealed) return unrevealedURI;
        return string(abi.encodePacked(baseURI, _toString(tokenId), ".json"));
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool ok,) = owner().call{value: balance}("");
        require(ok, "failed");
        emit Withdrawn(owner(), balance);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
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
