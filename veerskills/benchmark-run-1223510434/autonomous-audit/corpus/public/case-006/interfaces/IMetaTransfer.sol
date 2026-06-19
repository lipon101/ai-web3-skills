// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMetaTransfer {
    event TransferExecuted(address indexed from, address indexed to, address indexed token, uint256 amount, uint256 fee);
    event RelayerFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address indexed newRecipient);
    event TokenRegistered(address indexed token);
    event TokenDeregistered(address indexed token);

    function executeTransfer(
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    function executeTokenTransfer(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    function setRelayerFee(uint256 fee) external;
    function setFeeRecipient(address recipient) external;
    function isTokenAllowed(address token) external view returns (bool);
}
