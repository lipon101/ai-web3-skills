# Stage 1 Output Templates

Concrete templates for the 6 files Stage 1 writes under `$RUN_DIR/1-protocol-map/`. Read this at Stage 1 start (alongside `pipeline-overview.md`, [`threat-model-first.md`](threat-model-first.md), and `rust-protocol-types.md`).

**v0.4.0 Threat-Model-First order**: actors → boundaries → 10-point surface walk → entry points → invariants → hot zones. The templates below assume the threat-model artifacts (`trust-model.md`, `attack-surface.md` §10-point) are filled FIRST; `entry-points.md` / `invariants.md` / `hot-zones.md` cite them.

These templates are written for Rust ecosystems (Solana / Anchor, CosmWasm, Substrate, generic Rust). Prose discipline mirrors X-Ray's `templates.md`:

- **Bullet brevity rule**: one tight sentence per bullet, one line ideally, max two. Don't restate what `file:line` already shows. The code reference carries the evidence; prose must not duplicate it.
- **DO-NOT-EXPLOIT rule**: Stage 1 names *concern areas*, not specific exploits. "Worth checking…" / "Worth tracing…" — let Stage 2 finish the sentence. If your bullet contains "→ attacker drains X" or "→ user trapped", cut it.

---

## 1. `overview.md` — what this protocol does in 200 lines max

```markdown
# Protocol Overview

> [Project Name] | [crate count] crates | [total nSLOC] nSLOC | [git short-hash] (`[branch]`) | [project shape: anchor | cosmwasm | substrate | generic-rust] | [DD/MM/YY]

**What it does:** [One sentence — the core mechanism.]

- **Users**: [Who interacts and why]
- **Core flow**: [The main user-facing operation in one bullet]
- **Key mechanism**: [AMM type, vault model, lending model, oracle design, etc.]
- **Token model**: [SPL mints, CW20 contracts, pallet-assets — what tokens exist and their roles]
- **Authority model**: [Anchor `program_upgrade_authority`, CosmWasm admin, Substrate Origin — who controls what]

[No paragraphs. No fluff. Keep vendor-neutral — no audit-platform or bounty-program framing.]

## Crates in scope

| Subsystem | Key Crates / Modules | nSLOC | Role |
|-----------|----------------------|------:|------|
| [subsystem] | [crate1, crate2, ...] | [total] | [one-line role] |

[Group by subsystem — one row per subsystem, not per file. List key crates / modules.]

## Backwards-compatibility code

[Include this subsection ONLY if backwards-compatibility remnants identified. Omit entirely if none found.]

- `[crate::module::function or const]` — [what it was part of, why retained, that it is not active functionality]

## How it fits together

[Start with "The core trick:" — one sentence explaining the protocol's fundamental mechanism.]

[Then show 3-5 key flows as annotated code-block diagrams. Each flow:]
[1. ### subheading (no numbering — order is self-evident)]
[2. Code block showing the call chain with tree-style branching (├─ └─)]
[3. Italic annotations on critical steps (where state changes, where CPI fires, where payment is verified)]
[Keep it to the 3-5 MOST IMPORTANT flows. Skip governance / admin / oracle flows — those are in trust-model.md and attack-surface.md.]

[IMPORTANT: Use concrete crate / module names, NOT trait names. Write `vault::deposit::deposit_handler()`, not `Deposit::handle()`. The auditor needs to know which actual function executes.]

[Focus on flows that span multiple crates / modules — these are where integration bugs hide.]
```

---

## 2. `attack-surface.md` — entry points + trust boundaries (per-finding-relevant)

