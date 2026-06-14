# Hacking Agents — Shared Rules

Every Stage 2 angle (Vector Scan, Math Precision, Auth/Account, Economic, Execution Trace, Invariant, Periphery, First Principles) obeys these rules. The orchestrator passes this file to every dispatched subagent alongside the angle's own definition.

## Reading

Your bundle has these inputs. Read in this order:

1. `1-protocol-map/hot-zones.md` — focus your attention here first
2. `1-protocol-map/entry-points.md` — every public/external function with classification
3. `1-protocol-map/invariants.md` — doc-stated, code-extracted, and inferred invariants
4. `1-protocol-map/trust-model.md` — actors and trust levels
5. The matching protocol-type profile in `references/rust-protocol-types.md` (your bundle names which one)
6. `references/attack-vectors/rust-attack-vectors.md` (Vector Scan only — others may glance for context)
7. The in-scope source files (paths in `1-protocol-map/scope-summary.md`), starting with hot-zones

When matching function names, check both `function_name` and `_function_name` (helper convention). Also check `pub fn`, `fn`, and `async fn` visibility variants.

## Cross-codebase weaponization (TIGHTENED in v0.1.7 — MANDATORY)

When you find a bug in one location, **weaponize that pattern across every other location in the bundle.** Search by function name AND by code pattern. Finding "missing `signer` constraint on `claim_rewards`" means you check every other privileged operation's `#[derive(Accounts)]` for the same gap. Missing a repeat instance is an audit failure.

After scanning, **escalate every finding to its worst exploitable variant.** A DoS may hide fund theft; a panic may hide an auth bypass; a deserialization bug may hide an account-substitution. Then revisit every function where you found something and attack its other branches.

### Mandatory weaponization-check field on every FINDING

Every FINDING block MUST include a `weaponization_check:` field listing:

1. The pattern signature you searched for (function name, code structure, or AST shape).
2. The grep / Read commands you used to search.
3. Every location you checked, with hit/miss outcome.
4. If a hit was found: a separate FINDING for the second location, OR a `multiple-instance:` annotation on this finding listing all locations.

**Failure mode this prevents** (the swafe v0.1.5 F-19 / C4 M-07 case):

- Argus found `recover_backups()` returns `self.backups` instead of `self.recover` (C4 M-02). Recommended fix: `self.recover.iter().collect()`.
- Argus did NOT then ask: "where else does the same `self.backups` reference pattern appear, and would my fix also resolve those?"
- The C4 M-07 was a parallel bug: `recover_id` only searches `self.backups` AND skips `self.rec.social` (the social-backup case). The correct fix is `self.recover.iter().chain(once(&self.rec.social)).collect()` — Argus's primary recommendation would still leave M-07 broken.
- This is exactly the failure mode the weaponization rule exists to prevent. v0.1.7 makes the check explicit in the FINDING schema.

### Schema (added to every FINDING)

```
FINDING | crate: <crate> | module: <path> | function: <fn> | bug_class: <kebab> | group_key: ...
location: <file>:<line-range>
path: <caller> → <function> → <state change> → <impact>
proof: <concrete values, traces, or state sequences>
description: <one-sentence root cause>
fix: <one-sentence suggestion>
weaponization_check:
  pattern: <what you grepped for>
  searched: [<file:line>, <file:line>, ...]
  hits:
    - <file:line>: <how the same pattern appears here>
    - (if no hits: "no additional instances")
  multiple-instance: <yes (separate FINDINGs filed) | no | yes (consolidated under this finding's "Recommendations" with all locations cited)>
reachability_check:
  cited_function: <the function whose bug you're claiming>
  callers_in_scope: [<file:line of every in-scope caller>, or "none"]
  callers_in_tests_only: [<file:line of every #[cfg(test)] / #[test] / tests/ caller>, or "none"]
  reachable_from_public_entry: yes | no | unclear (which Stage-1 entry-point chain reaches it)
scope_carveout_check:
  scanned_sections: [<section title>, ...]
  touching_carveouts:
    - section: <title>
      quote: "<verbatim>"
      match: WITHIN | PARTIAL | OUTSIDE
  rebuttal: <paragraph quoting carve-out words and showing why bug falls outside them, OR "n/a">
  rebuttal_quality: strong-textual | weak-interpretive | absent | n/a
  verdict: PROCEED | DOWNGRADE_TO_<sev> | DROP
code_comment_scan:
  local_scan: <file:line range scanned around the cited bug>
  project_grep: <grep command run, or "skipped — <reason>">
  matches:
    - file:line: "<verbatim comment>"
      classification: SUPPORTS_FINDING | DOCUMENTS_AS_DESIGN | NEUTRAL
      relevance: <1-sentence why this comment relates>
  verdict: STRENGTHEN | DROP_AS_SC2 | NO_SIGNAL
practical_weaponisation:                       # v0.1.10 — attack-difficulty axis
  capital_required: <amount in USD or "minimal">
  time_required: <atomic-tx | seconds | minutes | hours | "sustained over N blocks">
  monitoring_required: yes | no
  attacker_class: <permissionless | needs-flash-loan | needs-MEV-position | needs-validator-role | needs-trusted-role>
  weaponisation_grade: A | B | C | D
  # A = atomic + permissionless + minimal capital
  # B = atomic + permissionless + non-trivial capital OR sustained + permissionless
  # C = requires monitoring or MEV position
  # D = requires trusted role or sustained coordination
trust_threshold:                               # v0.1.10 — numeric trust model
  level: 1 | 2 | 3 | 4 | 5
  # 1: single-key admin
  # 2: 2-of-3 multisig OR single key behind timelock
  # 3: timelock + multisig
  # 4: governance + timelock + multisig
  # 5: full DAO with veto / multi-stage approval
  layers_bypassed_by_finding: 0..N
  # 0 = does not require trusted action
  # 1 = compromise of single key/layer
  # N = bypass all layers (Critical-eligible)
confidence_interval:                           # v0.1.10 — replaces bare `confidence`
  point: 0..100
  low: 0..100                                  # used by Stage 8 for SUBMIT decision
  high: 0..100                                 # used by Stage 8 for REFINE decision
  width_reasons: [<each uncertainty contribution with magnitude>]
prior_validity_rate:                           # v0.1.10 — Bayesian prior (placeholder until v0.3.0 model)
  protocol_type: <Lending | DEX | Vault | Stablecoin | Derivatives | LST | Bridge | Governance | NFT | Solana-generic | CosmWasm-generic | Substrate-generic | Generic-Rust>
  base_rate_for_class: 0.0..1.0                # historical TP rate for this bug class on this protocol type, or "no historical data"
  source: <eval-set ID or "no historical data">
source_snapshot:                               # v0.1.10 — reproducibility
  in_scope_files_sha256: <single hash over sorted list of cited files>
  git_commit: <sha or "uncommitted">
  audit_timestamp_utc: <ISO-8601>
claimed_severity: Critical | High | Medium | Low
confidence: 0..100                             # legacy field — same as confidence_interval.point; kept for back-compat
evidence_tags:                                 # v0.4.0 — infra mode MANDATORY (smart-contract optional)
  - tag: <FUZZ-PASS | LSP-TRACE | CODE-TRACE | NON-DET-PASS | CONFORMANCE-PASS | DIFF-PASS | PRIMITIVE:FALLBACK>
    artifact: <file path or command output>
    summary: <one sentence>
mandatory_checks:                              # v0.4.0 — infra mode MANDATORY (SC: confidence_gate only, rest n/a)
  devils_advocate: {rebuttal, survives_self_rebuttal, verdict}
  pre_auth: {earliest_boundary, fires_before_auth, modifier_eligible}
  asymmetric_cost: {attacker_cost, defender_cost, ratio, asymmetric_dos_class}
  cross_domain_deps: {deps, all_verified_in_production, downgrade_trigger}
  evidence_quality: {tag_set_sufficient_for_severity, action_if_no}
  confidence_gate: {point, low, high, passes_finding_threshold}
verdict_state: CONFIRMED | REFINED | REFUTED | CONTESTED   # v0.4.0 — 4-state, replaces 3-state
verdict_history:
  - {stage, state, reason, timestamp_utc}
severity_rationale:                            # v0.4.0 — required by Impact×Likelihood×Modifiers matrix
  impact_cell: "<Impact tier + one-line justification>"
  likelihood_cell: "<Likelihood tier + one-line justification>"
  modifiers_applied: [<modifier_id>, ...]
  resulting_tier: <Critical | High | Medium | Low | Informational>
```

