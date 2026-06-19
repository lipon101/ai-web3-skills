# Oracle Audit Reference

## Protocol Identity

Oracle contracts publish, aggregate, normalize, or validate external data used by economic or governance logic.

## Core Invariants

- data freshness assumptions are enforced
- units and decimals are normalized correctly
- fallback logic is safe and bounded
- price consumers cannot mistake stale or invalid data for current truth

## High-Risk Entry Points

- publish or update price
- read normalized price
- configure source or heartbeat
- choose fallback or aggregation strategy

## Common Failure Modes

- stale price acceptance
- unit normalization errors
- unsafe fallback choice
- price manipulation through narrow observation windows
- inconsistent price use across dependent modules

## High-Frequency Category Cross-Check

- incorrect decimal normalization between feeds and consumers
- invalid round, version, or completeness handling
- reserve-derived or AMM-derived prices used without manipulation resistance
- TWAP miscalculation or asymmetric TWAP enforcement
- unchecked external call return values from oracle adapters
- stale oracle price data accepted because heartbeat assumptions are wrong
- missing access control on source, heartbeat, or fallback configuration

## Cross-Tag Interactions

- `Oracle + Lending`: stale or manipulated prices break liquidation safety
- `Oracle + DEX`: spot-derived values can be attacker-controlled
