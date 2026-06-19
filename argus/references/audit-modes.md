# Audit Modes — `smart-contract` vs `infra`

> **Status**: introduced in v0.3.0-alpha. Argus now supports two distinct audit missions. The mode is selected at Stage 0 and routes every downstream stage to mode-specific references.

## The two modes

| Aspect | `smart-contract` mode (legacy) | `infra` mode (new in v0.3.0) |
|--------|--------------------------------|------------------------------|
| **Target** | Solana Anchor programs, CosmWasm contracts, Substrate pallets, on-chain Rust applications | DLT infrastructure: validator clients, consensus engines, p2p networking, crypto libraries, storage engines, RPC nodes, off-chain workers, bridge relayers, wallet libraries |
| **Bug shapes** | Oracle manipulation, replay, scope carve-outs, account substitution, CPI re-entry, threshold math, governance flaws, fix-subsumption — logic-layer | UB / aliasing / memory safety, unsafe trait soundness, integer overflow, concurrency (deadlock, race, lost wake-up, ordering), cryptographic misuse, resource exhaustion, FFI safety, supply-chain CVE |
| **Verification** | LLM-driven Pass A/B/C/D adversarial review (current pipeline) | Deterministic backends (Miri / Kani / Loom / Rudra / cargo-fuzz / cargo-audit) with LLM only for hypothesis generation + harness writing + orchestration |
| **Severity authority** | Pass D English rubric + C4 historical-severity heuristic | Pass D **Impact × Reachability matrix** — deterministic |
| **Submission target** | Code4rena / Sherlock / Cantina / Immunefi / HackenProof / CodeHawks contest or BB | Immunefi infra programs, HackenProof, vendor disclosure, embargoed CVE, internal-disclosure |
| **PoC tier ladder** | Tier-1 E2E / Tier-2 integration / Tier-3 minimal repro / Tier-4 derivation | **Tier-1-formal** (Kani/Miri proof) / **Tier-1-fuzz** (cargo-fuzz crash) / **Tier-1-runtime** (Loom failing schedule) / **Tier-2-prop** (proptest) / **Tier-3-unit** / **Tier-4-derivation** |
| **Pre-Pass 1** (scope carve-out) | ENABLED | DISABLED (no contest scope construct) |
| **Pass A TR-1** (trusted-role-required kill) | ENABLED | DISABLED (no admin-trust model — code is the protocol) |
| **Stage-2 angle set** | Vector Scan, Math Precision, Auth/Account/Signer/Origin, Economic Security, Execution Trace, Invariant, Periphery, First Principles, Cryptographic Soundness, Concurrency (v0.1.10), FFI Boundary (v0.2.0), Differ (v0.6.0) | Memory Safety, Unsafe Trait Soundness, Arithmetic, Concurrency, Cryptographic Misuse, Resource Exhaustion / DoS, Logic & State Machine, Supply Chain & FFI, **ZK Circuit Soundness (v0.6.1)** |

## Auto-detection at Stage 0

`scripts/enumerate.sh` already outputs `=== Project shape ===` with one of `anchor`, `cosmwasm`, `substrate`, `solana-native`, `generic-rust`, `unknown`. Default mode by project shape:

| Project shape | Default mode | Override allowed? |
|---------------|--------------|-------------------|
| `anchor` | `smart-contract` | yes — but rare (Anchor IS contracts) |
| `cosmwasm` | `smart-contract` | yes |
| `substrate` | **ambiguous** — could be pallet (contract-shaped) or runtime/node (infra) | mandatory user confirmation |
| `solana-native` | **ambiguous** — could be native program (contract-shaped) or `solana-runtime`/validator infra | mandatory user confirmation |
| `generic-rust` | `infra` | yes — but rare (generic Rust IS infra by default) |
| `unknown` | mandatory user selection | n/a |

When ambiguous, Stage 0 uses `AskUserQuestion` to confirm the mode before proceeding.

### Recommendation discipline (v0.3.1)

The "Recommended" sticker on the `AskUserQuestion` prompt MUST follow this priority order. Earlier rules win.

1. **Bounty page category tag (highest priority)** — when an Immunefi / HackenProof / vendor bounty page is supplied at Stage 0 and the page's category selector is parseable:
   - Category contains **"Blockchain/DLT"**, **"Infrastructure"**, **"Node"**, **"Wallet"**, or **"Library"** → recommend **`infra`**.
   - Category contains **"Smart Contract"**, **"DeFi"**, **"NFT"**, **"AMM/DEX"**, **"Lending"**, **"Bridge (contract-side)"** → recommend **`smart-contract`**.
   - Category is ambiguous or missing → fall through to rule 2.
2. **Crate-name + repository-shape heuristics** — patterns that override the bare project-shape:
   - Crate name matches `*-runtime`, `*-validator`, `*-node`, `*-consensus`, `*-network`, `*-p2p`, `*-wallet`, `*-crypto`, `*-curve`, `*-signature`, `*-ringct`, `*-monero-*`, `*-substrate-*`, `*-cosmos-sdk-*`, `cometbft-*`, `polkadot-sdk-*`, `solana-runtime` → recommend **`infra`**.
   - Repo description / README contains "validator", "consensus", "p2p networking", "wallet library", "crypto primitive", "DLT infrastructure" → recommend **`infra`**.
   - Repo description / README contains "Anchor program", "CosmWasm contract", "Substrate pallet", "smart contract" → recommend **`smart-contract`**.
