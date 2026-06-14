# Vault Audit Reference

## Protocol Identity

Vault contracts accept assets, mint shares, manage withdrawals, and may allocate funds to strategies.

## Core Invariants

- asset/share conversion is economically consistent
- deposits and withdrawals preserve total accounting integrity
- strategy gains and losses are reflected correctly
- withdrawal queues and fee paths cannot strand value

## High-Risk Entry Points

- deposit, mint, withdraw, redeem
- harvest, report, rebalance
- set fee or strategy
- process queued withdrawals

## Common Failure Modes

- first-depositor or empty-vault inflation
- asymmetric rounding on deposit and redeem
- stale total assets or strategy value
- withdrawal queue denial of service
- fee accounting leakage

## High-Frequency Category Cross-Check

- stale cached state or state update ordering errors between strategy reports
  and user actions
- oracle or price manipulation through vault donation, LP pricing, or stale
  strategy valuations
- unsafe token approvals and unsafe ERC20 handling in strategy interactions
- reward or fee accounting manipulation across harvest and rebalance flows
- locked or irretrievable funds in queues, rescue paths, or emergency exits
- upgradeability or storage-gap flaws in upgradeable vault deployments
- callback-token reentrancy during deposit, withdraw, or strategy execution

## Cross-Tag Interactions

- `Vault + Lending`: collateral valuation may depend on stale share pricing
- `Vault + Bridge`: delayed settlement can desynchronize share accounting