If the `weaponization_check` field is missing, the FINDING is rejected by the orchestrator at Stage 2 dedup and the angle is asked to re-emit with the field populated.

### Reachability discipline (NEW in v0.1.8 — MANDATORY)

The `reachability_check` field is **mandatory**. The check answers: "is this bug actually reachable from a production entry point, or only from test code?"

**The failure mode this prevents** (the swafe v0.1.5 H-1 / Judge re-pass case):

- Argus found `recover_backups()` returns the wrong field. Recommended fix and rated High.
- The cited bug-triggering function was `mark_recovery` — but a grep of in-scope callers revealed that `mark_recovery` is only called by `#[cfg(test)]` modules. No production code path invokes it.
- The bug is real in code but unreachable from any deployed entry point. Real severity: QA/Low.
- The Judge re-pass downgraded H-1 from High to QA on this basis. Argus had not performed the reachability check.

### How to perform the reachability check

For every Stage 2 FINDING, before emitting:

1. **Identify the cited function** (the one whose buggy behavior the finding claims is exploitable).
2. **Grep for callers** across the entire in-scope source tree:
   ```bash
   grep -rn "<function_name>(" --include='*.rs' <project-root>/src/
   ```
3. **Classify each caller**:
   - **In-scope production caller**: regular `pub fn` / `fn` not behind `#[cfg(test)]` / `#[test]` / inside `tests/` module.
   - **Test-only caller**: behind `#[cfg(test)]` attribute, or inside a `tests/` directory, or annotated `#[test]` / `#[tokio::test]`.
   - **External caller (out-of-scope)**: in a crate / module not in `1-protocol-map/scope-summary.md`.
4. **Verify reachability from a Stage 1 entry point**: trace each in-scope caller back to `entry-points.md`. If no chain reaches the cited function, the bug is **unreachable** → demote to LEAD or drop entirely.

### Verdict mapping

| Reachability outcome | Action |
|----------------------|--------|
| `reachable_from_public_entry: yes` AND chain cited | proceed with claimed severity |
| `reachable_from_public_entry: no` (only test callers) | demote to **LEAD** or drop. Do NOT file as FINDING. The bug is real but un-exploitable. |
| `reachable_from_public_entry: no` (only out-of-scope callers) | demote to LEAD with note "depends on out-of-scope code calling the function" |
| `reachable_from_public_entry: unclear` | keep as candidate FINDING but record the uncertainty. Stage 4 Pass C will fire on it. |

### README invariant pre-check (NEW in v0.1.8 — MANDATORY)

Adjacent to the docstring-disclaimer rule. Before flagging a behavior as a vulnerability, **read the project's README and any in-scope design docs** for invariants that document the behavior as intentional.

**The failure mode this prevents** (the swafe v0.1.5 M-5 / Judge re-pass case):