3. **Project-shape default** (rule 2 falls through to this) — the table above. `anchor` / `cosmwasm` → SC; `generic-rust` → infra; `substrate` / `solana-native` → user-confirm; `unknown` → user-confirm.
4. **Prior-run history (lowest priority; ONLY pro-signal when prior runs were validated)** — Argus may consult `assets/findings/` or prior `$RUN_DIR/8-final/submission-grade.md` outputs for prior modes. **Prior runs only carry recommendation weight if their SUBMIT findings were independently validated (accepted by the platform, or judged correct by a follow-up review).** A prior SC-mode run that produced false positives or INVALID verdicts is **anti-signal**: recommend the OTHER mode. Failed prior runs may indicate the mode itself was wrong for the target.

### Anti-pattern: "Recommended SC because prior run was SC"

When prior runs against the target were in SC mode AND those runs surfaced findings that were later judged INVALID / SC-2 / out-of-scope by external review, the recommendation is **`infra` not `smart-contract`** — the prior runs were themselves miscategorized, and re-running in SC mode perpetuates the original mistake.

Canonical case: **monero-oxide** (Monero protocol Rust libraries). Project shape `generic-rust`, Immunefi bounty tagged **Blockchain/DLT**, prior Argus runs (v0.1.3 monero-oxide, v0.2.5 Monero Oxide) were SC-mode AND the v0.2.5 F-15 `Decoys::select_n` finding was externally ruled INVALID for structural unreachability. **The v0.2.5 failure is what drove the entire v0.3.0 pivot to `infra` mode.** Recommendation for any future run on monero-oxide MUST be `infra`. Rule 1 (Immunefi page Blockchain/DLT tag) + Rule 2 (crate-name contains "monero", "ringct", "wallet") + Rule 4 (prior SC run was INVALID = anti-signal for SC) all point at `infra`.

## Mode-specific references — routing table

| Stage | `smart-contract` mode reads | `infra` mode reads |
|-------|----------------------------|---------------------|
| 0 | `cost-estimation.md` | `cost-estimation.md` (same; cost is mode-independent) |
| 1 | `pipeline-overview.md` + `rust-protocol-types.md` + `stage1-output-templates.md` | `pipeline-overview.md` + **`dlt-infra-types.md`** + **`stage1-infra-templates.md`** |
| 2 | `hacking-agents/shared-rules.md` + `hacking-agents/{vector-scan,math-precision,auth-account,economic-security,execution-trace,invariant,periphery,first-principles}-agent.md` + `attack-vectors/rust-attack-vectors.md` | `hacking-agents/shared-rules.md` + **`hacking-agents/infra/{memory-safety,unsafe-trait,arithmetic,concurrency,crypto-misuse,resource-exhaustion,logic-state-machine,supply-chain-ffi,zk-circuit-soundness}-agent.md`** + **`attack-vectors/dlt-infra-attack-vectors.md`** |
| 3 | `poc-standards.md` (Tier-1/2/3/4 ladder) | **`infra-verification-stage.md`** (REPLACES `poc-standards.md` — deterministic tool verdicts: CONFIRMED / DISPROVED / INCONCLUSIVE. Miri / Kani / Loom / Rudra / cargo-fuzz / cargo-audit invocation. v0.3.0-alpha Chunk 3.) |
| 4 | `adversarial-review.md` (full Pre-Passes + Pass A/B/C/D) | **`infra-impact-analysis.md`** (REPLACES `adversarial-review.md` — deterministic Impact × Reachability matrix + 4 downgrade rules. No Pass A/B/C/D. Stage 3 CONFIRMED findings get a mechanical severity verdict via `scripts/reachability.py` + `scripts/assign_severity.py`. v0.3.0-alpha Chunk 4.) |
| 5 | `platform-validation.md` + `platform-criteria/{code4rena,sherlock,cantina-bb,cantina-comp,immunefi,hackenproof,generic}.md` | **`disclosure-paths.md`** (4 disclosure paths: vendor-coordinated / vendor-report / cve-disclosure / generic-infra. No contest-platform AI-N rules — DLT-infra findings go to vendors / CVE / public issues. v0.3.0 Chunk 5.) |
| 6 | `program-triage.md` (bounty page WebFetch) | **`cve-triage.md`** (CVE decision matrix + RUSTSEC/NVD/GHSA cross-check + pre-filled CVE-request JSON. v0.3.0 Chunk 5.) |
| 7 | `duplication-check.md` (full probe set) | `duplication-check.md` + **CVE-database probe** (CVE / GHSA / RustSec advisory lookup) |
| 8 | `output-format.md` + `report-templates/{code4rena,sherlock,cantina,immunefi,hackenproof,codehawks,generic}.md` | `output-format.md` + **`report-templates/infra/{advisory,vendor-report,cve-disclosure,generic-infra}.md`** (Stage 5 selects which template; Stage 8 fills it. v0.3.0 Chunk 5.) |
| 9 | `fix-verification.md` (current 6 phases) | `fix-verification.md` + **`infra-fix-verification.md`** (adds Miri/Kani/Loom re-runs to confirm fix kills the verified violation) |