```markdown
# Attack Surface

> [Project Name] | [N] entry points | [N] permissionless | [N] role-gated | [N] privileged | [git short-hash] (`[branch]`)

## Trust-boundary index (v0.4.0 — MANDATORY, before entry-point classification)

[List every boundary identified in threat-model-first.md § Step 2. One row per boundary.]

| Boundary | Lower-trust source | Higher-trust target | Enforcement | Data crossing |
|----------|--------------------|--------------------|-----------------|---------------|
| [name] | [actor or surface] | [module/state] | `<file:line>` of the gate | [bytes / structs / params] |

## 10-point attack-surface walk (v0.4.0 — MANDATORY)

[Walk all 10 surface points from threat-model-first.md § Step 3. Each subsection: code citations or explicit "n/a — <reason>".]

### 1. Access control
- `<file:line>` — [gate description]
- [or: "n/a — <reason>"]

### 2. Input validation
- [decoder type] at `<file:line>` — bounds enforced: yes/no; panic-on-malformed: yes/no

### 3. Authentication
[…]

### 4. Authorization
[…]

### 5. State management
[…]

### 6. Token handling
[…]

### 7. External calls
[…]

### 8. Cryptographic operations
[…]

### 9. Time / randomness
[…]

### 10. Economic incentives
[…]

## Entry-point classification

| Class | Count | Notes |
|-------|------:|-------|
| Permissionless | [N] | Callable by any signer / any origin |
| Role-gated | [N] | Requires a specific signer / authority / origin |
| Privileged | [N] | Admin / DAO / `ensure_root` |
| Initialization | [N] | One-time deployment / `init` / `instantiate` |

## Permissionless entry points

[Sort by value flow: tokens-in first, tokens-out second, no-token-movement last. For each, write one-line concern bullet citing `crate::module::function` and what's worth checking.]

- **`crate::module::function`** — [params + auth gate] — [what's worth checking, max 2 lines]

## Role-gated entry points

[Group by role. Within each role, sort by value flow.]

### Role: [authority / `OWNER` / `T::EnsureOrigin` impl name]

- **`crate::module::function`** — [params + auth check] — [what's worth checking]

## Privileged entry points

[Compact table for admin / `ensure_root` / DAO functions — all in one place.]

| Crate::Function | Parameters | State Modified | Timelock? |
|-----------------|------------|----------------|-----------|
| `crate::module::function` | [params] | [what changes] | [yes/no — duration] |

## Initialization entry points

[One-time entry points still attackable during deployment. List separately.]

- **`crate::module::function`** — [type: `init` / `instantiate` / `Pallet::initialize`] — [what it sets and whether front-runnable]
```

---

## 3. `trust-model.md` — actors and what they can do

```markdown
# Trust Model

> [Project Name] | [N] actors | [N] trusted | [N] semi-trusted | [N] untrusted

## Actors

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| [Role / Pubkey / Origin variant] | TRUSTED / SEMI-TRUSTED / UNTRUSTED | [what they can do — instant vs timelocked] |

[Only named actors from code. No "Anyone" — that's "Untrusted user" if applicable. Never use "Semi-trusted" without a reason — use "SEMI-TRUSTED (reason: e.g. a single keeper without slashing)".]

[The Capabilities column must be specific about what's instant vs timelocked / multisig'd. If a role has a transfer delay but instant operational functions, state both: "1-day transfer delay; all operational fns (`set_fee`, `set_oracle`, `withdraw_treasury`) instant."]

## Adversary ranking

[Ordered by threat level for THIS protocol type, adjusted by git evidence. Typically 3-5 entries.]

1. **[Adversary type]** — [one sentence: WHO they are and WHY they threaten THIS protocol type. Use the matched profile from rust-protocol-types.md.]
2. **[Adversary type]** — [...]

[The HOW and WHERE details belong in attack-surface.md, not here. This section names WHO threatens.]

## Trust boundaries

[Where trust transitions happen. Per boundary: what's trusted across the boundary, what damage if compromised, what protection exists.]

- **[Boundary name]** — [protection status + the single worst instant action it leaves open + code ref. Max 2 lines.]
```

---

## 4. `entry-points.md` — every public/external function with classification

