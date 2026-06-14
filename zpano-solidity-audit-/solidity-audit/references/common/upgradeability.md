# Upgradeability Reference

## Focus Areas

- proxy patterns
- initializer safety
- implementation takeover risk
- upgrade authorization
- storage layout compatibility
- deployment sequencing and atomic initialization
- re-initialization risk after upgrades

## Common Failure Modes

- unprotected initializer
- upgrade path bypassing governance or timelock
- storage collision or layout drift
- implementation contract left claimable
- emergency upgrade powers inconsistent with trust assumptions
- non-atomic proxy deployment that leaves a mempool-visible initialization
  window
- re-initialization after upgrade resets critical trust assumptions
- missing authorization on UUPS `_authorizeUpgrade`

## Audit Questions

- who can upgrade
- can implementation or admin addresses be changed unexpectedly
- can initialization be replayed or front-run
- does proxy deployment pass initialization data atomically
- are post-upgrade storage and initialization assumptions re-verified
