# Active Lifecycle Mutability Rules

## Goal

Detect when a protocol promises that current state is fixed, but implementation still reads mutable globals or replaceable dependencies during an active lifecycle.

## Active Lifecycle Windows

Treat these as sensitive windows:

- active draw
- active epoch
- active auction
- post-lock pre-settlement
- pending callback
- unclaimed winnings period
- emergency refund period

## Mandatory Checks

### 1. Mutable Global Variables

List every global variable that can affect:

- pricing
- payout
- fee extraction
- refund amount
- collateral checks
- reward distribution
- timing or scheduling

Then verify whether current lifecycle logic reads:

- a snapshotted per-round value
- or the live mutable global

### 2. Replaceable Dependencies

List every external dependency that can be swapped:

- entropy provider
- payout calculator
- oracle source
- bridge verifier
- executor
- strategy

Then verify whether active lifecycle logic assumes the dependency is immutable.

### 3. Claim-Time Drift

Check whether claim, refund, or settlement logic uses:

- purchase-time values
- round-time values
- or current live values

### 4. Future-Only Promise Validation

If docs, comments, or product assumptions say a change applies only to future rounds, verify that claim in code.

## High-Risk Patterns

- bridge manager charges using a live global while core logic uses a round snapshot
- callback after lock reads a freshly replaceable dependency
- claim or refund reads a global fee that was not snapshotted at purchase time
- settlement reads a live calculator or provider that can be replaced mid-lifecycle

## Output Expectations

A valid finding should name:

- the mutable variable or dependency
- the active lifecycle window
- the expected snapshot boundary
- the actual live read path
- the user or protocol impact