```markdown
# Entry Points

> [Project Name] | [N] entry points | [N] permissionless | [N] role-gated | [N] privileged | [N] initialization

## Protocol Flow Paths

[Order entry points into expected execution flows — the "story" of the protocol from deployment to steady state. Each major user-facing entry point gets a path showing every step that must happen before it becomes callable.]

[Group flows by actor. Use simple arrow chains — no boxes, no diagrams. Annotate non-obvious preconditions with `◄──`.]

### Setup (Authority)

`init_pool()` → `set_oracle()` → `set_fee_authority()` → `enable_market()`

### User flow

`[setup above]` → `vault::deposit()` → `lending::borrow()`  ◄── liquidity must exist
                                          ├─→ `lending::repay()`
                                          └─→ `lending::liquidate()`  ◄── position unhealthy

### Maintenance (Keeper)

`[deposit above]` → [interval passes] → [oracle fresh] → `crank::accrue_interest()`

[Rules for flow paths:]
[- One chain per major destination function. Branch with ├─→ and └─→ when multiple exit paths.]
[- Reference earlier flows with `[setup above]` / `[deposit above]` instead of repeating.]
[- ◄── annotates non-function preconditions (time passage, health, liquidity).]
[- Trace from `require!` / `ensure!` / `if … return Err` statements back to the functions that write those state variables.]
[- 15-30 lines total. This section is an index into the detail sections below.]

---

## Permissionless

[Entry points callable by any signer / any origin with no effective access restriction. Sorted by value flow.]

### `crate::module::function`

| Aspect | Detail |
|--------|--------|
| Visibility | `pub fn` / `#[program]` / `#[pallet::call]` |
| Caller | [User / Anyone / etc.] |
| Parameters | [`param_name (user-controlled)`, `param_name (protocol-derived)`] |
| Call chain | `→ crate::fn() → crate::fn() → ...` |
| State modified | [Anchor accounts / CosmWasm state items / Substrate Storage items that change] |
| Value flow | [Tokens: sender → vault / vault → recipient / None] |
| Re-entry guard | [yes / no / N/A for non-CPI paths] |

[Repeat for each permissionless entry point.]

---

## Role-gated

[Entry points restricted by role. Group by role.]

### Role: `KEEPER`

#### `crate::module::function`

| Aspect | Detail |
|--------|--------|
| Visibility | `pub fn` + `[constraint]` |
| Caller | [Keeper bot / Relayer / etc.] |
| Parameters | [`param (user-signed)`, `param (keeper-provided)`, `param (protocol-derived)`] |
| Call chain | `→ ...` |
| State modified | [...] |
| Value flow | [direction] |
| Re-entry guard | [yes / no] |

[Repeat for each role and function.]

---

## Privileged (admin / `ensure_root` / DAO)

[Compact table — auditors need to see the full admin surface at a glance.]

| Crate::Function | Parameters | State Modified | Timelock? |
|-----------------|------------|----------------|-----------|
| `crate::admin::set_fee` | `fee_bps: u16` | `Config::fee_bps` | no — instant |

[Repeat.]

---

## Initialization

[`init` / `instantiate` / `Pallet::initialize` — one-time deployment functions. Still attackable during the deployment window.]

- **`crate::module::function`** — [type] — [what it sets, who can call, whether front-runnable]
```

---

## 5. `invariants.md` — doc-stated, code-extracted, and inferred invariants

```markdown
# Invariants

> [Project Name] | [N] guards | [N] inferred | [N] not enforced on-chain

## 1. Enforced guards (reference)

[Per-call preconditions. Heading IDs (`G-N`) are anchor targets from attack-surface.md and Stage 2 candidate findings.]

#### G-1
`require!(amount > 0, ErrCode::ZeroAmount)` · `crate/src/file.rs:123` · [one-line purpose — *why* this guard exists / what invariant it enforces]