## What survives the mode split (mode-independent)

These references / fields / disciplines apply identically in both modes:

- The 9-stage pipeline shape itself.
- Cross-stage invariants: no data re-derivation, code citation always required, dead findings stay dead, subagent results advisory, AI-provenance reminder mandatory.
- The mandatory FINDING schema fields: `weaponization_check`, `reachability_check`, `code_comment_scan`, `docstring_disclaimer`, `bug_reachability_proof`, `confidence`, `claimed_severity`, `stage1_ref`, `test_coverage`.
- Confidence model deductions in `shared-rules.md`.
- Cost-estimation formulas (per-stage token formulas are mode-agnostic; the Stage-2 dispatch cost is the same regardless of which 8 angles run).
- TodoWrite mandatory at Stage 0.
- One-todo-in-progress-at-a-time discipline.

## What is mode-dependent

- The Stage-2 angle set + vector catalogue.
- The Stage-1 output templates (smart-contract mode emits 6 protocol-mapping files; infra mode emits 6 different files focused on unsafe-block inventory, FFI surface, async runtime topology, concurrency primitive inventory, dependency CVE surface, hot-zone ranking).
- Stage 3 PoC tier ladder (smart-contract Tier-1 E2E vs infra Tier-1-formal / Tier-1-fuzz / Tier-1-runtime).
- Stage 4 Pre-Pass 1 (scope carve-out — disabled in infra).
- Stage 4 Pass A invalidator catalogue (smart-contract 13 categories vs infra-augmented with TC class).
- Stage 4 Pass D severity rubric (English + C4 heuristic vs Impact × Reachability matrix).
- Stage 5 platform criteria (contest platforms vs disclosure paths).
- Stage 6 program triage (bounty page vs CVE/embargo workflow).
- Stage 8 report templates.

## Cross-mode discipline

If a project is **genuinely hybrid** (e.g., a Substrate runtime with embedded contracts in `pallet-contracts`), Stage 0 picks the dominant mode and Stage 2 explicitly notes the secondary surface. Cross-mode hybrid full coverage is a v0.4.0+ candidate; v0.3.0 ships with single-mode-per-run discipline.

## Why both modes exist

The user audits **DLT infrastructure** as primary work — validator clients, consensus engines, crypto libraries, storage backends. v0.2.6 was built for smart-contract auditing because the earliest test corpus was Code4rena contests. v0.3.0-alpha pivots Argus to its actual mission while preserving the smart-contract pipeline as a callable mode (still useful for cross-checking contract-shaped library code, e.g., on-chain components of a DLT system).

## Strategy routing (NEW v0.6.0)

Strategies are orthogonal to audit modes. Any strategy can run in either `smart-contract` or `infra` mode.

| Strategy | Stage 1 | Stage 2 angles | Stage 3 PoC floor | Stage 4 | Reference |
|----------|---------|---------------|-------------------|---------|-----------|
| **Digger** (default) | Full 6-step threat model | All 12 (SC) / 9 (infra) | Tier-1 target, Tier-3 floor | Full Pre-Pass + Pass A/B/C/D | — |
| **Speedrunner** | Actors + surface 1-4 only | Auth + Vector Scan + Exec Trace + First Principles | Tier-2 acceptable, Tier-3 floor | Pass A only | `strategies/speedrunner.md` |
| **Watchman** supplement | Diff-aware (changed modules only) | All, scope = changed paths | Tier-1 for regression-introduced | Full on changed paths | `strategies/watchman.md` |
| **Differ** supplement | Full + reference import | All 10 + Differ angle | Tier-2 floor | Pass B with reference comparators | `strategies/differ.md` |
| **Lead Hunter** (explicit) | Deep threat model (single subsystem) | Single Lead Hunter agent (4× context budget) | Tier-1 mandatory | Standard (novel class needs strongest evidence) | `strategies/lead-hunter.md` |
| **Scientist** (explicit) | Full + tooling needs assessment | All 10 + Scientist tool findings (Stage 1.5) | Tool output IS PoC evidence | Standard | `strategies/scientist.md` |

Strategy selection happens at Stage 0.5 via `signal-assessment.md`. The strategy modifies pipeline behavior per the table above. User-explicit strategy choice at Stage 0 overrides the automatic recommendation.

## What does NOT belong in this file

- Per-vector descriptions (those live in `attack-vectors/*.md`).
- Per-angle methodology (those live in `hacking-agents/*-agent.md`).
- Per-stage operational detail (those live in the named per-stage reference files).
- Per-strategy detailed methodology (those live in `strategies/*.md`).

This file is the **mode + strategy routing index**, nothing more.
