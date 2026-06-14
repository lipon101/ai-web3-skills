# Lending Audit Reference

## Protocol Identity

Lending contracts manage collateral, debt, utilization, interest accrual, and liquidation.

## Core Invariants

- solvency and health checks reflect current economic state
- debt and collateral accounting remain synchronized
- liquidation rules preserve protocol safety margins
- interest accrual updates happen before dependent checks

## High-Risk Entry Points

- deposit collateral
- borrow, repay
- liquidate
- accrue interest
- set oracle or risk parameters

## Common Failure Modes

- stale health factor checks
- liquidation ordering bugs
- interest accrual mismatch
- bad debt creation or hidden insolvency
- precision loss in borrow or repay share math
- unsafe oracle assumptions

## High-Frequency Category Cross-Check

- accounting share mismatch between debt shares, asset balances, and treasury
  fees
- bad debt or hidden insolvency after partial liquidation or stale accrual
- interest rate or interest accrual update ordering bugs
- external protocol integration assumptions in adapters, wrappers, or
  collateral managers
- position health checks using stale prices, stale totals, or post-action
  state
- locked funds from withdrawal, liquidation, or rescue edge cases
- vault share inflation when vault-like collateral is accepted directly

## Cross-Tag Interactions

- `Lending + Oracle`: stale or manipulated prices break solvency checks
- `Lending + Vault`: share pricing and collateral value assumptions interact
