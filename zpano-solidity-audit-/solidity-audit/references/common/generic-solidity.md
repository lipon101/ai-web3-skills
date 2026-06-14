# Generic Solidity Audit Reference

## Core Invariants

- privileged actions are constrained to the intended trust boundary
- accounting state remains internally consistent across all state transitions
- external calls cannot invalidate local assumptions
- initialization and upgrade state cannot be hijacked

## Primary Checks

- unsafe ownership or role transitions
- missing initialization guards
- storage layout or upgrade assumptions
- unsafe external calls and unchecked return values
- state update ordering around asset movement
- hidden trust assumptions in helper or registry contracts

## Cross-Check

Before declaring a generic surface safe, map it against
`references/common/vulnerability-taxonomy.md`, especially for:

- stale approvals and router calldata abuse
- hidden callbacks and reentrancy entry points
- selector mismatch and unsafe interface assumptions
- deployment-sequencing and proxy-initialization risk

## Review Order

1. external entry points
2. privileged state transitions
3. asset movement and accounting updates
4. initialization and upgrade paths
