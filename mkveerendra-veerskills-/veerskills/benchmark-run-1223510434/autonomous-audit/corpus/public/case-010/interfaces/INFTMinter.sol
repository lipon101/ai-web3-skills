// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INFTMinter {
    event WhitelistMinted(address indexed minter, uint256 amount, uint256 startId);
    event PublicMinted(address indexed minter, uint256 amount, uint256 startId);
    event SalePhaseChanged(string phase, bool open);
    event RoyaltyConfigured(address indexed receiver, uint96 feeBps);
    event Revealed(string baseURI);
    event Withdrawn(address indexed owner, uint256 amount);

    function whitelistMint(uint256 amount, bytes32[] calldata proof) external payable;
    function publicMint(uint256 amount) external payable;
    function setWhitelistRoot(bytes32 root) external;
    function setWhitelistSaleOpen(bool open) external;
    function setPublicSaleOpen(bool open) external;
    function setRoyalty(address receiver, uint96 feeBps) external;
    function reveal(string calldata baseURI) external;
    function withdraw() external;
}