- Argus flagged M-5 "Recovery uses OR-of-N over `rec.assoc`; multi-email accounts have weakest-link auth strength" as Medium.
- Argus's recommendation was "introduce a `recovery_email_threshold` and require ≥k matching signatures."
- The swafe README (invariants #2 and #8) **explicitly mandates OR-of-N**: "Only the owner of an email should be able to request the recovery of an account" — meaning *any single email*, not M-of-N. Invariant #8: "An account may have multiple emails associated for recovery." The OR-of-N semantics is documented intentional design.
- Argus's proposed fix would VIOLATE the documented invariant. Real severity: Informational (SC-2).
- The Judge re-pass downgraded M-5 from Medium to Informational on this basis.

### How to perform the README invariant pre-check

For every Stage 2 FINDING, before emitting:

1. **Read the project's README** (or `assets/docs/` content if Stage 1 captured it).
2. **Search for invariants / properties / "should" / "must" / "only" statements** that touch the bug area.
3. **Quote any invariant that contradicts the finding's framing** verbatim into a new mandatory field:
   ```
   readme_invariant_check:
     scanned: <readme path or "no readme found">
     touching_invariants: [<verbatim quoted invariant 1>, <verbatim quoted invariant 2>, ...]
     finding_contradicts_invariant: yes | no
     verdict: <if yes: SC-2 candidacy → drop or reframe; if no: proceed>
   ```
4. **If the finding's framing contradicts a documented invariant**, the finding is at risk of SC-2. Either:
   - Drop the finding (the README documents the gap).
   - Reframe around a *different* defect — if the README says OR-of-N is intended but the *implementation* allows OR-of-2 (some shape that violates the invariant), that's still a finding.

The README invariant pre-check is part of Stage 2 (before emit) AND part of Stage 4 Pass A (re-checked when the docstring-disclaimer rule fires). Both layers exist because Stage 2 angles can miss the README scan; Stage 4 catches the missed cases.

### Scope carve-out pre-check (NEW in v0.1.9 — MANDATORY)

**Distinct from `readme_invariant_check`.** That field captures positive specifications ("the protocol must do X" → finding contradicts X). This field captures **scope exclusions** — sections in the README / contest scope that say "issues of class X are publicly known / out of scope / trusted-role-only / known design choice", which judges treat as ineligible regardless of technical merit.

**The failure mode this prevents** (the Reflector v0.1.8 run M-1 / L-3 case):

- Argus flagged M-1 "bitmask shift on admin replay at `timestamp == last_timestamp`" as Medium. The trigger requires admin to call `set_price` with the same timestamp twice.
- The Reflector README has a section titled **"Administrator Mistakes"** (under "Publicly known issues"): *"Contract `admin` can potentially invoke `admin`-level contract functions with some inconsistent/malformed arguments that may result in an unexpected internal contract state... Such an action would require explicit approval from >50% of Reflector DAO members, and thus cannot simply be done by mistake. As such, the contract code does not employ very strict validation rules in such functions."*
- Argus's writeup actually QUOTED this carve-out and argued against it ("malformed-args carve-out doesn't cover well-formed args at same timestamp"). The rebuttal was interpretive — no textual basis showing the literal scope words exclude this case.
- C4 wardens omitted M-1 from the contest report. Most likely reason: the carve-out applies.
- Same pattern hit L-3 with the README's **"Oracle Data Staleness"** section ("By design, it's normal to have a situation where an oracle does not have price data..."), partially weakening the impact case.

### How to perform the scope carve-out check

For every Stage 2 FINDING, before emitting:

1. **Read the project README's scope-exclusion sections.** Common section titles to look for:
   - "Publicly known issues" / "Known issues" / "Limitations"
   - "Out of scope" / "Files out of scope"
   - "Centralization Risks" / "Trust assumptions" / "All trusted roles in the protocol"
   - Subsections under any of the above (e.g., "Administrator Mistakes", "Oracle Data Staleness")
   - Top-level sections that document a class of behavior as intentional ("How It Works", "Security Properties")
2. **Quote each section's text verbatim** when it touches the bug area. Capture the exact scope wording.
3. **Match the finding's mechanism against each carve-out.**
   - **WITHIN_CARVEOUT**: the bug's required actor / state / input / mechanism falls inside the carve-out's literal text. Example: "Administrator Mistakes" carve-out covers admin functions invoked with inconsistent/malformed args; finding requires admin to call `set_price` with `timestamp == last_timestamp`.
   - **PARTIALLY_WITHIN**: one limb of the bug falls inside the carve-out, another doesn't. Example: README says "staleness is normal"; finding charges fee for stale-data read — staleness is in carve-out, fee asymmetry is not.
   - **OUTSIDE_CARVEOUT**: bug mechanism does not match any carve-out's literal text.
4. **Discharge the rebuttal burden** if WITHIN or PARTIALLY_WITHIN. The writeup's rebuttal must be:
   - **Textual**: cites specific words in the carve-out and explains why they don't reach this case.
   - **Concrete**: identifies the precise mechanism that is outside the literal scope.
   - **Not interpretive**: "the carve-out is meant for X" without textual support is rejected.

Record in a new mandatory field:

```
scope_carveout_check:
  scanned_sections: [<section title>, ...]
  touching_carveouts:
    - section: <title>
      quote: "<verbatim>"
      match: WITHIN | PARTIAL | OUTSIDE
  rebuttal: <if WITHIN/PARTIAL: paragraph quoting the carve-out's literal words and showing why the bug falls outside them. If OUTSIDE: "n/a">
  rebuttal_quality: strong-textual | weak-interpretive | absent | n/a
  verdict: PROCEED | DOWNGRADE_TO_<sev> | DROP
```

### Verdict mapping (Stage 2)

| Match | Rebuttal quality | Action |
|-------|------------------|--------|
| OUTSIDE | n/a | proceed with claimed severity |
| WITHIN | strong-textual | proceed; Stage 4 Pass C will fire to weigh the rebuttal |
| WITHIN | weak-interpretive OR absent | **DROP at Stage 2** — file as LEAD or discard. Saves PoC budget. |
| PARTIAL | strong-textual | DOWNGRADE one tier from claimed severity |
| PARTIAL | weak-interpretive OR absent | DOWNGRADE one tier AND tag for Stage 4 Pass C close-call review |

The scope carve-out check is part of Stage 2 (before emit, cheapest kill) AND part of Stage 4 (re-checked as a Pre-Pass — see `references/adversarial-review.md`). Both layers exist for the same reason as the README invariant pre-check: Stage 2 angles can miss the scope scan; Stage 4 is the safety net.

### Skip condition

Skip the scope carve-out check ONLY when the README has no scope-exclusion sections at all. Record `scope_carveout_check: no_scope_sections_in_readme` in the FINDING block. Do not skip implicitly — record the absence affirmatively.

### Code-comment scan (NEW in v0.1.9 — MANDATORY)

Developers leave breadcrumbs in code: `TODO`, `FIXME`, `XXX`, `HACK`, `NOTE`, `SAFETY:`, `INVARIANT:`, "by design", "intentional", "we don't validate", "should be", "may not". These comments are dual-signal at the per-finding level:

- **SUPPORTS_FINDING**: a `// FIXME: this allows X bypass` adjacent to the cited bug location is the dev acknowledging the exact defect — strengthens the finding and gives Stage 7 dup-check a free signal ("has the team filed an issue or fixed this in a commit not yet merged?").
- **DOCUMENTS_AS_DESIGN**: a `// NOTE: we don't validate timestamp here because admin is trusted` adjacent to the cited bug is the dev documenting the gap as intentional — SC-2 candidate, equivalent to a docstring disclaimer.
- **NEUTRAL**: unrelated comment in the area; ignore.

These comments are distinct from `///` doc comments (covered by Docstring discipline below) — they're inline `//` and `/* */` comments inside or adjacent to the function body.

### How to perform the code-comment scan

For every Stage 2 FINDING, before emitting:

1. **Read the cited file and 10 lines above + below the bug location.** Quote every comment that uses one of the marker tokens (`TODO`, `FIXME`, `XXX`, `HACK`, `NOTE`, `SAFETY`, `INVARIANT`) or any of the prose patterns above.
2. **For each matching comment**, classify against the finding's claim:
   - `SUPPORTS_FINDING` if the comment names the same defect or hints at the same gap.
   - `DOCUMENTS_AS_DESIGN` if the comment justifies the gap as intentional (trust assumption, scope deferral, simplification).
   - `NEUTRAL` if the comment is unrelated.
3. **Also run a project-wide grep** to catch comments far from the cited line that still touch the same mechanism:
   ```bash
   grep -rn -E '(TODO|FIXME|XXX|HACK|NOTE|SAFETY:|INVARIANT:)' --include='*.rs' <project-root>/src/ | grep -i '<bug-keyword>'
   ```
   Where `<bug-keyword>` is a token from the finding's mechanism (e.g., `auth`, `timestamp`, `init`, `replay`).
4. **Record in a new mandatory field**:
   ```
   code_comment_scan:
     local_scan: <file:line range scanned, e.g., file.rs:330-365>
     project_grep: <command run, or "skipped — single-file finding">
     matches:
       - file:line: "<verbatim comment>"
         classification: SUPPORTS_FINDING | DOCUMENTS_AS_DESIGN | NEUTRAL
         relevance: <1-sentence why this comment relates to the finding>
     verdict: STRENGTHEN | DROP_AS_SC2 | NO_SIGNAL
   ```

### Verdict mapping (Stage 2)

| Strongest match | Action |
|----------------|--------|
| Any `DOCUMENTS_AS_DESIGN` HIGH relevance | DROP — SC-2 candidate, the dev flagged the gap as intentional. File as LEAD only if the dev's justification is itself buggy (rare). |
| Any `SUPPORTS_FINDING` HIGH relevance | STRENGTHEN — quote the comment in the finding's `proof:` field. Run an extra Stage 7 dup-check pass for git log / GitHub issues mentioning the same comment. |
| Only `NEUTRAL` matches OR no matches | NO_SIGNAL — proceed normally. |

The code-comment scan is part of Stage 2 (before emit) AND part of Stage 4 (re-checked as a Pre-Pass — see `references/adversarial-review.md`). Both layers exist because Stage 2 angles can miss the local read; Stage 4 catches the missed cases.

### Why this matters

Two motivating cases:

- **Strengthen case**: a `// FIXME: this can panic if Vec is full` next to the line `vec.set(idx, val)` is the dev confirming the exact panic the finding describes. Including the FIXME quote in the writeup raises the finding's perceived plausibility and pre-empts judge skepticism.
- **Drop case**: a `// NOTE: we deliberately do not check timestamp == last_timestamp here; admin re-broadcast is treated as no-op by design` next to the bitmask shift would have killed Reflector M-1 at Stage 2 instead of letting it survive to a wasted PoC + adversarial-review cycle. Even when no such comment exists, the scan being performed and recorded as `verdict: NO_SIGNAL` is itself audit-trail evidence that the angle did the diligence.

### Skip condition

There is no skip condition. Every FINDING runs the local 10-line scan. The project-wide grep can be skipped only when the finding's mechanism is genuinely single-file with no cross-cutting keyword (rare); record `project_grep: skipped — <reason>` in that case.

### Bug-state reachability proof (NEW v0.2.5 — MANDATORY for every FINDING claiming a bug at a specific code location)

This is the **structural** reachability discipline. Argus's existing checks cover related but distinct questions:

- `reachability_check` (v0.1.8) — is the cited FUNCTION reachable from a public entry?
- `branch_reachability_check` (v0.1.12) — is the cited BRANCH (if/else arm, match arm) reachable through caller chain without a caller's early-return blocking it?

Neither catches: **the cited function is reachable AND the cited branch is reachable, but the bug STATE inside that branch is structurally unreachable due to a loop bound, a same-line guard, an inductive invariant, or an earlier-iteration return.** The Monero Oxide F-15 failure (2026-05-09) was exactly this case: `select_n`'s function was reachable, the line-99 branch was reachable, but the underflow state inside the subtraction was prevented by the same-line `< ring_len` comparison combined with the line-52 floor and per-iter induction.

**The rule**: every FINDING claiming a panic / OOB / underflow / overflow / livelock / specific arithmetic violation at a code location MUST produce a bug-state reachability proof BEFORE the FINDING is emitted. If the proof can't be constructed, demote to LEAD with `bug_reachability_proof_status: incomplete`.

#### The four components of the proof

```
bug_reachability_proof:
  bug_state_predicate: "<precise statement of the state required for the bug to manifest>"
  # Example: "underflow occurs IFF do_not_select.len() > highest_output_exclusive_bound at the moment of subtraction at line 99"

  function_entry_predicate: "<what holds at function entry from any public-entry caller>"
  # Example: "highest_output_exclusive_bound >= ring_len + 60 (line-52 floor); do_not_select starts empty (line-7); ring_len >= 11 (constant from RING_LEN_MIN)"

  loop_progression_model: "<if the bug is inside a loop or iteration: how loop variables evolve per iter>"
  # Example: "iter k starts with do_not_select.len() = 1 + (k-1)*(ring_len-1) under all-locked-daemon; MAX_ITERS = 10; per-iter check (highest - len) < ring_len returns InterfaceError when triggered"
  # If not in a loop, write "n/a — straight-line code".

  reachability_argument: "<step-by-step trace from function-entry-predicate to bug-state-predicate>"
  # Example: "From entry: len=0, highest=R+60. After iter 1: len=R+1. After iter 2: len=2R+1. Iter k starts at len=1+(k-1)*(R-1). Per-iter check fires when (R+60) - len < R, i.e., len > 60. For R=16 this is iter 5 (len=61). Bug state requires len > R+60 = 76, which requires iter 6 with len = 61+(R-1) = 76 — but iter 5's check already returned InterfaceError. Bug state UNREACHABLE."

  proof_outcome: REACHABLE | UNREACHABLE | INCONCLUSIVE
  # REACHABLE → continue with FINDING
  # UNREACHABLE → demote to dropped (do not file as LEAD; the bug doesn't exist)
  # INCONCLUSIVE → file as LEAD; Stage 4 Pre-Pass will re-attempt the proof
```

#### Same-line protection-check special case

When the cited bug expression is part of a guard expression on the same line, the proof has a near-automatic UNREACHABLE outcome. The guard exists specifically to prevent the bug.

Common patterns to recognize:

| Cited line shape | Cited "bug" | Proof outcome |
|-----------------|------------|---------------|
| `if a >= b { a - b } else { ... }` | `a - b` underflows | UNREACHABLE — the guard fires when a < b |
| `if (a - b) < c { return Err }` (where the goal is to bound `a - b`) | `a - b` underflows | UNREACHABLE in production with adjacent floor; proof must show the floor argument |
| `if idx < array.len() { array[idx] }` | `array[idx]` panics | UNREACHABLE |
| `let safe = checked_add(a, b)?; ...` | `a + b` overflows | UNREACHABLE — `?` propagates Err |
| `take(N).enumerate()` | iteration overruns N | UNREACHABLE |
| `if iters >= MAX { return }` inside a loop containing the bug | unbounded iteration | UNREACHABLE |

When the cited line matches one of these patterns, the angle MUST emit `proof_outcome: UNREACHABLE` and drop the candidate UNLESS the angle can construct a counter-proof showing the guard itself fails (e.g., integer overflow inside the guard, attacker bypasses via a different path).

#### Optional language signals (secondary, not authoritative)

If the angle's own internal reasoning contains any of these phrases when describing the cited bug, that's evidence the angle itself suspects unreachability — surface it explicitly:

- "spins indefinitely before" / "loops before"
- "fires before" / "trips before" / "triggers before"
- "exits before" / "returns before" / "short-circuits before"
- "harder than stated" / "more constrained than stated"
- "the protection check at the same line"
- "the per-iter check" / "per-iter floor" / "MAX_ITERS fires first"
- "structurally unreachable" / "structurally bounded"
- "inductive invariant prevents"

When ANY of these phrases appears in the angle's reasoning AND `proof_outcome` is REACHABLE, the angle MUST add `internal_contradiction_note: <which phrase + why proof is REACHABLE despite the phrase>`. Stage 4 Pre-Pass will scrutinize the contradiction.

#### Skip condition

The proof is mandatory for findings claiming:
- panic (any kind)
- OOB read / write
- arithmetic underflow / overflow
- livelock / infinite-loop / unbounded resource
- divide-by-zero
- out-of-gas / CU-exhaustion at a specific call site
- assertion failure at a specific line
- any "the function will reach state X with attacker-controlled input Y" claim

For findings that don't claim a specific code-location bug state (e.g., "this protocol's design has weak threat model", "this admin role has too much power", documentation-class), the proof is N/A — record `bug_reachability_proof: n/a — not a code-location bug claim`.

### Practical weaponisation (NEW in v0.1.10 — MANDATORY)

The `practical_weaponisation` field captures the *attack-difficulty axis* — orthogonal to severity. Two findings with identical severity (both High) can have very different weaponisation grades; a Grade-A High is a more urgent finding than a Grade-D High because exploitation is easier.

#### How to compute the weaponisation grade

| Grade | Attacker class | Capital | Time | Monitoring |
|-------|----------------|---------|------|------------|
| A | permissionless | minimal | atomic-tx | no |
| B | permissionless | non-trivial OR flash-loan-eligible | atomic-tx | no |
| C | permissionless OR needs-MEV-position | any | sustained over a few blocks | yes |
| D | needs-trusted-role OR needs-validator-role | any | sustained / coordinated | yes |

#### Verdict effect

| Grade | Stage 4 effect | Stage 8 effect |
|-------|----------------|----------------|
| A | no change | sort SUBMIT bucket: A first within same severity |
| B | no change | sort SUBMIT bucket: B after A |
| C | Pass D may consider downgrading one tier IF impact is also bounded | sort: C after B |
| D | Pass D applies severity cap based on `trust_threshold.layers_bypassed_by_finding` (see below) | sort: D last |

### Numeric trust threshold (NEW in v0.1.10 — replaces binary trust)

The `trust_threshold` field replaces the legacy binary TRUSTED / SEMI-TRUSTED / UNTRUSTED model. The level reflects the protocol's trust-architecture; `layers_bypassed_by_finding` reflects what the bug requires.

#### How to determine the level

Read Stage 1's `trust-model.md`. The level is the number of independent layers an attacker must compromise to perform the privileged action protected by the trust model:

- **Level 1**: single-key admin can act unilaterally.
- **Level 2**: 2-of-3 multisig, OR single key behind a timelock (timelock provides response window but not preventive auth).
- **Level 3**: timelock AND multisig.
- **Level 4**: governance vote AND timelock AND multisig.
- **Level 5**: full DAO with veto rights / multi-stage approval (governance pause + timelock + multisig + emergency veto).

#### How to determine layers_bypassed_by_finding

Read the finding's exploit path. Count layers of trust the attack circumvents:

- **0 layers**: the attack does not require any trusted action. The bug fires from a permissionless caller. (Most findings.)
- **1 layer**: the attack assumes one trusted role is compromised (single key leaked). This is bug-bounty-relevant on most platforms — keys do leak.
- **2+ layers**: the attack assumes multiple independent trust layers are bypassed (multisig + timelock both compromised). Generally not in-scope for bug bounties; the platform considers this catastrophe-class outside the protocol's threat model.
- **= level**: the attack requires the entire trust set to act maliciously simultaneously. Old TR-1 territory → INFORMATIONAL cap.

#### Verdict mapping (replaces TR-1)

| Layers bypassed | Action |
|-----------------|--------|
| 0 | no severity impact from trust model |
| 1 | keep claimed severity; finding is bug-bounty-relevant |
| 2 ≤ N < level | DOWNGRADE one tier per additional layer (multi-key compromise is escalating-improbable) |
| N == level | INFORMATIONAL cap (the entire trust set acts maliciously — out of bounty scope) |

The legacy TR-1 / TR-2 categories in Stage 4 Pass A are retained as cross-references; Pass D's clamps now use this field instead of the binary classification.

### Confidence intervals (NEW in v0.1.10 — replaces bare confidence)

The `confidence_interval` field reflects *epistemic uncertainty* — the orchestrator's uncertainty about its own confidence. A finding with `point=70` and `width=0` is "I am very sure this is 70% likely valid"; a finding with `point=70` and `width=30` is "best guess is 70% but the truth could be anywhere from 55-85% given what I don't know."

#### How to compute the interval

Start with `point = 100`. Apply the existing point-deductions:

- partial attack path traced: −20
- requires specific (but achievable) precondition state: −10
- bounded / non-compounding impact: −15
- requires multiple users to coordinate: −10
- exploit path crosses an out-of-scope dependency: −15
- depends on numeric data not verified: −20
- relies on assumption about external protocol's behavior without citation: −25

Then compute uncertainty contributions (each adds `±N` to interval width, contributing equally to `low` and `high`):

| Source of uncertainty | ± width |
|----------------------|---------|
| Unverified external claim (Stage 4 External Research returned UNVERIFIABLE) | ±10 |
| PoC tier 4 (written derivation) | ±15 |
| PoC tier 3 (state-only sim) | ±10 |
| No comparator citation when the impact case relies on one | ±10 |
| Reachability `unclear` | ±10 |
| LLM ensemble disagreement at Pass A (split verdict) | ±5 |
| LLM ensemble disagreement at Pass C (split verdict) | ±10 |
| Confidence calibration uncertainty (no historical data for protocol type) | ±5 |

`low = point - sum(contributions)`, clamped to [0, 100].
`high = point + sum(contributions)`, clamped to [0, 100].

Stage 8 binning uses `low` for the SUBMIT decision (be conservative about claiming a finding is strong) and `high` for the REFINE decision (be inclusive about salvageable findings).

### Prior validity rate (NEW in v0.1.10 — Bayesian prior placeholder)

The `prior_validity_rate` field documents the *historical base rate* for this protocol-type × bug-class combination. Without training data, set `base_rate_for_class: "no historical data"` and `source: "no historical data"`. Once the eval suite (`evals/benchmarks/`) accumulates labeled findings, populate from there.

This field is the input that the v0.3.0 logistic-regression confidence model will consume:

```
P(valid | features) = sigmoid(w0 + Σ w_i * feature_i)

features: poc_tier, pass_a_holds_count, pass_b_holds_count, pass_c_verdict,
          angle_agreement_count, prior_validity_rate, weaponisation_grade,
          scope_carveout_match, trust_threshold_level, layers_bypassed
```

Until the model ships, `prior_validity_rate` is informational only; orchestrator does not auto-adjust based on it. Document its presence so future runs can replay against it.

### Source snapshot (NEW in v0.1.10 — reproducibility)

The `source_snapshot` field records exactly what bytes were audited:

- `in_scope_files_sha256`: compute via `cd <project> && find <scope> -name '*.rs' | sort | xargs sha256sum | sha256sum`. The Stage 1 `scripts/enumerate.sh --sha256` flag produces this directly.
- `git_commit`: `git rev-parse HEAD` (or `"uncommitted: <dirty-hash>"` if working tree dirty).
- `audit_timestamp_utc`: ISO-8601 of when Stage 1 ran.

Every per-stage verdict.md MUST repeat this field. Stage 9 fix-verification compares the fix's `source_snapshot` against the original finding's snapshot and surfaces drift.

### Evidence-quality tags (NEW v0.4.0 — infra mode MANDATORY, smart-contract optional)

Every FINDING in `infra` mode MUST carry one or more `evidence_tags`. Tags name the kind of mechanical evidence the finding rests on — not the claim itself, but the artifact that backs the claim.

| Tag | Meaning | Produced by |
|-----|---------|-------------|
| `[FUZZ-PASS]` | A `cargo-fuzz` corpus / minimised input reproduces the bug | `cargo +nightly fuzz run <target>` with a minimised crash artifact |
| `[LSP-TRACE]` | A bidirectional def/ref trace from public entry to the bug line | `rust-analyzer` LSP `textDocument/definition` + `textDocument/references` walk |
| `[CODE-TRACE]` | A hand-written narrative of the call chain with file:line cites | reading the source and writing the chain |
| `[NON-DET-PASS]` | Differential / determinism check confirms divergence (e.g., re-encoding round-trip differs, two equivalent Borsh decodes produce different outputs) | a runnable test that fails when the bug is present |
| `[CONFORMANCE-PASS]` | A spec / reference-impl differential demonstrates the bug (e.g., Argus impl vs upstream Zcash reference vector mismatches) | a test that diffs the audited impl against an external oracle |
| `[DIFF-PASS]` | A `cargo +stable test` (or `anchor test` / `solana-program-test`) end-to-end reproducer passes/fails as required (Tier-1-live-e2e per v0.3.3) | an actual test file in `tests/argus_repro/` |
| `[PRIMITIVE:FALLBACK]` | Evidence is a working PoC for an attack PRIMITIVE (panic, OOB write, deserialiser-loop) without a full caller-chain to a public entry — kept as fallback when the upstream chain is `unclear` but the primitive is mechanically demonstrated | a unit test exercising the primitive in isolation |

#### The evidence rule

> `[CODE-TRACE]` alone is **not enough** to confirm Critical/High infra findings.

A finding tagged ONLY `[CODE-TRACE]` may claim severity up to MEDIUM (post-modifier). To claim HIGH or CRITICAL, the finding MUST also carry at least one of `[FUZZ-PASS]`, `[NON-DET-PASS]`, `[CONFORMANCE-PASS]`, `[DIFF-PASS]`, or `[LSP-TRACE]`. `[PRIMITIVE:FALLBACK]` does NOT clear the bar on its own — it documents a reachability gap.

#### How to populate

Record on every FINDING in a new mandatory field:

```
evidence_tags:
  - tag: <TAG>
    artifact: <file path or command output that produced the tag>
    summary: <one sentence on what the artifact shows>
```

Stage 4 Pass D will reject any infra-mode CRITICAL/HIGH finding whose tag set is `[CODE-TRACE]`-only with verdict `EVIDENCE-TAG-INSUFFICIENT — downgrade or refine`.

### Mandatory analysis checks (NEW v0.4.0 — infra mode MANDATORY)

Six checks every infra-mode FINDING runs before emit. Each is a pass/fail gate; failure does NOT necessarily drop the finding but DOES adjust severity or tag for Stage 4 review.

#### 1. Devil's Advocate

For every candidate FINDING, the angle must produce a one-paragraph rebuttal AGAINST the finding: the strongest argument that this is NOT a bug, the most likely benign explanation, or the missing precondition that would make the attack impossible. If the devil's-advocate paragraph survives one round of self-rebuttal, the finding is `CONTESTED` (see Verdict states).

#### 2. Pre-Auth Check

Identify the earliest network/RPC/CLI/config boundary the input crosses. If the bug fires BEFORE authentication / handshake / signature verification, tag `pre_auth: yes`. Pre-auth panics get the `PRE-AUTH-PANIC` floor:HIGH modifier (see infra-impact-analysis.md Step 5).

#### 3. Asymmetric Cost

Quantify attacker cost vs defender cost. A bug where the attacker spends 1KB to make the node spend 100MB of RAM is asymmetric (DETER-class); a bug where attacker and defender spend equal resources is symmetric (less interesting). Asymmetric ratio ≥ 100:1 with permissionless reachability is the mempool/P2P DoS High signal.

#### 4. Cross-Domain Dependencies

Does the bug require behavior from a component outside the audited scope (a specific kernel version, a specific Solana feature-gate state, a specific Anchor version, an upstream crate's behavior)? If yes, list each dependency and verify each is actually present in production. A cross-domain dependency that cannot be verified downgrades the finding via the `BOUNDED-IMPACT` or `PRACTICAL-DIFFICULTY` modifier.

#### 5. Evidence Quality

Look at `evidence_tags`. If tags are `[CODE-TRACE]`-only on a HIGH/CRITICAL claim, refuse to emit at that severity — refine via the auto-loop (see Stage 8.5) or downgrade.

#### 6. Confidence Gate

Compute `confidence_interval` (per the existing v0.1.10 model). Apply the Stage-8 threshold rule (`low ≥ 30` AND `point ≥ 50` for FINDING). Findings that fail the gate auto-bin as LEAD.

#### How to record

Add to every infra-mode FINDING:

```
mandatory_checks:
  devils_advocate:
    rebuttal: "<one paragraph: strongest argument this is NOT a bug>"
    survives_self_rebuttal: yes | no
    verdict: CONFIRMED | CONTESTED
  pre_auth:
    earliest_boundary: <where attacker-controlled input enters>
    fires_before_auth: yes | no
    modifier_eligible: PRE-AUTH-PANIC | none
  asymmetric_cost:
    attacker_cost: <bytes/CPU/storage>
    defender_cost: <bytes/CPU/storage>
    ratio: <N:1>
    asymmetric_dos_class: yes | no
  cross_domain_deps:
    deps: [<dep1>, <dep2>, ...]
    all_verified_in_production: yes | no | partial
    downgrade_trigger: BOUNDED-IMPACT | PRACTICAL-DIFFICULTY | none
  evidence_quality:
    tag_set_sufficient_for_severity: yes | no
    action_if_no: REFINE | DOWNGRADE
  confidence_gate:
    point: <0-100>
    low: <0-100>
    high: <0-100>
    passes_finding_threshold: yes | no
```

Smart-contract mode runs only the Confidence Gate (the other five are infra-specific). The `mandatory_checks` field is `n/a` for SC findings.

### Verdict states (NEW v0.4.0 — 4-state replaces 3-state)

The legacy 3-state (`CONFIRMED` / `DISPROVED` / `INCONCLUSIVE`) is replaced by a 4-state model that distinguishes "the bug exists but the original framing needed adjustment" from "the bug exists and the original framing was right."

| State | Meaning | When used |
|-------|---------|-----------|
| `CONFIRMED` | Bug exists; PoC reproduces; original claim and severity stand | Stage 3 PoC reproduces + Stage 4 Pass D upholds severity |
| `REFINED` | Bug exists; PoC reproduces; original framing was partially wrong (e.g., wrong root cause, wrong call-chain, wrong severity). The refined finding stands at the refined severity. | Stage 3 reproducer succeeds via a different mechanism than originally claimed, OR Stage 4 Pass D downgrades |
| `REFUTED` | Bug does not exist; PoC fails to reproduce; the claim is mechanically falsified | Stage 3 reproducer fails OR Stage 4 Pre-Pass kills the finding (carve-out, README invariant, docstring disclaimer, bug-state proof UNREACHABLE) |
| `CONTESTED` | The technical claim has surviving merit AND the devil's-advocate rebuttal also has surviving merit; resolution requires program-team or human review | `mandatory_checks.devils_advocate.survives_self_rebuttal: yes` AND PoC partially reproduces |

#### State assignment authority

| Stage | Authority |
|-------|-----------|
| Stage 2 | emits as candidate `CONFIRMED` (cannot itself REFUTE — only Stage 3+ can) |
| Stage 3 | may emit `REFUTED` if PoC fails; may emit `REFINED` if mechanism differs |
| Stage 4 Pass D | may emit `REFINED` (downgrade) or `REFUTED` (rebuttal upheld) |
| Stage 8.5 (REFINE auto-loop) | runs only on `REFINED` and `CONTESTED` states |
| Stage 8 final binning | gates SUBMIT on `CONFIRMED` or `REFINED`; `CONTESTED` and `REFUTED` never SUBMIT |

#### How to record

Add to every FINDING (replaces the implicit "found" state):

```
verdict_state: CONFIRMED | REFINED | REFUTED | CONTESTED
verdict_history:
  - stage: <2 | 3 | 4 | 8.5>
    state: <STATE>
    reason: <one sentence>
    timestamp_utc: <ISO-8601>
```

The 4-state is **mandatory** in infra mode and **optional but recommended** in smart-contract mode (where the legacy `CONFIRMED`/`DISPROVED`/`INCONCLUSIVE` triple is still accepted for back-compat).

## Docstring discipline (MANDATORY before flagging)

Before classifying a function's behavior as a bug, you MUST:

1. **Read the function's own `///` doc comment.** Quote it verbatim.
2. **Quote any behavior disclaimer.** Disclaimers include:
   - "may error" / "may not enforce" / "may return"
   - "not guaranteed to" / "no guarantees about"
   - "best effort" / "permissive" / "may not be"
   - "the result is not guaranteed to follow X" / "this is not a complete X"
   - "callers should X" / "users must X" (shifts responsibility outward)
3. **If a disclaimer is present** AND your finding's claim is "this function should enforce X" or "this function fails to validate Y", **the finding is at risk of SC-2 (documented intentional design)**. Either:
   - drop the finding (the disclaimer documents the gap), OR
   - reframe the finding around the *caller's* failure to add the validation the disclaimer says they should add.
4. **Record the disclaimer in the F-NN.md** under a new field `docstring_disclaimer`. If absent, write `docstring_disclaimer: none at <file>:<line>` — Stage 4 needs this either way.

Example of the failure mode this prevents (F-03 from the monero-oxide run):
- Function `Transaction::read` has docstring: "this MAY error if miscellaneous Monero consensus rules are broken … the result is not guaranteed to follow all Monero consensus rules or any specific set of consensus rules."
- A finding "Transaction::read does not enforce consensus rule X" was flagged High.
- The docstring explicitly disclaims consensus-rule enforcement. SC-2 should have killed the finding immediately. The angle skipped the docstring read and missed it.

## Trust-contract source discipline (NEW v0.1.11 — MANDATORY)

When a finding argues "the protocol's trust model says X" or "the protocol assumes the daemon is honest" or any claim about the protocol's intended trust boundaries, the citation MUST point to a **project-repo source**:

- `<repo>/README.md`
- `<repo>/SECURITY.md`
- `<repo>/audits/*.pdf`
- `<repo>/docs/*` (project-authored, not Argus-generated)
- `<repo>/<crate>/README.md` (per-crate readmes — these are authoritative)

**Citing `$RUN_DIR/1-protocol-map/trust-model.md` is REJECTED.** That file is an Argus-derived artifact — the orchestrator's reading of the project, not the project's authoritative trust contract. Auditing one's own audit notes as ground truth is a methodological error.

When `1-protocol-map/trust-model.md` and the project's README disagree, **the project README wins**. Update the artifact to match (or flag the divergence and continue without the artifact's claim).

### How to perform the trust-contract check

For every finding whose impact case relies on "the protocol guarantees X" or "the trust model says Y":

1. Open the project's README.md (and SECURITY.md, and per-crate READMEs in `interface/`, `core/`, etc.).
2. Search for the trust claim: phrases like "the caller is responsible for", "we assume", "the [actor] is trusted to", "neither set of traits promise", "this is not a complete X".
3. Quote the relevant sentence verbatim.
4. Compare to the finding's claim.
5. Apply the verdict matrix:

| Project README says | Finding claims | Action |
|---------------------|----------------|--------|
| Project guarantees X | Finding shows X breaks | proceed (this is a real bug) |
| Project DISCLAIMS X (caller responsible) | Finding shows X breaks | **KILL — the project explicitly hands the responsibility to the caller; no in-scope guarantee was promised** |
| Project says nothing about X | Finding shows X breaks | proceed but flag uncertainty |
| Project's $RUN_DIR/1-protocol-map cited as authority | n/a | **REJECT — re-cite from project repo or drop the claim** |

Record in a new mandatory field on findings making trust claims:

```
trust_contract_check:
  trust_claim: <one sentence: "the protocol guarantees X">
  cited_source: <file:line in project repo>
  cited_source_is_argus_artifact: yes | no
  verbatim_quote: "<quoted text from project source>"
  project_disclaims_guarantee: yes | no
  verdict: PROCEED | KILL_AS_DISCLAIMED | REJECT_CITATION
```

### Why this matters — the F-06 monero-oxide failure

The v0.1.10 run on monero-oxide produced F-06 (sanity_check_contiguous_blocks anchor-skip) citing `1-protocol-map/trust-model.md` as if it were the project's trust contract. The Judge identified that:

- That file is an Argus-generated artifact, not a project doc.
- The actual project trust contract at `monero-oxide/interface/README.md:11-16` says: *"Neither set of traits promise the returned data is completely accurate and up to date. Using an untrusted interface, even if the results are validated as sane, may always inject invalid data unless the caller locally behaves as a full node, applying all consensus rules, and is able to detect if they are not on the best chain."*
- The project EXPLICITLY DISCLAIMS the validating-wrapper guarantee F-06 assumed.

Citing `1-protocol-map/trust-model.md` (Argus's own reading) instead of `interface/README.md` (the project's stated contract) is exactly the failure this rule prevents.

## Comparator-claim discipline (MANDATORY)

When your finding's impact case relies on comparison to an external system (wallet2, Anchor framework, OpenZeppelin, Pyth, another protocol's source), you MUST:

