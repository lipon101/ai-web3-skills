# Bridge Audit Reference

## Protocol Identity

Bridge contracts move value or messages across domains using proof verification, message uniqueness, and controlled settlement.

## Core Invariants

- a valid message is processed once
- source and destination domain assumptions are explicit
- mint, burn, lock, and release operations stay consistent across domains
- rate limits and emergency controls bound damage
- assets custodied for one user cannot be moved by another user's bridge payload
- bridge execution cannot use arbitrary call data to exercise unrelated contract authority

## High-Risk Entry Points

- receive message
- verify proof
- process deposit or withdrawal
- mint or release funds
- configure remote peers or verifiers
- claim paths that both release funds and execute arbitrary bridge payloads
- ticket or NFT custody managers that hold assets on behalf of multiple users

## Common Failure Modes

- cross-chain replay
- chain ID confusion
- nonce or message uniqueness gaps
- verifier trust boundary mismatch
- funds locked due to settlement inconsistency
- unsafe token handling on remote settlement
- arbitrary call target or calldata controlling custodied assets
- approval-plus-call patterns that let the bridge payload escape its intended asset scope
- live price or fee reads in bridge helpers when the core protocol uses round snapshots

## High-Frequency Category Cross-Check

- access control misconfiguration around peers, verifiers, executors, or
  rate-limit roles
- external call injection in receive, claim, or settlement payloads
- funds locked by partial settlement or inconsistent mint, burn, lock, and
  release bookkeeping
- gas-limit or execution-budget failure on delivery, proving, or callback
  completion
- initialization and upgrade flaws around verifier or peer configuration
- non-standard token and native ETH handling on both sides of settlement
- state update inconsistency between message consumption and value movement

## Cross-Tag Interactions

- `Bridge + Vault`: share accounting may not survive asynchronous settlement
- `Bridge + Governance`: remote control paths can bypass local trust assumptions
- `Bridge + Generic`: helper managers may custody unrelated user assets while executing bridge payloads
