# Stage 4 — Impact Analysis & Exploitability (`infra` mode)

> Replaces SC-mode Pass A/B/C/D entirely. For each CONFIRMED finding from Stage 3 (per `infra-verification-stage.md`), this stage deterministically assigns severity via a fixed Impact × Reachability matrix.
>
> Source: DeepSeek `chunk4.md`, integrated 2026-05-12 with adjustments for output-path conventions, real Python scripts in place of pseudocode, and audit-modes.md routing alignment.

## Purpose

For every CONFIRMED finding from Stage 3, determine:

1. **Reachability**: can an attacker (remote, local, authenticated) trigger the vulnerable code path?
2. **Impact**: what's the worst-case security consequence if exploited?
3. **Severity**: the fixed product of reachability × impact, with downgrade rules for DLT-specific context.

Output is a severity label (CRITICAL / HIGH / MEDIUM / LOW / INFORMATIONAL) plus a structured impact statement written to `$RUN_DIR/4-impact/F-NN.md`. **No LLM opinion — the matrix decides.** This is the architectural counterpart to Stage 3's tool-confirmation: severity is mechanical, not judgmental.

## Prerequisites

- Stage 3 has produced a `CONFIRMED` verdict with tool evidence at `$RUN_DIR/3-verification/F-NN/verdict.md`.
- The codebase has been indexed by `rust-analyzer` (call graph accessible via `rust-analyzer analysis-stats --output json`).
- The attacker model is defined per DLT component type in `dlt-infra-types.md`.

If `rust-analyzer` indexing fails (large workspace, incomplete metadata, unresolved deps), the orchestrator falls back to manual annotation: each finding is flagged `reachability_confidence: low` and the finding is processed with a verdict-file flag the user must review. The finding does NOT auto-advance to Stage 5 in this case.

---

## Step 1 — Call-Graph Reachability

For each CONFIRMED finding, the orchestrator queries the call graph to answer:

> "Is the target function reachable from any entry point that an attacker can influence?"

### Entry-point classification (automatic)

A function is an **attacker-reachable entry point** if it is:

- A public API (`pub fn`) in a crate exposed over the network (RPC handler, HTTP endpoint, p2p message handler).
- An FFI function callable from external code (`extern "C"`).
- A command-line handler or configuration file parser.
- A transaction processing function (for validator / consensus components).
- A deserialization routine for untrusted input (Borsh / SCALE / Bincode / serde for network bytes).

The orchestrator extracts this list from:

- `cargo doc --no-deps --message-format=json` (public API surface).
- `grep -rn` for attribute markers: `#[rpc]`, `#[actix_web::*]`, `#[jsonrpsee::*]`, `libp2p::NetworkBehaviour`, `impl Deserialize`, `#[no_mangle]`, `extern "C"`.
- The component-type's `dlt-infra-types.md` entry-point inventory (Stage 1 produced this).

### Call-graph traversal

Using `rust-analyzer`'s call hierarchy or a pre-built call-graph JSON, trace from the vulnerable function **upward** toward entry points. If a path exists and intermediate functions do not sanitize or constrain the attacker's influence on the relevant arguments, the finding is **reachable**.

### Reachability buckets

| Reachability | Definition |
|--------------|------------|
| **Remote** | Reachable from an unauthenticated network entry point. No credentials needed. |
| **Authenticated** | Requires valid credentials, a staked validator slot, or trusted-peer-set membership. |
| **Local** | Requires shell access or filesystem write on the host (e.g., config file parsing, local IPC). |
| **Test-only** | Not reachable from any production entry point (only from `#[cfg(test)]` callers, `tests/` modules, or out-of-scope dev tooling). |

**Test-only reachability** → finding is demoted to LEAD. Logged at `$RUN_DIR/4-impact/_test-only-leads.md` for internal review. Not submitted.

### Automation script

```bash
python3 $SKILL_DIR/scripts/reachability.py \
    --callgraph $RUN_DIR/1-protocol-map/callgraph.json \
    --finding $RUN_DIR/3-verification/F-NN/verdict.md \
    --entry-points $RUN_DIR/1-protocol-map/entry-points.md \
    --output $RUN_DIR/4-impact/F-NN.reachability.json
```

