# Staking Audit Reference

## Protocol Identity

Staking contracts lock assets or voting power and distribute rewards over time or across epochs.

## Core Invariants

- stake shares and underlying balances remain aligned
- reward emission and claim accounting are monotonic and fair
- unlock or cooldown logic cannot be bypassed
- penalties and slashing affect the intended balances only

## High-Risk Entry Points

- stake and unstake
- claim rewards
- queue unlock or withdraw
- slash or emergency actions

## Common Failure Modes

- reward accounting drift
- queue or epoch boundary bugs
- rounding-based dust extraction
- cooldown bypass
- state inconsistency after slash events

## High-Frequency Category Cross-Check

- balance accounting drift between stake shares and underlying assets
- reward distribution flaws across epochs, slash events, or rebases
- withdrawal and unstaking issues that trap assets or bypass cooldown
- share price manipulation or first-depositor inflation in wrapper-style
  staking tokens
- approval or allowance vulnerabilities around reward or unstake helpers
- stale state after claim, slash, or checkpoint updates
- pause, blacklist, or emergency controls that unexpectedly block exits

## Cross-Tag Interactions

- `Staking + Governance`: voting weight may diverge from economic lock state
- `Staking + Vault`: share conversion can amplify reward or exit bugs