1. **Cite the comparator's source code.** "wallet2 does this differently" without `wallet2/<file>.cpp:<line>` is not a finding — it's an unsupported claim.
2. **Read the cited code.** If you can't find the line that supports the comparator claim, the claim is unverified and the finding is downgraded to LEAD.
3. **Record in F-NN.md** under `comparator_citation`:
   - `comparator_system: <name>`
   - `comparator_claim: <what you say it does differently>`
   - `comparator_source: <file:line or URL>`
   - `verified: yes/no`

Stage 4 will fire `CLOSE_CALL_REVIEW (comparator-claim)` on any finding with an unverified comparator claim. Better to demote to LEAD here than survive to Stage 4 and fail.

## Do not report

- Linter / clippy lints, naming nits, doc comments missing.
- Panics only reachable from already-trusted internal callers with verified invariants.
- Standard ecosystem trade-offs (CU costs, weight estimates, MEV-without-mitigation in shared mempools).
- Self-harm-only bugs.
- "Admin can rug" without a concrete mechanism.
- TODO / FIXME comments.
- Missing event / log emissions unless the protocol explicitly relies on them for off-chain state.

## Output format

Return structured blocks only — no preamble, no narration. Exception: Vector Scan agent outputs its classification block first.

**FINDING** has a concrete, unguarded, exploitable attack path with a `proof:` field that cites real code values or a real call sequence.

