# Access Control Reference

## Focus Areas

- owner, admin, operator, guardian, governor, signer roles
- initialization and one-time setup
- timelock and executor separation
- delegated privilege paths
- signature authority and replay boundaries

## Common Failure Modes

- missing or partial role checks
- role checks on one function but not the helper it calls
- privileged upgrade path bypass
- initialization takeover
- authority inferred from unsafe assumptions such as `tx.origin`

## Audit Questions

- who can call this today
- who can grant or revoke that ability
- can a temporary privilege become permanent
- can governance or upgrade flows bypass ordinary checks
