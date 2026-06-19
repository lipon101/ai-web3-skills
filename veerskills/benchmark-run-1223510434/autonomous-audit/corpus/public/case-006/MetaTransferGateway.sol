// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./TokenRegistry.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MetaTransferGateway {
    using ECDSA for bytes32;

    TokenRegistry public tokenRegistry;
    IERC20 public token;
    address public admin;
    address public relayerFeeRecipient;
    uint256 public relayerFee = 1e16;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 private constant TRANSFER_TYPEHASH = keccak256(
        "Transfer(address from,address to,uint256 amount,uint256 deadline)"
    );

    event TransferExecuted(address indexed from, address indexed to, uint256 amount, uint256 fee);
    event TokenTransferExecuted(address indexed token_, address indexed from, address indexed to, uint256 amount);
    event RelayerFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address indexed newRecipient);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    error NotAdmin();
    error Expired();
    error InvalidSignature();
    error TokenNotAllowed();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(address _token, address _feeRecipient, address _tokenRegistry) {
        if (_token == address(0) || _feeRecipient == address(0)) revert ZeroAddress();
        token = IERC20(_token);
        relayerFeeRecipient = _feeRecipient;
        admin = msg.sender;
        tokenRegistry = TokenRegistry(_tokenRegistry);
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("MetaTransferGateway")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function setRelayerFee(uint256 fee) external onlyAdmin {
        relayerFee = fee;
        emit RelayerFeeUpdated(fee);
    }

    function setFeeRecipient(address recipient) external onlyAdmin {
        if (recipient == address(0)) revert ZeroAddress();
        relayerFeeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    function executeTransfer(
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(block.timestamp <= deadline, "expired");

        bytes32 digest = keccak256(abi.encodePacked(from, to, amount, deadline));
        address signer = digest.toEthSignedMessageHash().recover(signature);
        require(signer == from, "invalid signature");

        token.transferFrom(from, to, amount - relayerFee);
        token.transferFrom(from, relayerFeeRecipient, relayerFee);
        emit TransferExecuted(from, to, amount - relayerFee, relayerFee);
    }

    function executeTokenTransfer(
        address tokenAddr,
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (!tokenRegistry.isAllowed(tokenAddr)) revert TokenNotAllowed();
        if (block.timestamp > deadline) revert Expired();
        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, from, to, amount, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = digest.recover(signature);
        if (signer != from) revert InvalidSignature();
        IERC20(tokenAddr).transferFrom(from, to, amount);
        emit TokenTransferExecuted(tokenAddr, from, to, amount);
    }

    function isTokenAllowed(address tokenAddr) external view returns (bool) {
        return tokenRegistry.isAllowed(tokenAddr);
    }
}
