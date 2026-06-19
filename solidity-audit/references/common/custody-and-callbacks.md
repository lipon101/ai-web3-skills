# Custody And Callbacks Reference

## Use Case

Apply this reference whenever a contract:

- custodies ERC20, ERC721, ERC1155, bridge receipts, tickets, or claim balances for multiple users
- grants approvals before external execution
- executes user-controlled call targets or calldata
- dispatches callbacks while privileged state or custodied assets remain live

## Core Invariants

- one user's external execution must not affect another user's custodied assets
- approvals must stay scoped to the intended asset and amount
- callback execution must not bypass custody or authorization boundaries
- local ownership bookkeeping must stay aligned with actual asset custody

## High-Risk Patterns

- `approve -> arbitrary call`
- `custody -> callback -> transferFrom`
- arbitrary external call while the contract still holds unrelated user assets
- local `ticketOwner` or receipt bookkeeping that is weaker than actual asset ownership
- receiver hooks or callback hooks that run before state fully settles

## Audit Questions

- what third-party assets are currently custodied by this contract
- can a user-controlled target consume approvals or move assets outside the intended scope
- can a callback chain reach transfer or approval state for assets belonging to another user
- does the contract behave like a hidden custodian even if named manager, helper, or bridge