**LEAD** has real code smells with partial paths — default to LEAD over dropping.

**Every FINDING must have a `proof:` field** — concrete values, traces, or state sequences from the actual code. **No proof = LEAD, no exceptions.**

**One vulnerability per item.** Same root cause = one item. Different fixes needed = separate items.

```
FINDING | crate: <crate-name> | module: <module::path> | function: <function_name> | bug_class: <kebab-tag> | group_key: <crate>::<module>::<function>|<bug_class>
location: <file>:<line-range>
path: <caller> → <function> → <state change> → <impact>
proof: <concrete values, traces, or state sequences from the actual code>
description: <one sentence root cause>
fix: <one sentence suggestion>
claimed_severity: Critical | High | Medium | Low
confidence: 0..100
stage1_ref: <which hot zone / entry point / invariant from Stage 1 this maps to>
test_coverage: covered | gap | n/a
# v0.4.0 — infra-mode MANDATORY (smart-contract optional); see § Evidence-quality tags / § Mandatory analysis checks / § Verdict states above for the full schema
evidence_tags: [<TAG entries>]
mandatory_checks: {devils_advocate, pre_auth, asymmetric_cost, cross_domain_deps, evidence_quality, confidence_gate}
verdict_state: CONFIRMED | REFINED | REFUTED | CONTESTED
severity_rationale: {impact_cell, likelihood_cell, modifiers_applied, resulting_tier}
```