The script emits JSON with `reachability_bucket`, `entry_point_path` (the chain of calls from entry to target), and `attacker_control` (which arguments / fields the attacker controls along the path). See `scripts/reachability.py`.

If `rust-analyzer` JSON is missing or path-resolution fails, the script emits `reachability_bucket: unclear` and the finding gets `reachability_confidence: low`.

### Dynamic-dispatch handling (trait objects)

Trait-object dispatch (`Box<dyn Trait>`, generic with trait bound erased at boundary) can't be fully resolved by static analysis. The script applies a **conservative over-approximation**: if any implementor of the trait is reachable from an entry point, the target is considered reachable. This prefers false positives over false negatives at the reachability stage — better to over-include and have Stage 5/6 filter than to under-include and miss a real bug.

---

## Step 2 — Impact Classification (Immunefi v2.3-aligned, v0.4.0)

Impact tier is determined by the worst-case consequence of the finding. Aligned with [Immunefi Vulnerability Severity Classification System v2.3](https://immunefi.com/immunefi-vulnerability-severity-classification-system-v2-3/) for Blockchain/DLT.

| Impact tier | Definition | Examples |
|---|---|---|
| **Critical** | Network cannot confirm new transactions; unintended chain split; direct loss of user funds via protocol-level mechanism; permanent freeze of >10% of staked funds; consensus failure leading to unrecoverable state | Consensus halt from non-determinism; successful double-spend via fork-choice flaw; crafted payload triggering divergence across ≥50% of network; direct fund drain via VM invariant break |
| **High** | Network-wide denial of service (not permanent); temporary freezing of funds or validator slashing; chain reorg enabler; light-client bypass allowing fraudulent state acceptance; node crash reachable by any peer | Amplified P2P DoS taking down ≥10% of nodes; mempool asymmetric-cost attack forcing full eviction (DETER-class); light-client accepts invalid state proof; RPC endpoint panic crashing node |
| **Medium** | Single-node DoS (not network-wide); significant performance degradation under adversarial conditions; privilege escalation within a node; information disclosure; finality delay without halt; block-propagation slowdown | Malformed message locks one node; mempool exhaustion from a single peer; RPC method leaks sensitive internal state; validator can be slashed via crafted input without losing all stake |
| **Low** | Resource inefficiency; minor state inconsistencies; bugs requiring a trusted position (consensus-level stake, operator access); recoverable misbehavior; log/event correctness issues | Inefficient gossip causing bandwidth waste; metric counter incorrect; audit-log inconsistency; governance vote count off-by-one |
| **Informational** | Code hygiene; best-practice deviations; unused code; documentation mismatches; dead code | Missing error context; dead fork-choice branch; spec-vs-impl naming drift |

The legacy v0.3.x "System Compromise / Data Corruption / Funds At Risk / Denial of Service / Confidentiality Breach / Integrity Weakening" categories now serve as **classifier inputs** that map to the 5 Immunefi-aligned tiers above. Mapping table in `scripts/assign_severity.py` `VECTOR_TO_IMPACT_TIER`.

---

## Step 3 — Likelihood Classification (NEW v0.4.0)

Replaces the v0.3.x "Reachability" axis. Likelihood subsumes reachability AND the additional preconditions an attacker must satisfy (Byzantine stake, network position, timing window, sustained adversarial state).

| Likelihood tier | Definition | Examples |
|---|---|---|
| **High** | Permissionless exploit, no prerequisites, reachable by any network participant or RPC client | Any P2P peer can send the crafted message; any unauthenticated RPC client can trigger the bug |
| **Medium** | Requires specific conditions: particular mempool state, validator subset, epoch boundary, active sync window, fork window, authenticated RPC | Attack needs a fresh sync; needs ≥1 validator to misbehave; requires a specific block range; requires JWT-authenticated Engine API |
| **Low** | Complex setup, multiple stars must align, requires time-bounded race, or sustained adversarial position | Needs a controlled validator for 10+ epochs; needs a sustained eclipse; microsecond race window; requires >1/3 Byzantine fraction already present |

**Test-only reachability** is no longer a Likelihood tier — it caps at INFORMATIONAL (per the legacy v0.3.x rule, preserved).

---

## Step 4 — Base severity = Impact × Likelihood

| ↓ Impact \ Likelihood → | **High** | **Medium** | **Low** |
|---|---|---|---|
| **Critical** | **CRITICAL** | **HIGH** | **HIGH** |
| **High**     | **HIGH**     | **HIGH** | **MEDIUM** |
| **Medium**   | **MEDIUM**   | **MEDIUM** | **LOW** |
| **Low**      | **LOW**      | **LOW** | **LOW** |
| **Informational** | **INFORMATIONAL** | **INFORMATIONAL** | **INFORMATIONAL** |

**Note**: matrix is **stricter than the v0.3.x 3×6** for Critical impact + Medium/Low likelihood. This reflects the catastrophic nature of L1 infrastructure failures: a consensus halt remains a severe incident even when the exploit requires specific conditions, because recovery cost (hard fork, rollback, manual intervention) scales with blast radius, not likelihood.

---

## Step 5 — Modifiers (applied after base matrix; v0.4.0 NEW)

Modifiers shift the tier by ±1 and **stack** (floor: Informational, ceiling: Critical). The v0.3.x design was downgrade-only ("no UPGRADE rule"); v0.4.0 allows upgrades **only via documented modifier triggers**, never via judge override.

### Downgrades

| Modifier | Shift | Rationale |
|---|---|---|
| **Requires >1/3 Byzantine stake** | −1 tier | Attack path assumes ownership of consensus-level stake that would cost more than the bounty to acquire honestly |
| **Requires >2/3 Byzantine stake** | −2 tiers | Already-broken trust assumption; protocol explicitly does not defend against this |
| **Requires fully-trusted role** (governance, emergency key, upgrade admin) | −1 tier (floor: Info) | Trust assumption is documented; attack is a governance concern, not a protocol bug |
| **DoS affects only attacker's own node or resources** | −1 tier (floor: Info) | Self-harm is not a security issue |
| **Testnet-only reachability** | −1 tier | Production impact is bounded; exploits may not port cleanly |
| **Requires on-chain-only observation** (no cross-boundary impact) | −1 tier | Limited to internal state |
| **Latent dead-code finding** (code exists but unreachable in production; behaviorally-equivalent dead implementations) | cap at HIGH | A latent finding cannot be Critical unless a PoC demonstrates a realistic activation path within the audited commit. Document the activation precondition. |
| **Bundle-incomplete finding** (one missing field in a multi-field validation bundle without the full enumeration) | mark PARTIAL until enumeration | Prevents one-field-and-stop reporting. |

### Upgrades

| Modifier | Shift | Rationale |
|---|---|---|
| **Cross-chain or bridge surface with fund-loss path** | +1 tier | Bridges concentrate value and broadcast impact |
| **Finality-strict chain** (Casper FFG, Tendermint BFT, Aptos, Sui) with finality-affecting bug | +1 tier | Finality violations are unrecoverable without hard fork or social consensus, unlike probabilistic-finality chains |
| **Attacker has source control** (forked client, validator operator, relay operator) | +1 tier | Attacker can modify client behavior on top of exploiting the bug |
| **Permissionless exploit requires zero stake** | +1 tier if base ≥ Medium | Fully public attack surface; no economic friction |
| **Exploit reachable from an unauthenticated RPC endpoint** | +1 tier if base ≥ Medium | RPC is typically the most exposed attack surface |
| **Pre-auth panic** (panic reachable BEFORE authentication/handshake completes) | floor: HIGH | Single-packet node-kill primitive (NEAR "Ping of Death" class); always at least HIGH regardless of base |

---

## Step 6 — Calibration adjustments (v0.4.0)

Six empirically-grounded adjustments from real bug outcomes:

1. **Eclipse attacks default to Medium**, upgraded to High only if the attacker can reach ≥30% of nodes cheaply. Matches Immunefi treatment.
2. **Mempool asymmetric DoS (DETER / MemPurge class) maps to High** per the Immunefi "process transactions beyond set parameters" clause.
3. **RPC crash without chain impact is High only if** the affected client has ≥25% market share. Single-client RPC crashes on minority clients drop to Medium.
4. **"Brute force" language**: attacks requiring majority stake or >$X cost to execute are downgraded one tier (already encoded in Byzantine-stake modifier).
5. **Single-client consensus violations** (where other clients continue validating) are High, not Critical. A Critical chain split requires the majority of clients to diverge. Example: a single-client Fusaka-style bug is High; Critical requires ≥50% of network to diverge.
6. **Pre-auth panic is always High or Critical** on reachability grounds. The NEAR "Ping of Death" was rated CVSS 8.8 because any network peer could kill any node with one packet. See pre-auth-panic upgrade modifier above.

---

## Step 7 — Severity rationale (MANDATORY field on every finding)

Every Stage 4 finding MUST include a **Severity rationale** field that cites:

1. **Impact cell** with definition: e.g., "Impact: High — network-wide DoS from single peer per Step 2 Critical/High/Medium/Low/Info table"
2. **Likelihood cell** with definition: e.g., "Likelihood: Medium — requires peer to be connected during sync window per Step 3"
3. **Any modifiers applied**: e.g., "+1 for unauthenticated RPC surface", "pre-auth panic floor:HIGH"
4. **Resulting tier**: e.g., "Base = HIGH; modifier floor:HIGH; final = HIGH"

This makes grading auditable and makes disagreements mechanically resolvable in review.

---

## Step 5 — Output Artifact

For each CONFIRMED finding, Stage 4 writes `$RUN_DIR/4-impact/F-NN.md`:

```markdown
# F-NN — Impact Analysis (infra mode Stage 4)

- **vector_id**: A01
- **group**: A — Memory Corruption & UB
- **target**: `crate::serialize::write_header` at `serialize.rs:42-58`
- **stage_3_verdict**: CONFIRMED via Miri (evidence: `$RUN_DIR/3-verification/F-NN/tool-evidence.log`)

## Reachability

- **entry_point**: `NetworkHandler::on_message` (p2p message handler)
- **bucket**: Remote
- **call_path**: `on_message → parse_packet → deserialize_header → write_header`
- **attacker_control**: full control of message payload bytes
- **reachability_confidence**: high (rust-analyzer call graph resolved)
- **dynamic_dispatch_overapproximation**: no

## Impact

- **tier**: System Compromise
- **mechanism**: transmute size mismatch (Miri A01) allows writing 8 bytes into a 4-byte buffer, corrupting adjacent stack data including the return address.
- **worst_case**: Remote code execution on the node.

## Severity

- **matrix_lookup**: Impact=System Compromise × Reachability=Remote → **CRITICAL**
- **downgrade_applied**: none
- **downgrade_evidence**: n/a (no trusted role required; attacker needs only network access)
- **final_severity**: **CRITICAL**

## Tool Evidence

- Stage 3 log: `$RUN_DIR/3-verification/F-NN/tool-evidence.log`
- Miri error string (golden signature): `error: Undefined Behavior: type u64 has size 8, but transmuted type has size 4`
- Reproduction: `cargo +nightly miri test -- test_write_header --nocapture`

## Recommendation

Replace `transmute::<u64, [u8; 8]>` with `u64::to_le_bytes()` and adjust the buffer write to use the correctly-sized target. Apply bounds checking on the buffer before writing.

## Next stage

If `final_severity ≥ INFORMATIONAL` and finding is not test-only → Stage 5 (disclosure-path classification, Chunk 5).
If test-only → terminal; logged in `$RUN_DIR/4-impact/_test-only-leads.md`.
```

---

## Scripts

Real implementations under `$SKILL_DIR/scripts/`.

### `scripts/reachability.py`

Reads `rust-analyzer analysis-stats` JSON output, identifies entry points from configurable patterns + Stage-1 `entry-points.md` annotations, traces paths from each entry point toward the target function. Emits `reachability_bucket: Remote | Authenticated | Local | Test-only | unclear` plus the call path. Conservative over-approximation on dynamic dispatch.

Usage:
```bash
python3 $SKILL_DIR/scripts/reachability.py \
    --callgraph <path>.json \
    --target-function <crate::module::function> \
    --entry-points <path>.md \
    --component-type <validator-client|consensus-engine|...> \
    --output <path>.reachability.json
```

### `scripts/assign_severity.py`

Implements the matrix as a lookup table. Takes `reachability_bucket` + `vector_id` (resolved to `impact_tier` via the VECTOR_TO_IMPACT table) + optional `downgrade_rule` and emits `final_severity` + the reasoning.

Usage:
```bash
python3 $SKILL_DIR/scripts/assign_severity.py \
    --reachability <Remote|Authenticated|Local|Test-only> \
    --vector-id <A01|C02|...> \
    --downgrade-rule <none|TRUSTED-ROLE-REQUIRED|PRACTICAL-DIFFICULTY|BOUNDED-IMPACT|UPGRADEABLE> \
    --downgrade-evidence <citation>
```

Output is JSON consumed by the Stage 4 verdict writer.

---

## Integration

- **Stage 4 runs after ALL Stage 3 findings are processed.** Batch operation; not per-finding-streaming.
- **CONFIRMED → Stage 4 → severity assigned → Stage 5 (Chunk 5).**
- **DISPROVED findings are dropped** (already terminal at Stage 3; not re-processed here).
- **INCONCLUSIVE findings stay in `$RUN_DIR/3-verification/_inconclusive.md` and `manual-queue.md`**; they never pass to Stage 4 or 5.
- **Test-only reachable findings are demoted to LEAD** at this stage; logged in `$RUN_DIR/4-impact/_test-only-leads.md`.

## Limits

- **Call-graph reachability is sound for static dispatch; dynamic dispatch (trait objects, generic boundaries with erased bounds) uses conservative over-approximation** — mark reachable if any implementor is reachable. This prefers false positives over false negatives at the reachability gate.
- **Impact tiers assume worst-case exploitation.** A real attacker might need additional primitives (ASLR bypass, heap grooming, side-channel precision) not modeled here. This is intentional — at the Stage 4 gate we prefer false positives; Stage 5/6 (Chunk 5) apply disclosure-path / CVE-triage realism to filter.
- **The matrix is hand-built.** The 18 cells reflect community-standard mappings (CVSS-like impact × access-vector axes) but are not calibrated against an empirical DLT-infra finding corpus. Calibration is `ARGUS_V0.3.0_PLAN.md` post-v0.3.0 work.
- **Downgrade rules are heuristic.** TRUSTED-ROLE-REQUIRED applicability depends on the trust model from `dlt-infra-types.md`, which itself is hand-built per component. A wrong component-type classification at Stage 1 propagates to wrong downgrade decisions at Stage 4.

---

## Coordination with `audit-modes.md`

This file is loaded in `infra` mode only. In SC mode, Stage 4 runs the full Pass A/B/C/D adversarial review per `adversarial-review.md`. The two modes do not share Stage-4 logic.

In infra mode, the FINDING-schema fields `weaponization_check`, `reachability_check`, `code_comment_scan` are produced at Stage 2 but only `reachability_check`'s output is consumed here (and Stage 4's call-graph traversal supersedes the grep-based version from Stage 2 — `ARGUS_AUDIT.md` S2-4 fix).

## What this design closes from `ARGUS_AUDIT.md`

- **H-2** (severity tiers are English, two runs may disagree) — replaced by deterministic matrix.
- **H-3** (Cantina Impact × Likelihood vs C4 5-tier mapping implicit) — Stage 5 (Chunk 5) will map matrix output to per-disclosure-path expectations.
- **S2-4** (`reachability_check` naive grep) — replaced by `rust-analyzer` call graph here; the Stage-2 grep is now just a quick prefilter.
- **S4-7** (C4 historical-severity table miscalibration) — N/A in infra mode; deterministic matrix instead.

## What this design does NOT close

- **C-1** (calibration uncalibrated) — the matrix cells are hand-built; no empirical corpus has validated the specific cell values. Post-v0.3.0 calibration sweep against W3SA + a forthcoming DLT-infra corpus is the planned validator.
- **A-2** (severity unidirectional after Pass D) — preserved by design here. No UPGRADE rule.
- The downgrade rules' boundary conditions are still judgmental: "trusted peer set membership" vs "any-peer" can be ambiguous in some p2p designs.