[Repeat #### G-N for every relevant guard. Two lines per guard: H4 heading, then a body line with three ` · `-separated fields: verbatim predicate, file:line, purpose prose. Skip pure parameter validation with no global implication.]

## 2. Single-crate invariants

[Inferred from delta writes, guard lifts, ratio analysis, state-machine transitions.]

#### I-1: [name]
- **Type**: Conservation | Bound | Ratio | StateMachine | Temporal
- **Property**: [the invariant in plain language, e.g. "every active position has `amount >= MIN_POSITION`"]
- **Derivation**: [how it was inferred — Δ-pair, lifted guard with all write sites, NatSpec quote]
- **On-chain**: Yes | No
- **Source**: `crate/src/file.rs:LN`

[Repeat #### I-N. The On-chain=No blocks are the high-signal ones — each is simultaneously an invariant and a candidate finding.]

## 3. Cross-crate / cross-module invariants

[Caller / callee pairs that cross scope boundaries.]

#### X-1: [name]
- **Caller-side assumption**: `crate_a/src/file.rs:LN` reads value from `crate_b::module::query` and assumes [property]
- **Callee-side write sites**: `crate_b/src/file.rs:LN` writes that value via `function_x`, `function_y`
- **On-chain enforcement**: [whether the callee enforces what the caller assumes]
- **Source**: cite both ends

[Repeat #### X-N. Only include rows where BOTH sides are inside the scope. Do not speculate about out-of-scope dependencies — those go in attack-surface.md as composability concerns.]

## 4. Economic invariants

[Higher-order properties deriving from I-N + X-N.]

#### E-1: [name]
- **Property**: [e.g. "user cannot withdraw more than they deposited unless yield was harvested"]
- **Derivation**: derives from I-3, I-7, X-2
- **On-chain**: Yes | No (matches the weakest link in derivation)

## 5. Unbounded storage fields (v0.1.7 — MANDATORY; EXPANDED in v0.1.10)

[Enumerate every storage field declared as `Vec<T>`, `BTreeMap<K, V>`, `HashMap<K, V>`, or any growable container that can be appended/inserted via a public entry point. For each, cite the documented `MAX_*` cap and the gate that enforces it. If no cap exists, explicitly flag — this is a Stage-2 candidate-finding (see V63 in rust-attack-vectors.md).]

### 5.1 Direct unbounded containers (V63)

| Field | Type | Append/insert site | Cap | Gate | Hot-path consumer | Bound? |
|-------|------|---------------------|-----|------|---------------------|--------|
| `RecoveryStateV0::assoc` | `Vec<AssociationsV0>` | `add_association` (account/v0.rs:605-619) | none | none | `initiate_recovery` linear scan (account/v0.rs:171-226) | **NO — flag as Stage-2 candidate (V63)** |
| `Vault::guardians` | `Vec<Pubkey>` | `set_guardians` (...) | `MAX_GUARDIANS = 10` | `require!(guardians.len() <= MAX_GUARDIANS)` | `verify_threshold_signatures` linear scan | yes |

### 5.2 Unbounded mapping iteration (NEW v0.1.10 — V86)

[Enumerate every site where a `Map<K, V>` (CosmWasm `cw_storage_plus::Map`, Substrate `StorageMap`, or `BTreeMap`) is iterated inside a public-entry handler. Even bounded maps become DoS surfaces if the per-element work is non-trivial.]

| Iteration site | Map type | Map size source | Per-element work | Attacker controls size? |
|----------------|----------|-----------------|-------------------|------------------------|
| `<file:line>` | `Map<Pubkey, Position>` | `permissionless deposit` populates | full health-factor calc + oracle read | **YES — flag (V86)** |

### 5.3 Lazy cumulative-growth containers (NEW v0.1.10 — V87)

[Enumerate fields where individual transactions push a bounded number of entries (per-tx cap enforced) but cumulative growth across many txs is unbounded.]

| Field | Per-tx cap | Cumulative cap | Reset point | Bound? |
|-------|-----------|----------------|-------------|--------|
| `<crate::Foo::pending_actions>` | 10 per tx | none | none | **NO — flag (V87)** |

### 5.4 Accumulators with attacker-controlled granularity (NEW v0.1.10 — V88)

[Enumerate every counter / running total whose update granularity is settable by an attacker-influenceable parameter without an upper bound.]

| Field | Update site | Granularity-setter | Granularity bound | Overflow protection |
|-------|-------------|--------------------|--------------------|---------------------|
| `<crate::Pool::cumulative_rewards>` | `accrue_rewards` | `set_rate(rate)` permissionless | **none** | `*= elapsed` not checked — flag (V88) |

[Repeat for every field. **Bound? = NO** in any subsection means the field passes attacker-controllable size/growth/granularity to a hot-path consumer — flag it.]

**Rule**: every growable storage container, every map-iteration site, every cumulative-growth field, and every attacker-controllable accumulator MUST appear in the appropriate sub-table. Missing entries are enumeration misses — re-run Stage 1 source reading.
```

---

## 6. `hot-zones.md` — ranked list of files / modules to focus Stage 2 on

```markdown
# Hot Zones

> [Project Name] | hot zones ranked by Stage-2 priority

[The model uses this file to decide which files to read first in Stage 2. Rank by:
- protocol-type-relevance
- git churn
- recent-commit-fix-density
- presence of `unsafe` / unchecked arithmetic / `unwrap()` / unbounded loops
- test coverage gaps
- complexity
- **imperative state-mutation surface (NEW v0.1.12)** — see below
- **untrusted-byte-decode surface (NEW v0.1.12)** — see below
- **cost / weight / opcode tables (NEW v0.1.12)** — see below
- **fallback-branch / dead-code candidates (NEW v0.1.12)** — see below
- **verifier vk-binding paths (NEW v0.1.12, ZK projects)** — see below
]

### Bias warning (NEW v0.1.12)

A Stage 1 hot-zone ranking that focuses ONLY on:
- AIR `eval()` constraint blocks
- ZK circuit `Chip::eval` definitions
- Math invariant tables

…systematically misses bugs in imperative state-mutation Rust. The SP1 / Succinct Code4rena 2026-04 shadow-audit taught Argus this lesson: the contest's actual Mediums (M-02 truncated `public_values` panic, M-03 zero-`SplitOpts` livelock, M-06 nonce-clobber on `pack`) all lived in non-AIR imperative Rust. Argus's hot-zones ranking biased toward AIR code and missed all three.

For every project, Stage 1 hot-zones MUST include the categories below in addition to whatever protocol-specific ranking applies.

### Imperative state-mutation hot zones (MANDATORY)

Search the project for functions named or named-similarly-to:

`split`, `pack`, `unpack`, `partition`, `flatten`, `commit`, `merge`, `truncate`, `extend`, `chunk`, `batch`, `fold`, `compress`, `serialize`, `deserialize`, `encode`, `decode`, `prepare`, `prove`, `verify`, `dispatch`, `execute_step`

Every such function reachable from a public entry-point with attacker-influenceable inputs is a hot-zone candidate. Evaluate each:

| Function | File:line | Inputs from public API? | Edge cases tested? |
|----------|-----------|------------------------|---------------------|
| `<crate>::record::ExecutionRecord::split` | `record.rs:188-360` | yes (SplitOpts from caller) | unclear |
| `<crate>::pack_deferred_events` | `pack.rs:42-180` | yes (Vec<Event> from caller) | partial |
| ... | | | |

### Untrusted-byte-decode hot zones (MANDATORY)

Every `pub fn` (or `extern "C" fn`) that accepts `&[u8]`, `Vec<u8>`, or Borsh-decoded structs from outside trust boundaries:

| Function | File:line | First-line length-check? | Panic-class on malformed? |
|----------|-----------|-----------------------------|-----------------------------|
| `verify_public_values(input: &[u8])` | `verify.rs:565-624` | NO | yes (slice OOB) |
| `Transaction::read(reader: &mut R)` | `transaction.rs:282` | partial | yes (underflow) |
| ... | | | |

### Cost / weight / opcode hot zones (MANDATORY for protocols with metered execution)

Every cost table, weight table, opcode-fee table, or per-instruction CU calculation:

| Table | File:line | Coverage gap? |
|-------|-----------|----------------|
| `Opcode::cost(&self) -> u64` | `cost.rs:56-78` | check StoreDouble vs StoreWord (siblings) |
| `pallet::weights::*` | `weights.rs` | spot-check claims vs. work performed |

### Fallback / dead-code hot zones (MANDATORY)

Every documented "alternative" / "fallback" / "if-else" branch where the documentation suggests a code path is reachable, but the call chain may early-return before it:

| Branch | File:line | Caller chain | Reachable? |
|--------|-----------|---------------|------------|
| Blake3 fallback in `verify_public_values` | `verify.rs:645-668` | `verify_plonk_bn254` early-returns on `!vkey.is_plonk()` | NO — dead code |
| Legacy v1 path in `recover_id` | `recovery.rs:142` | `mark_recovery` only called by `#[cfg(test)]` | NO — test-only |

### Verifier vk-binding paths (MANDATORY for ZK projects)

Every `verify*` public function:

| Function | File:line | Binds vk_root at entry? | Caller checks vk_root before invoke? |
|----------|-----------|-------------------------|---------------------------------------|
| `verify_groth16_bn254` | `verify.rs:565-624` | NO (only checks proof) | NO | → SP1 M-01 pattern |

### Spec-doc enumeration (NEW v0.2.1 — MANDATORY)

**Driving signal**: swafe Code4rena 2025-11 shadow-audit run. C4 awarded 6 Lows for spec/impl mismatches (L-02 through L-08) — discrepancies between the project's `swafe-book/` specification and the Rust implementation. Argus v0.2.0 missed all 6 because Stage 1 didn't read the spec docs.

This is not a strictness question — it's an **input completeness** question. The bugs were in the diff between spec and impl; without reading the spec, the diff is invisible.

**Rule**: at Stage 1, enumerate every project-authored specification document and capture them as cross-reference inputs for Stage 2 angles.

**Sources to enumerate** (in priority order):

1. **`assets/docs/`** in the Argus run directory — user-supplied spec / context. Already used; v0.2.1 makes it explicit.
2. **Project repo `docs/`** — typically project-authored design docs.
3. **`*-book/`** directories (e.g., `swafe-book/`, `chain-book/`, `protocol-book/`) — mdBook-style specs.
4. **`SPEC.md`, `SPECIFICATION.md`, `DESIGN.md`, `PROTOCOL.md`** at repo root or per-crate.
5. **`*-spec.md`** anywhere in the workspace.
6. **`README.md` "How it works" / "Specification" / "Properties" / "Invariants" sections** — captured but lower-priority than dedicated spec docs.
7. **Whitepaper PDFs** linked from README (WebFetch if URL is given; otherwise note as "user-supplied PDF in assets/").
8. **`audits/` directory** — prior audit reports with remediations the project may have pinned as scope-references.

**Operation**:

```pseudo
for source in [assets/docs/, <repo>/docs/, <repo>/*-book/, repo-root, per-crate]:
    for path in find(source, "*.md", "*.pdf", "*.adoc"):
        record path in spec-docs-inventory.md with: filename, byte size, top-level headings

for each section heading containing keywords like "must", "should", "invariant", "property",
    "specification", "rules", "verify", "consensus":
    extract verbatim quote into invariants.md § "spec-derived invariants"
```

**Output addition** to Stage 1 — new file `$RUN_DIR/1-protocol-map/spec-docs-inventory.md`:

```markdown
# Spec-doc inventory

| Source | Path | Size | Top-level headings |
|--------|------|------|---------------------|
| project-repo/*-book/ | swafe-book/src/protocol.md | 24KB | "Recovery flow", "Guardian thresholds", "Account state" |
| project-repo/docs/ | docs/INVARIANTS.md | 8KB | "Invariants 1-12" |
| README | swafe/README.md § Specification | 4KB | "Account model", "Threshold semantics" |
| audits | audits/2024-08-zellic.pdf | (skipped — PDF; user manual review) | — |

## Spec-derived invariants extracted

| Invariant ID | Source | Verbatim quote |
|--------------|--------|----------------|
| spec-1 | swafe-book/protocol.md:142 | "the recovery threshold MUST be a strict majority of the guardian set" |
| spec-2 | swafe-book/protocol.md:189 | "an account's `assoc` field is bounded by `MAX_ASSOC = 32`" |
| spec-3 | docs/INVARIANTS.md:24 | "every share upload writes to a fresh slot; existing slots are immutable" |
| ... | | |
```

Stage 2's Invariant angle and First Principles angle MUST consume this file. **For every invariant in the spec-derived table, the angle reads the cited code and emits a FINDING if the implementation deviates.**

**Effect on swafe**: with `swafe-book/` enumerated, the 6 spec/impl-mismatch Lows (L-02..L-08) become Stage-2 candidates because the Invariant angle now has the spec to compare against. C4 awarded these as Lows; Argus would have caught them as Lows too.

**Skip condition**: if the project has no spec docs at all (`spec-docs-inventory.md` is empty), record `no_spec_docs_found: yes` affirmatively. Stage 2 spec/impl-mismatch detection is then N/A — no spec to mismatch against.

### Verify-Signal Crate Enumeration (NEW v0.2.0 — MANDATORY)

**Driving failure**: SP1 / Succinct contest M-04 (`crates/verifier/src/plonk/mod.rs:unwrap()` panic). The crate was in `scope.txt` but Argus's Stage 1 hot-zones swept only `crates/prover/` (the largest crate by nSLOC) and missed the standalone `crates/verifier/`. The orchestrator scored 0% direct recall on this finding partly because of this enumeration gap.

**Rule**: Stage 1 MUST independently enumerate every in-scope crate that contains security-critical verify/prove logic, regardless of crate size. The "biggest crate by nSLOC" heuristic systematically misses helper crates.

**Operation** (run for every crate in `scope.txt`):

```pseudo
for crate in SCOPE_CRATES:
    public_verify_fns = grep(
        crate.src_dir,
        pattern=r"pub\s+fn\s+\w*(verify|prove|check|validate|circuit|proof|witness|attest|audit)\w*"
    )

    if public_verify_fns is empty:
        continue   # no verify-signal — skip cheap

    # Distinguish important sub-crate from irrelevant utility (Rust-specific signals)
    important = false

    # Signal A — name heuristic
    if crate.name matches r"(verif|prove|valid|circuit|proof|witness|attest|zk)":
        important = true

    # Signal B — re-export linkage from main crate
    if grep(main_crate.src, "use " + crate.name + "::") returns hits:
        important = true

    # Signal C — Cargo.toml dependency edge
    if crate.name in main_crate.Cargo.toml.dependencies:
        important = true
    if main_crate.name in crate.Cargo.toml.dependencies:
        important = true

    # Signal D — type flow (function signatures use main crate's types)
    if any function in public_verify_fns uses types from main_crate:
        important = true

    if important:
        if crate.nSLOC >= 200:
            hot_zones.push(HotZone(crate, priority=PRIMARY, stage2_budget=FULL))
        else:
            # Small but signal-bearing — minimal Stage 2 budget
            hot_zones.push(HotZone(crate, priority=SECONDARY, stage2_budget=MINIMAL_30s))
```

**Anti-false-hot-zone filter**: a crate with `verify` in its name BUT no Cargo.toml dependency edge to/from main crate AND no type-flow signal AND located in `benches/` / `examples/` is excluded. The `benches/verify_benches.rs`-style false positive is filtered.

**Effect on SP1 case**: `crates/verifier/` matches signal A (name=`verifier`), signal B (likely re-exported by tests/scripts), and contains `pub fn verify`. It would be added as SECONDARY hot-zone at minimal budget. Stage 2 scans its public functions, spots the `unwrap()` on untrusted proof field, builds the LEAD, and Stage 3.6 Witness Builder Validator 3 fuzzes the boundary to confirm DoS. Direct recall on M-04 lifts from 0/4 to 4/4 on the SP1 baseline.

**Output addition** (new section in `hot-zones.md`):

```markdown
## Verify-Signal crate enumeration (v0.2.0)

| Crate | nSLOC | Signal A (name) | Signal B (re-export) | Signal C (dep edge) | Signal D (type flow) | Priority | Budget |
|-------|------:|------------------|----------------------|----------------------|----------------------|----------|--------|
| `crates/verifier/` | 187 | yes (name=verifier) | yes (`use verifier::` in tests) | yes (main_crate depends) | yes (`fn verify(proof: &prover::Proof)`) | SECONDARY | MINIMAL_30s |
| `crates/zkvm-circuits/` | 1240 | yes | yes | yes | yes | PRIMARY | FULL |
```

## Top hot zones

| Rank | Crate / Module / File | Why hot | Stage-2 angles to dispatch |
|-----:|-----------------------|---------|-----------------------------|
| 1 | `crate::module::file:LN-LN` | [git churn N commits + reward-accrual logic + value-moving] | Math Precision, Invariant, Economic |
| 2 | `crate::module::file` | [...] | [...] |

## Test coverage gaps

[Notable gaps that elevate review priority. Files / modules with high churn AND missing tests rank higher.]

- `crate::module::file` — [tests: N unit / 0 fuzz / 0 proptest — gap matters because…]

## `unsafe` blocks

[Every `unsafe { ... }` block in scope, with file:line and a one-line justification (or "no justification" if missing).]

- `crate/src/file.rs:LN` — [what the unsafe block does, whether justified by code comment]

## Recent activity (last 30 days)

[Files with security-relevant commits in the last 30 days. Cross-reference with hot-zone ranking.]

- `crate/src/file.rs` — [N commits, one-line summary of latest commit message]
```

---

## Discipline rules

- **No fabrication**: every fact in every Stage 1 file cites code or git evidence.
- **No threat speculation in Stage 1**: Stage 1 names concerns; Stage 2 attacks them. Don't pre-judge whether a concern is exploitable.
- **No marketing language**: no "comprehensive", "robust", "industry-leading". State the fact, stop.
- **No fictional roles / actors**: only named code roles. Don't invent "honest user" or "rational attacker" — say "any user" or "permissionless caller".
