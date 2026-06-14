# DEX Audit Reference

## Protocol Identity

DEX contracts route swaps, manage pools, compute quotes, or maintain reserve-based pricing.

## Core Invariants

- reserve and balance accounting stay aligned
- swap execution respects slippage and deadline expectations
- liquidity shares are minted and burned fairly
- oracle or reserve-derived pricing cannot be abused through ordering gaps

## High-Risk Entry Points

- swap, route, quote-to-execute paths
- add/remove liquidity
- fee collection and reserve sync
- callback settlement and flash interactions

## Common Failure Modes

- missing slippage protection
- stale reserves or stale pool state
- price manipulation via flash liquidity or oracle coupling
- unsafe callbacks
- token decimal mismatch
- incorrect fee accounting

## High-Frequency Category Cross-Check

- flash-loan or single-block reserve manipulation
- front-running and MEV around quote-to-execute flows
- fee-on-transfer or non-standard token handling
- first-depositor or share inflation when pools or vault-like wrappers start
  near empty
- token approval issues and unsafe external calls in routers or aggregators
- stale state after swaps, syncs, or liquidity actions
- signature and replay vulnerabilities in permit or off-chain order paths

## Cross-Tag Interactions

- `DEX + Oracle`: manipulated spot inputs leak into protected decisions
- `DEX + Vault`: share pricing can inherit stale pool assumptions
