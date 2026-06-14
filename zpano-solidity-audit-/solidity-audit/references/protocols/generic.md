# Generic Protocol Reference

## Use Case

Use this label for important contracts that do not fit a specialized protocol type but still affect trust, funds, permissions, or critical state.

## Core Invariants

- trust boundaries are explicit
- privileged changes are bounded
- configuration cannot silently invalidate safety assumptions
- helpers and registries cannot corrupt downstream protocol logic
- active lifecycle logic must not read live mutable values when a round-local snapshot is expected
- callback or helper contracts must remain safe even when they custody third-party assets

## Priority Checks

- access control
- initialization and upgrade paths
- registry integrity
- unsafe external call assumptions
- critical config mutation
- mutable dependency replacement during active lifecycle windows
- callback feasibility and liveness on realistic gas budgets

## High-Frequency Category Cross-Check

- router-style arbitrary calldata execution against existing approvals
- selector mismatch or unsafe interface casts on external dependencies
- hidden custody surfaces in helpers, managers, and adapters
- proxy initialization or deployment sequencing gaps
- stale approvals that survive migration or cancellation
- compiler or version-sensitive assumptions that make the source-level guard
  misleading
