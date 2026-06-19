# Math And Accounting Reference

## Focus Areas

- rounding direction
- decimal normalization
- share and debt accounting
- reward distribution
- fee accrual
- first-user edge cases

## Common Failure Modes

- stale snapshots used for later checks
- asymmetric mint and burn math
- share inflation from empty-vault or first-depositor edge cases
- incorrect accrual ordering
- precision loss that benefits the attacker repeatedly
- accounting updates split across partially trusted calls

## Audit Questions

- what quantity is the true source of record
- which states must always remain in sync
- who benefits from rounding in each direction
- can a user profit by round-tripping a state transition
