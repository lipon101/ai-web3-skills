# Threat-Model-First Stage 1 Methodology (NEW v0.4.0)

Stage 1 reads this file before producing the 6 Stage-1 artifacts. v0.4.0 reorganizes Stage 1 so the **threat model drives** the entry-point and attack-surface enumeration — not the other way around. Without this discipline, Stage 1 produces a feature catalogue (an index of `pub fn`s) that Stage 2 has to re-derive a threat model from. With it, Stage 1 hands Stage 2 a target-aware threat surface.

## The order of operations (mandatory)

Stage 1 MUST execute steps 1-3 BEFORE steps 4-6:

| # | Step | Output |
|---|------|--------|
| 1 | **Identify actors** (who participates in the system, with what trust level) | `trust-model.md` § Actors |
| 2 | **Identify trust boundaries** (where attacker-controlled data crosses into the protected core) | `trust-model.md` § Trust boundaries + `attack-surface.md` § Trust-boundary index |
| 3 | **Walk the 10-point attack-surface checklist** (OpenZeppelin-aligned, Argus depth discipline) against the codebase | `attack-surface.md` § 10-point walk |
| 4 | Enumerate entry points (filtered against the surface from step 3) | `entry-points.md` |
| 5 | Extract invariants (anchored to actors + boundaries from steps 1-2) | `invariants.md` |
| 6 | Compose `overview.md` + rank `hot-zones.md` (weighted by surface exposure from step 3) | `overview.md`, `hot-zones.md` |

Stage 1 that runs in legacy 4-then-1-2 order (entry points first, threat model retrofitted) is **rejected** by Stage 2's pre-check.

## Step 1 — Actors

Enumerate every party that interacts with the system. Each actor gets:

```yaml
actor:
  name: <Authority | LP | Borrower | Validator | Sequencer | Keeper | RPC client | Peer | Block proposer | ...>
  trust_level: TRUSTED | SEMI-TRUSTED | UNTRUSTED
  capabilities: [<one-line capability>, ...]
  invocation_path: <CLI | RPC | on-chain tx | gossip | sysvar | environment | direct memory>
  rate_limit: <permissionless | per-stake | per-key | timelocked | ...>
  economic_friction: <free | gas-bound | stake-bound | bonded | ...>
```

Actors that do not appear in the source code do not exist for this audit. "Hypothetical malicious user" is not an actor; "Untrusted signer of `instruction.accounts[0]`" is.

## Step 2 — Trust boundaries

For each crossing from a lower-trust to a higher-trust zone, name the boundary:

```yaml
boundary:
  name: <e.g., "Borsh decode of instruction data" | "RPC-handler entry from network" | "CPI to external program">
  lower_trust: <actor or surface name from step 1>
  higher_trust: <component / module / state>
  enforcement_mechanism: <`#[account(...)]` constraint | `Signer<'info>` | manual key-check | sysvar check | match arm | type discriminant | ...>
  data_that_crosses: <instruction data | account data | network bytes | CLI flags | ...>
  bypass_if_missing: <one-sentence description of what the boundary prevents>
```

Boundaries without a named `enforcement_mechanism` are **gaps**, not boundaries — file as candidate hot zone.

## Step 3 — The 10-point attack-surface walk

Walk every item below against the in-scope source. Each point gets a §-subsection in `attack-surface.md` with one or more concrete code citations or an explicit "n/a — <reason>". The 10-point list is the Argus depth discipline for L1 / Anchor / Solana surface enumeration.

### 1. Access control

For Anchor: every `#[derive(Accounts)]` struct's signer / owner / has_one / constraint set.
For Solana-native: every `accounts.iter().next()` and the implicit positional contract.
For CosmWasm: `info.sender` checks in every `ExecuteMsg` arm.
For Substrate: `ensure_root!` / `ensure_signed!` / `T::EnsureOrigin` impls.
For Rust infra services: capability tokens, RBAC tables, ACL maps.

Cite: `<file:line>` for the gate that protects each privileged path. List paths with NO gate as candidate findings.

### 2. Input validation

External byte streams: instruction data, account data, network packets, CLI arg parsing, environment variables, file IO from untrusted paths.

For each decoder/parser, record:
- which decoder type (`try_from_slice` / `BorshDeserialize::deserialize` / `bincode::deserialize` / `serde_json::from_slice` / hand-rolled).
- whether bounds are enforced (length prefixes, max-size caps).
- whether the decoder can panic on malformed input.

### 3. Authentication

For each entry point, the authentication ceremony: `Signer<'info>`, `#[account(signer)]`, ed25519 verification, PDA seed validation, `recent_blockhash` recency, validator-set membership for consensus messages, TLS / handshake completion.

Cite the line that performs the auth check. List entry points that skip authentication explicitly.

### 4. Authorization

