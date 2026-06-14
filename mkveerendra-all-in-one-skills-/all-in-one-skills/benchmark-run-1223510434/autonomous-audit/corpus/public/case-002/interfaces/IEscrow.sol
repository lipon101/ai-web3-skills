// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEscrow {
    event Created(uint256 indexed id, address depositor, address recipient, uint256 releaseBlock);
    event Released(uint256 indexed id);
    event Refunded(uint256 indexed id);
    event DisputeRaised(uint256 indexed id, address indexed initiator);
    event DisputeResolved(uint256 indexed id, bool releasedToRecipient);

    function create(address payable recipient, uint256 releaseBlock) external payable returns (uint256 id);
    function release(uint256 id) external;
    function refund(uint256 id) external;
    function raiseDispute(uint256 id) external;
    function resolveDispute(uint256 id, bool releaseToRecipient) external;
    function escrowCount() external view returns (uint256);
}