```
LEAD | crate: <crate-name> | module: <module::path> | function: <function_name> | bug_class: <kebab-tag> | group_key: <crate>::<module>::<function>|<bug_class>
code_smells: <what you found that suggests something is wrong>
description: <one sentence explaining the trail and what remains unverified>
unverified: <what the LEAD couldn't trace to a complete attack path>
```

The `group_key` is the dedup key. After all 8 angles run, the orchestrator dedupes by `group_key` (exact match first; then merges synonymous `bug_class` tags sharing the same crate+module+function).

Agents may add custom fields (each angle's definition specifies which).

## Confidence model (UPDATED in v0.1.10 — interval-based)

Each candidate FINDING ships with both a point confidence (0-100) AND a confidence interval. The point is computed via deductions; the interval reflects epistemic uncertainty (see § Confidence intervals above).

### Point deductions (start at 100)

- partial attack path traced (some steps speculated): −20
- requires specific (but achievable) precondition state: −10
- bounded / non-compounding impact: −15
- requires multiple users to coordinate: −10
- exploit path crosses an out-of-scope dependency: −15
- depends on numeric data not verified (decimals, oracle params, real liquidity, CU costs): −20
- relies on an assumption about an external protocol's behavior without citation: −25

### Bounty-aware carve-outs (NEW v0.1.12 — driven by SP1 / Succinct shadow-audit failure)

The deductions above assume a generic fund-loss-class bug. Some bounties (Immunefi V2.3 ZK / verifier programs in particular) explicitly enumerate panic-class and DoS-via-panic findings as in-scope at Low/Medium severity. The "bounded / non-compounding impact: −15" deduction was calibrated for fund-loss bugs — applied to a panic finding in a bounty that pays for panics, it suppresses the finding to a LEAD even though it's bounty-eligible.

Stage 1's `attack-surface.md` now records the bounty's enumerated in-scope impacts (when the bounty has them; whitelist-mode per Stage 6 v0.1.11 classification). Stage 2 angles read this and apply the carve-outs:

| Bounty in-scope-impacts include... | Don't deduct for... |
|------------------------------------|----------------------|
| "Undocumented panic reachable from a public API" | "bounded / non-compounding impact" on panic-class findings |
| "Denial of service" / "Liveness violation" | "bounded / non-compounding impact" on DoS-class findings |
| "Undocumented fingerprints in created transactions" | "bounded / non-compounding impact" on fingerprint findings |
| "Non-constant-time implementation with regards to secret data" | "bounded / non-compounding impact" on side-channel findings |
| "Incorrect/incomplete cryptographic formulae within a verifier's callstack" | "partial attack path traced" when the math IS the bug (PoC = math derivation) |

The carve-outs apply ONLY when the finding's mechanism literally matches a bounty in-scope item. Generic "this is also a bounded DoS" without the bounty backing → deduction still applies.

#### How to apply

For each finding in Stage 2:

1. Read `1-protocol-map/attack-surface.md` § "Bounty enumerated in-scope impacts" (populated by Stage 1 from the bounty page).
2. For each deduction the angle would apply, check the carve-out table.
3. If the finding's mechanism matches a bounty in-scope item AND the carve-out applies, skip that deduction.
4. Record in the FINDING block:

```
bounty_carveouts_applied:
  - deduction_skipped: "bounded / non-compounding impact"
    bounty_item_matched: "Undocumented panic reachable from a public API"
    finding_mechanism: "verify_public_values panics on truncated input"
```

This is the SP1 M-02 fix: the verifier-panic-on-truncation finding now ships at confidence ≥50 → FINDING (not LEAD) because the bounty pays for panics.

### Threshold (uses interval, not just point)

| Decision | Rule |
|----------|------|
| FINDING | `point ≥ 50` AND `low ≥ 30` |
| LEAD | `point ≥ 30` AND `point < 50`, OR `low < 30` AND `high ≥ 50` |
| Drop | `point < 30` AND `high < 30` |

Stage 8 final binning uses `low` for SUBMIT (must clear 50) and `high` for REFINE (must clear 50). This makes the final filter robust to epistemic uncertainty: a finding the orchestrator is sure about (narrow interval) at point=55 makes SUBMIT; a finding it's unsure about (wide interval) at point=55 may not.

## Cap and threshold

- Each angle may produce up to 8 FINDINGs and unlimited LEADs to stay focused.
- Total post-dedup cap is ~30 FINDINGs across all angles — orchestrator prunes by claimed severity and Stage-1 alignment.

## Anti-patterns

- **Pattern-matching language without citation** ("this looks like reentrancy") — re-write or drop.
- **English-only proof** — "the attacker can drain the vault" without numbers or call sequence — demote to LEAD.
- **No file:line citation in `location`** — rejected at creation.
- **Two angles flag the same bug at different `group_key`** — orchestrator dedup will merge; do not preempt by suppressing.
- **"In theory" / "could in principle" / "should"** — banned. Show the path or drop the challenge.