After authentication: what is the authenticated identity allowed to do? Role pubkeys, owner-of-record checks, program-id whitelists, AccountInfo.owner equality, capability discriminants.

### 5. State management

State transitions: which writes happen in which order, what invariants are checked before/after, what happens on partial failure.

For Anchor: account-data invariants (`balance >= 0`, `total_supply == sum_of_shares`).
For storage state machines: epoch boundaries, finality flags, restart-safe persistence.
For consensus state: vote duplication prevention, equivocation detection, slot monotonicity.

### 6. Token handling

SPL Token CPIs, mint authority, transfer authority, Token-2022 extensions (transfer hook, transfer fee, confidential transfer).
CW20 / CW721 message dispatch.
Substrate `pallet-assets` / `Currency` trait usage.
Native lamport / coin transfers via `**lamports.borrow_mut() -= …`.

### 7. External calls

CPI graph: every `invoke` / `invoke_signed` / `solana_program::program::invoke_*` site.
CosmWasm: every `WasmMsg::Execute` / `WasmMsg::Instantiate`.
Substrate: every `dispatch` / `T::Call` boundary.
Rust infra: trait-object dispatch (`Box<dyn Trait>`), FFI (`extern "C"`), plugin systems (`libloading`), subprocess (`Command::new`).

For each external call, name the trust assumption: "Strategy reports correct gain", "Oracle returns fresh price", etc.

### 8. Cryptographic operations

Domain separation in hash preimages (HashTag, Personalization, prefix).
Canonical serialization for signing (Borsh canonical, scale-codec canonical).
Signature scheme choice (ed25519 vs secp256k1, multi-sig schemes).
PDA seed-space disjointness.
Randomness source provenance (`Clock::slot_hash`, oracle randomness, VDF output).

Rule (Argus L1 core invariant): hashes/signatures require **explicit** domain separation, versioning, and canonical serialization. Any hash construction that lacks a domain-separating prefix → candidate hot zone.

### 9. Time / randomness

`Clock` sysvar reads (`slot`, `unix_timestamp`, `epoch`).
Block timestamp monotonicity assumptions.
Validator-clock skew tolerance.
`recent_blockhash` usage for "randomness" (anti-pattern).
Per-iteration deadline / timeout enforcement.

### 10. Economic incentives

Priority fee handling.
Compute-unit budgets.
Account-write-lock contention (Solana-specific MEV surface).
Mempool fee-market gaming (DLT infra).
Validator-reward math precision.
Slashing/bonding mechanics.
Fee burn vs fee distribution invariants.

## Step 4 — Entry points (now informed by surface)

After steps 1-3, the entry-point table in `entry-points.md` is filtered: each entry's listing must cite which boundary (step 2) it crosses and which surface points (step 3) it touches. Entry points that touch no surface points are **out of audit scope** — list them in an appendix section, do not detail them.

## Step 5 — Invariants (anchored to actors + boundaries)

Each invariant in `invariants.md` carries:

```yaml
invariant:
  statement: "<one-sentence assertion>"
  source: <doc-stated | code-extracted | inferred>
  actor_that_could_violate: <actor name from step 1, or "none — structural">
  boundary_that_enforces: <boundary name from step 2, or "none — implicit">
  consequences_if_broken: <one sentence>
```

Invariants without a named `actor_that_could_violate` are not security-relevant — move to a "design constraints" appendix.

## Step 6 — Hot zones (surface-weighted)

`hot-zones.md` ranks modules by:

```
hot_zone_score = (surface_points_touched × 2)
               + (boundaries_crossed × 3)
               + (untrusted_actors_reaching × 2)
               + (untested_lines × 0.01)
               + (recent_git_churn × 0.05)
```

The legacy v0.3.x scoring (churn + untested-lines only) is deprecated. Stage 1 records the score per zone for traceability.

## Skip conditions

There are none. Every Stage 1 run executes all 10 points. Points that genuinely do not apply (e.g., point 6 for a project with no token handling) are recorded as `n/a — <one-sentence reason>` so the audit trail proves the point was considered.

## Why this matters

Without the threat-model-first discipline, Stage 1 produces a feature index. Stage 2 angles each re-derive their own private threat model from that index, leading to:

- Surface points missed by every angle (because each angle covers its own slice).
- Inconsistent severity baselines across angles (because each angle has a different mental threat model).
- Stage 4 Pass A having to do trust-model archaeology after the fact.

v0.4.0 reorganization is calibrated against early L1 audit runs that produced exactly this failure mode (feature-index Stage 1 + Stage-2-private-threat-models). The 10-point walk resolves it.

## Cross-references

- `references/stage1-output-templates.md` — the 6 file templates (each cites this file)
- `references/rust-protocol-types.md` — protocol-shape profile (informs which surface points are heaviest)
- `references/hacking-agents/shared-rules.md` § Mandatory analysis checks — Stage 2 reuses the surface inventory for its `cross_domain_deps` check
