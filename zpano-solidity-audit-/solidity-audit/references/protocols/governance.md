# Governance Audit Reference

## Protocol Identity

Governance contracts manage proposals, voting, timelocks, execution, and role transitions driven by voting power.

## Core Invariants

- proposal execution matches approved intent
- voting power is measured at the intended snapshot
- quorum and threshold rules cannot be bypassed
- privileged execution paths remain time-delayed when promised

## High-Risk Entry Points

- propose, queue, execute
- set governance parameters
- grant executor powers
- emergency or guardian override paths

## Common Failure Modes

- current-balance voting instead of snapshot-based voting
- flash-loan governance manipulation
- timelock bypass
- proposal hash ambiguity
- executor privilege escalation

## Research-Derived Cross-Check

- voting and execution allowed in the same transaction
- snapshot source tied to manipulable live balances or wrappers
- off-chain vote or permit style signatures missing nonce, expiry, or domain
  separation
- governance executor that can silently control upgrades, proxy admins, or
  bridge peers
- queue, cancel, or execute paths with stale proposal state or incorrect
  state transitions
- emergency or guardian powers that bypass promised delay or quorum rules

## Cross-Tag Interactions

- `Governance + Upgrade`: proposal execution may silently control upgrades
- `Governance + Oracle`: voting power or execution conditions may depend on manipulable prices
