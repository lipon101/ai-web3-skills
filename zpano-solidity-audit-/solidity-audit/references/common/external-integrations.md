# External Integrations Reference

## Focus Areas

- ERC20 and ERC4626 assumptions
- callbacks and reentrancy surfaces, including ERC721, ERC777, and ERC1155
  hooks
- oracle reads
- bridge or cross-domain messaging
- external strategy or router interactions
- custodied tokens, NFTs, allowances, and execution authority
- user-controlled external call targets or calldata
- interface signature mismatches and unsafe type casts
- spender migrations that leave stale approvals alive

## Common Failure Modes

- assuming standard ERC20 behavior
- stale external state read before settlement
- reentrancy through callbacks or token hooks
- trusting external return data without validation
- broken assumptions about chain IDs, message uniqueness, or freshness
- arbitrary external calls while the contract custodies third-party assets
- granting approvals before calling untrusted targets
- capability leakage where a payload can move unrelated custodied assets
- interface mismatches that silently dispatch to fallback or attacker code
- stale approvals surviving cancellation, migration, or spender replacement

## Audit Questions

- what external system is trusted here
- what happens if that system is stale, malicious, paused, or non-standard
- are external effects observed before local accounting settles
- can a user-controlled call target reach token, NFT, or approval state the caller should not control
- does this contract hold assets for multiple users while also executing arbitrary external calls
- does the interface used for an external dependency actually match the
  deployed selector surface
