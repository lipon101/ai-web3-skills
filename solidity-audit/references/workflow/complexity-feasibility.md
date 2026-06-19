# Complexity And Feasibility Rules

## Goal

Identify paths that are logically correct in isolation but fail in practice because they cannot be executed within realistic chain, keeper, or callback limits.

## Reportable Cases

Report complexity or gas findings when they can break:

- settlement
- callback completion
- liquidation
- withdrawals
- governance execution
- message delivery
- queue processing
- other liveness-critical invariants

Do not report micro-optimizations.

## Mandatory Checks

### 1. Critical Path Enumeration

Always inspect:

- settlement callbacks
- draw finalization
- winner counting
- liquidation loops
- queue processing
- batched claims
- proof verification and bridge execution

### 2. Growth Driver Analysis

For each critical path, identify which variables scale work:

- user count
- ticket count
- subset count
- bonusball range
- array length
- module size
- strategy count
- validator count

### 3. Budget Comparison

Compare estimated work against:

- target chain block gas limits
- per-transaction gas limits
- keeper or provider callback constraints
- hardcoded protocol gas caps

### 4. Asynchronous Callback Feasibility

For oracle, entropy, bridge, and keeper callbacks:

- check whether the callback gas is bounded
- check whether user or admin actions can push the callback above feasible limits
- check whether a failed callback leaves the protocol permanently locked or partially progressed

## Heuristics

- Nested loops over dynamic domains are high risk.
- Combinatorics and subset enumeration are high risk even when inputs are bounded.
- Any formula that converts pool size into callback gas or iteration count must be treated as adversarially steerable.
- A liveness break can be medium or high severity even without direct theft.

## Output Expectations

A valid finding should name:

- the critical path
- the scaling variable
- the realistic execution ceiling
- the resulting broken invariant or locked lifecycle
