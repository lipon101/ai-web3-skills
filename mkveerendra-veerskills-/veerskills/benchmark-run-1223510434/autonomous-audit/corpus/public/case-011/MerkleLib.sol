// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library MerkleLib {
    function verify(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 hash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 el = proof[i];
            hash = hash <= el
                ? keccak256(abi.encodePacked(hash, el))
                : keccak256(abi.encodePacked(el, hash));
        }
        return hash == root;
    }

    function processProof(
        bytes32[] calldata proof,
        bytes32 leaf
    ) internal pure returns (bytes32 computedHash) {
        computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            computedHash = computedHash <= proofElement
                ? keccak256(abi.encodePacked(computedHash, proofElement))
                : keccak256(abi.encodePacked(proofElement, computedHash));
        }
    }

    function leafHash(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount));
    }

    function doubleLeafHash(address account, uint256 windowId, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, windowId, amount));
    }
}
