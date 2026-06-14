// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library SignatureValidator {
    using ECDSA for bytes32;

    function recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        return digest.toEthSignedMessageHash().recover(signature);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, chainId, verifyingContract));
    }

    function isValidSignatureNow(
        address signer,
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (bool) {
        return recoverSigner(digest, signature) == signer;
    }

    function splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "invalid sig length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
