# Argus Handoff — Full Context for New Mac

> **Purpose**: this file is a complete-context handoff for resuming Argus work on a different machine. Drop this file into the new Mac's project root and point Claude at it; everything Claude needs to continue from where the previous session left off is below.
>
> **Last sync**: 2026-05-06 (mid-session, after pushing Argus v0.1.9).

---

## 1. Who the user is

- Email: `danielowenderefaka@gmail.com`
- Working environment: macOS, primary working directory `/Users/mac/Desktop/pashov2.0`
- Role: building / iterating on AI security-audit tooling for Rust + smart contracts. Tests Argus on real Code4rena contests and other live targets; iterates Argus releases driven by failure data from those runs.
- Collaboration style: terse, action-oriented, prefers minimal preamble. Pushes for rapid iteration ("push v0.1.7", "lets do this then tightening it"). Will course-correct with one-liners — treat those as authoritative.
- Auto Mode is on in this session — proceed without confirmation prompts on routine work.

---

## 2. What Argus is

A single Claude Code skill at `/Users/mac/Desktop/pashov2.0/argus/`. Rust-first end-to-end security-audit pipeline. Not a marketplace of skills — one focused capability with progressive disclosure across reference files.

**Single source of truth**: `argus/SKILL.md` (methodology, kept under 200 lines). All detail lives in `argus/references/*`.

### Project structure

```
argus/
├── SKILL.md                    # Methodology — read at session start
├── CLAUDE.md                   # Rules for Claude when extending Argus
├── CHANGELOG.md                # Version history (v0.1.0 → v0.1.9)
├── VERSION                     # Single source of truth for skill version
├── README.md / CONTRIBUTING.md / SECURITY.md / LICENSE
├── install.sh                  # Skill installer
├── .claude-plugin/plugin.json  # Claude Code plugin manifest
├── agents/openai.yaml          # OpenAI agent variant (alternative dispatch)
├── commands/                   # Slash-command entrypoints
│   ├── argus.md                # /argus
│   └── argus-fix-verify.md     # /argus-fix-verify (Stage 9)
├── evals/                      # Benchmark + comparison runners
│   ├── benchmarks/
│   ├── compare.md
│   └── runner.md
├── scripts/
│   ├── enumerate.sh            # Stage 1 workspace enumeration
│   ├── estimate-cost.py        # Stage 0 cost preview
│   └── install-deps.sh         # Toolchain installer (rustup, solana, anchor, avm, node)
├── assets/                     # Optional user-provided context (docs/, findings/)
└── references/                 # Progressive-disclosure reference files
    ├── pipeline-overview.md          # Per-stage handoff contract (read at Stage 1)
    ├── stage1-output-templates.md    # Templates for Stage 1's 6 output files
    ├── rust-protocol-types.md        # Solana / CosmWasm / Substrate / generic-Rust profiles
    ├── poc-standards.md              # PoC tier discipline (Tier-1 primary, Tier-3 floor, Tier-4 with self-audit)
    ├── adversarial-review.md         # Stage 4 (Pass A/B/C/D + Pre-Passes)
    ├── platform-validation.md        # Stage 5 generic
    ├── program-triage.md             # Stage 6
    ├── duplication-check.md          # Stage 7
    ├── output-format.md              # Stage 8 phases
    ├── fix-verification.md           # Stage 9 (optional)
    ├── cost-estimation.md            # Stage 0
    ├── hacking-agents/
    │   ├── shared-rules.md           # FINDING/LEAD format, mandatory schema fields
    │   ├── vector-scan-agent.md
    │   ├── math-precision-agent.md
    │   ├── auth-account-agent.md
    │   ├── economic-security-agent.md
    │   ├── execution-trace-agent.md
    │   ├── invariant-agent.md
    │   ├── periphery-agent.md
    │   └── first-principles-agent.md
    ├── attack-vectors/
    │   └── rust-attack-vectors.md    # V1-V63 vector library
    ├── platform-criteria/
    │   ├── code4rena.md
    │   ├── sherlock.md / sherlock-bb.md
    │   ├── cantina-bb.md / cantina-comp.md
    │   ├── immunefi.md
    │   ├── hackenproof.md
    │   └── generic.md
    └── report-templates/
        ├── code4rena.md
        ├── sherlock.md
        ├── cantina.md
        ├── immunefi.md
        ├── hackenproof.md
        ├── codehawks.md
        └── generic.md
```

---

## 3. The 8-stage pipeline (+ optional Stage 9, + optional Stage 0)

```
[0] Cost preview               → user authorization gate (added v0.1.5)
[1] Protocol Mapping           → $RUN_DIR/1-protocol-map/
[2] Rust Audit                 → $RUN_DIR/2-candidate-findings/F-NN.md  (8 parallel angles)
[3] PoC Generation (GATE)      → $RUN_DIR/3-poc/F-NN/{poc.*, repro.md, verdict.md}
[4] Adversarial Challenge      → $RUN_DIR/4-adversarial/F-NN.md  (Pre-Pass + Pass A/B/C/D)
[5] Platform Validation        → $RUN_DIR/5-platform/F-NN.md
[6] Program Triage             → $RUN_DIR/6-program/{bounty-page.md, F-NN.md}
[7] Duplication Triage         → $RUN_DIR/7-duplication/F-NN.md
[8] Final Output               → $RUN_DIR/8-final/{submission-grade.md, refine.md, discard.md}
[9] Fix Verification (OPT)     → $RUN_DIR/9-fix-verification/F-NN.md
```

**`$RUN_DIR`** = `<project-root>/argus/<UTC-timestamp>/`. One run per invocation. Never overwrite.

**Finding ID** = `F-01`, `F-02`, … assigned in Stage 2, carried unchanged through every later stage.

**Final buckets**: `SUBMIT` / `REFINE` / `DISCARD`. An empty `SUBMIT` bucket is a successful run.

**Severity authority**: only Stage 4 Pass D may UPGRADE. Stages 5-8 may DOWNGRADE only.

---

## 4. The 8 Stage-2 attacker angles

Dispatched as parallel general-purpose subagents in a single message when the project has >10 in-scope source files.

| Angle | File | Mindset |
|-------|------|---------|
| Vector Scan | `vector-scan-agent.md` | Pattern-match against the V1-V63 catalogue |
| Math Precision | `math-precision-agent.md` | Arithmetic, rounding, overflow, threshold off-by-one |
| Auth / Account | `auth-account-agent.md` | Anchor signer constraints, CosmWasm `info.sender`, Substrate `Origin` |
| Economic Security | `economic-security-agent.md` | MEV, fee asymmetry, profit/cost calculus |
| Execution Trace | `execution-trace-agent.md` | Multi-tx / cross-instruction state evolution |
| Invariant | `invariant-agent.md` | Stage-1-extracted invariants violated |
| Periphery | `periphery-agent.md` | Out-of-spotlight modules, helpers, init code |
| First Principles | `first-principles-agent.md` | Read code's own logic, ignore named patterns; violate every assumption |

**For ≤10 in-scope source files**: run sequentially in the orchestrator. Subagent dispatch overhead exceeds the speed-up at small N.

---

## 5. Stage 4 adversarial review — the false-positive killer

Read `references/adversarial-review.md` at Stage 4 start.

### Pre-Passes (run before Pass A, in this order)

1. **Scope carve-out + code-comment re-check** (NEW in v0.1.9, runs FIRST). Pure orchestrator file-reads, no subagent dispatch. KILL on:
   - Finding lands `WITHIN` a published scope carve-out (README "Publicly known issues" / "Out of scope" / "Centralization Risks" / named subsections like "Administrator Mistakes") AND rebuttal is `weak-interpretive` or absent.
   - Inline `// NOTE: by design` / `// SAFETY:` comment adjacent to the bug = `DOCUMENTS_AS_DESIGN` HIGH relevance → SC-2 KILL.
   - DOWNGRADE on `PARTIAL` carve-out match.
   - STRENGTHEN when `// FIXME` / `// TODO` adjacent to bug = `SUPPORTS_FINDING` (developer self-acknowledgment).
2. **External research wave** (v0.1.6). Spawns one Sonnet subagent per external-protocol claim with WebSearch / WebFetch. Verifies wallet2, Anchor, OZ, Pyth, Pendle behavior claims. Cache keyed by `"{system}::{claim hash}"`.
3. **Mitigation viability check** (v0.1.6, runs in background parallel to Pass A). Sonnet subagent classifies the proposed fix as `SOLVABLE` / `TRADE_OFF` / `UNCERTAIN`. `TRADE_OFF` HIGH → Pass D severity cap = Low.

### Four-pass main flow

- **Pass A — Generic invalidator scan**. 13-category catalogue (UP / CP / DT / EG / US / SH / DI / TI / SC / IM / AM / OS / TR). Selector ranks 4 entries (top-2 checked, bottom-2 advisory). **Wave 2 dispatch**: top-2 each get 2 parallel Sonnet checker subagents (4 total). **Unanimity rule**: both checkers must agree at HIGH confidence to auto-act on a HOLDS. Procedural floor: <4 ranked entries → Pass C MUST fire.
- **Pass B — Issue-specific challenges**. Generator produces 3-5 challenges; floor=3. **Wave 2 dispatch**: top-2 surviving challenges get 2 parallel Opus checkers each (issue-specific reasoning needs broader model). Comparator-claim challenges mandatory when finding cites external system.
- **Pass C — Symmetric neutral judge**. Opus. Fires when: any HIGH/MED HOLDS; any UNCERTAIN; rejected-HIGH; procedural-thinness; comparator-claim uncited; OR (NEW v0.1.9) scope-carveout WITHIN+strong rebuttal or PARTIAL+any. Skip-condition tightened in v0.1.9: scope-carveout must = OUTSIDE for Pass C to skip. **HIGH-confidence HOLDS handling**: VALID requires explicit `high_holds_overrides` field with content; "let Stage 8 handle" is REJECTED.
- **Pass D — Severity calibrator**. Independent re-grade from verified attack path. Allowed to UPGRADE as well as downgrade. Consults the **C4 historical-severity heuristic table** (v0.1.6) before assigning Critical/High — bug shapes like off-by-one threshold math, replay-without-version-binding, missing cnt-bump default to Medium even when "indirectly compromise assets via valid path." Counter-rule: `UPGRADE_OVERRIDE` field if PoC demonstrates direct fund-drain in one tx.

### Anti-hallucination rule

When a challenge depends on a numeric or external claim, verdict is `UNCERTAIN` unless grounded in: code citation in scope, Stage-1 doc-cited line, on-chain data, or PoC observable output. "Typically X" is NOT evidence.

---

## 6. Critical mandatory FINDING schema fields (Stage 2)

Every FINDING block at Stage 2 MUST carry these mandatory fields. Missing field = orchestrator rejects at dedup.

```
FINDING | crate: ... | module: ... | function: ... | bug_class: ... | group_key: ...
location: <file:line-range>
path: <caller> → <function> → <state change> → <impact>
proof: <concrete values, traces, sequences from real code>
description: <one-sentence root cause>
fix: <one-sentence suggestion>
weaponization_check:                   # v0.1.7 — search for repeat instances
  pattern: ...
  searched: [...]
  hits: [...]
  multiple-instance: yes/no
reachability_check:                    # v0.1.8 — is the bug reachable from production?
  cited_function: ...
  callers_in_scope: [...]
  callers_in_tests_only: [...]
  reachable_from_public_entry: yes | no | unclear
scope_carveout_check:                  # v0.1.9 — README scope exclusions
  scanned_sections: [...]
  touching_carveouts:
    - section: ...
      quote: "..."
      match: WITHIN | PARTIAL | OUTSIDE
  rebuttal: <textual paragraph>
  rebuttal_quality: strong-textual | weak-interpretive | absent | n/a
  verdict: PROCEED | DOWNGRADE_TO_<sev> | DROP
code_comment_scan:                     # v0.1.9 — TODO/FIXME/SAFETY/NOTE breadcrumbs
  local_scan: <file:line range>
  project_grep: <command, or "skipped — <reason>">
  matches:
    - file:line: "<verbatim>"
      classification: SUPPORTS_FINDING | DOCUMENTS_AS_DESIGN | NEUTRAL
      relevance: <why>
  verdict: STRENGTHEN | DROP_AS_SC2 | NO_SIGNAL
claimed_severity: Critical | High | Medium | Low
confidence: 0..100                     # v0.1.4 — 80% floor at Stage 3
stage1_ref: ...
test_coverage: covered | gap | n/a
```

Plus situational-mandatory: `docstring_disclaimer` (read function's own `///` doc; SC-2 trigger), `readme_invariant_check` (v0.1.8; positive specifications "must do X"), `comparator_citation` (when finding compares to external system).

**Confidence model**: start at 100, deduct: partial path -20, specific precondition -10, bounded impact -15, multi-user coordination -10, out-of-scope dependency -15, unverified numeric data -20, unverified external-protocol assumption -25. Threshold: ≥50 = FINDING; 30-49 = LEAD; <30 = drop.

---

## 7. Version history (v0.1.0 → v0.1.9)

Read `argus/CHANGELOG.md` for full detail; here's the motivating-failure-per-release timeline.

| Version | Driving signal | What it added |
|---------|----------------|---------------|
| 0.1.0 | Initial build | 8-stage pipeline synthesizing pashov X-Ray + Solidity Auditor + santiagoib bug-validator + hackenproof skills + heavyw8t The Judge |
| 0.1.1 | Cyfrin Updraft run failed because deps weren't installed | `scripts/install-deps.sh` for rustup / solana / anchor / avm / node |
| 0.1.2 | Stage 9 fix-verification gap | 5-phase fix-check (Understand / Analyze / Completeness / Regressions / Smart-contract-Rust-specific / verdict) |
| 0.1.3 | Initial vault-protocol test (7 planted bugs B1-B7) | Tier-3 PoC discipline tightening |
| 0.1.4 | monero-oxide run: 2/3 SUBMITs were FPs (F-03 docstring-disclaimer miss, F-10 comparator-claim miss) | 7-fix self-audit: Pass A procedural floor (must rank 4), Pass B floor (≥3), HIGH-HOLDS justification, docstring discipline, dedupe tightening, 80% certainty floor, Tier-1 PoC as primary target |
| 0.1.5 | User asked for cost transparency | Stage 0 cost preview (per-stage tokens, $X-$Y range, subscription % envelopes) |
| 0.1.6 | swafe Code4rena run: 8 SUBMITs collapsed to 3 by external Judge re-pass — "our judge is bad" | Architectural rewrite of Stage 4: parallel Wave-2 checkers (Sonnet for A, Opus for B), unanimity rule, External research wave (Sonnet + WebSearch), Mitigation viability check (background Sonnet), C4 historical-severity heuristic table (default Medium for off-by-one threshold / replay / missing cnt / wrong-field / linear scan / single-point-of-failure-auth / stale-state-window bug shapes) |
| 0.1.7 | Of 7 swafe C4 Mediums, Argus had 2 SUBMIT + 1 REFINE-faulty-dedup + 4 missed entirely | Stage 2 catalogue extensions: V61 majority threshold off-by-one (`div_ceil(2)` vs `(n/2)+1`), V62 degenerate-parameter silent-success (the swafe M-06 `&[]` + 0 case), V63 unbounded Vec; mandatory `weaponization_check` field |
| 0.1.8 | swafe Judge re-pass exposed 3 structural gaps: H-1 unreachability, H-3/M-2/M-4 fix-subsumption, M-5 README-invariant gap | Mandatory `reachability_check` field (greps for callers, classifies production/test/out-of-scope), mandatory `readme_invariant_check` field (scans README for "must"/"only" statements), fix-subsumption rule in dedupe judge ("would A's fix prevent B's exploit?" applied BEFORE other dedupe rules) |
| 0.1.9 | Reflector triage: M-1 (admin replay) survived to SUBMIT despite quoting "Administrator Mistakes" carve-out and arguing against it interpretively; L-3 (burn for None on stale) survived despite "Oracle Data Staleness" carve-out partially weakening it | Mandatory `scope_carveout_check` field (README "Publicly known issues" / "Out of scope" / "Centralization Risks" sections, with rebuttal-burden-of-proof: textual vs interpretive); mandatory `code_comment_scan` field (TODO/FIXME/SAFETY/NOTE/INVARIANT breadcrumbs, dual-signal: `SUPPORTS_FINDING` strengthens, `DOCUMENTS_AS_DESIGN` kills as SC-2); Stage 4 Pre-Pass added that runs FIRST (before External research wave, before Pass A) — pure orchestrator file-reads, KILL on WITHIN+weak/absent rebuttal or DOCUMENTS_AS_DESIGN HIGH; new Pass C trigger 6 `CLOSE_CALL_REVIEW (scope-carveout)` |

---

## 8. Test runs and what each taught us

### Vault-protocol (custom target with planted B1-B7 bugs)
- Location: `/Users/mac/Documents/rust-test/vault-protocol/`
- Used to validate v0.1.3 → v0.1.4 fixes.
- Lesson: thin Pass A (only 2 ranked invalidators) systematically misses SC-2 / SC-3 — produced 2/3 false positives.

### monero-oxide
- v0.1.3 run: 3 SUBMITs, 2 were false positives.
- F-03 = `Transaction::read` docstring explicitly disclaims consensus-rule enforcement; SC-2 should have killed it. Angle skipped the docstring read.
- F-10 = wallet2 comparator claim never cited the comparator's source code.
- Lesson: docstring-disclaimer pre-check + comparator-claim discipline (both mandatory in v0.1.4).

### swafe (Code4rena 2025-11-swafe)
- Run dir: `/Users/mac/Documents/2025-11-swafe/argus/20260505T233135Z/`
- v0.1.5 produced 8 SUBMITs; external Judge re-pass kept 3 (H-2 High, M-1 Medium, M-3 Medium).
- 4 of 7 C4 Mediums missed entirely (M-03, M-05, M-06, M-07) — Stage 2 catalogue gaps closed in v0.1.7.
- H-1 (recover_backups wrong field) unreachable from production — only test callers — closed in v0.1.8.
- H-3 / M-2 / M-4 collapse under H-2's fix — fix-subsumption rule in v0.1.8.
- M-5 (OR-of-N RIK) violates README invariants #2 / #8 — `readme_invariant_check` in v0.1.8.

### Reflector v3 (Code4rena 2025-10-reflector)
- Run dir: `/Users/mac/Documents/2025-10-reflector/argus/20260506T022358Z/`
- Submission dir: `8-final/submission-formatted/` — 10 files (H-01, M-01..M-05, L-01..L-03, QA-records-zero-burn, index.md).
- C4 ground truth: 1 High (H-01 set_invocation_costs_config), 5 Mediums (M-01..M-05), Lows + QAs.

**Triage of Argus 10 SUBMITs vs C4 ground truth**:

| Argus | C4 | Map |
|-------|----|----|
| M-2 (no-auth set_invocation_costs) | C4 H-01 | Caught — undergraded (Medium vs High) |
| M-3 (Beam extend_ttl panic) | C4 M-02 | Caught correctly |
| M-5 (TWAP None on data gap) | C4 M-03 | Caught correctly |
| L-1 (TWAP fee asymmetry) | C4 M-04 | Caught — undergraded (Low vs Medium) |
| L-2 (prices/x_prices overcharge) | C4 M-01 | Caught — undergraded (Low vs Medium) |
| M-4 (TWAP fee burn for None) | C4 QA-03 | Caught — overgraded (Medium vs Low) |
| H-1 (init front-run) | not in C4 | Plausibly novel real find — README has no carve-out for init races |
| M-1 (bitmask shift admin replay) | not in C4 | LIKELY scope-invalidated by "Administrator Mistakes" carve-out → drove v0.1.9 |
| L-3 (Beam burn for None on stale) | not in C4 | Marginal — partially scope-weakened by "Oracle Data Staleness" → drove v0.1.9 |
| QA records=0 | not in C4 | Valid QA — caller-mistake category |

**Headline numbers**: 6/7 recall on C4 risk findings (86%, big jump from swafe's 2/7). 4 severity miscalibrations (3 undergraded, 1 overgraded). 2 likely overshoots in SUBMIT bucket (M-1, L-3).

**Calibration regression**: v0.1.6's historical-severity heuristic over-corrected from swafe over-grading and now under-grades. Future v0.1.10 candidate: add an "impact-amplification" axis to the heuristic table (missing-validation × what-it-gates).

---

## 9. Current state — v0.1.9 just shipped

VERSION = 0.1.9. CHANGELOG entry added for 2026-05-06.

**What changed in code today**:
1. `argus/references/hacking-agents/shared-rules.md` — added `scope_carveout_check` and `code_comment_scan` as mandatory FINDING schema fields, with full how-to-perform sections and verdict matrices.
2. `argus/references/adversarial-review.md` — added Pre-Pass at the top of Stage 4 (runs before External-research wave, before Mitigation viability, before Pass A); added Pass C trigger 6 `CLOSE_CALL_REVIEW (scope-carveout)`; tightened Pass C skip condition to require scope-carveout = OUTSIDE; extended Stage 4 verdict file output schema.
3. `argus/VERSION` — `0.1.9`.
4. `argus/CHANGELOG.md` — v0.1.9 section with full motivation tied to Reflector M-1 / L-3.

**Expected v0.1.9 effect on a re-run vs Reflector**:
- M-1 → DROPPED at Stage 2 (rebuttal_quality = weak-interpretive against "Administrator Mistakes" carve-out).
- L-3 → DOWNGRADED Low→QA at Stage 2 (PARTIAL match against "Oracle Data Staleness").
- H-1 → survives (no scope carve-out covers init races; only an invariant which `readme_invariant_check` doesn't trigger on).
- QA records=0 → survives as QA.

Projected v0.1.9 SUBMIT bucket on Reflector: 8 findings (was 10).

---

## 10. Memory system

Path: `/Users/mac/.claude/projects/-Users-mac-Desktop-pashov2-0/memory/`

This directory exists but is currently empty on this machine. The memory system supports four file types: `user`, `feedback`, `project`, `reference`. Each memory is a frontmatter-tagged `.md` file plus a one-line index entry in `memory/MEMORY.md`.

If you start fresh on the new Mac:
- Create `/Users/mac/.claude/projects/<project-id>/memory/` (the project-id will differ — Claude Code derives it from the working directory path).
- Re-establish memories from this handoff doc as needed:
  - `user_role.md` (type=user): Daniel — building Rust audit tooling, iterates Argus driven by real Code4rena failure data.
  - `feedback_terse.md` (type=feedback): User prefers terse responses, no trailing summaries, action-over-planning. Why: explicit course corrections in this session ("push v0.1.7", "i can test it now"). How to apply: skip preamble, jump to tool calls.
  - `project_argus_focus.md` (type=project): Argus is the user's primary in-flight project; v0.1.9 just shipped 2026-05-06, focused on Reflector lessons. Why: 8-version iteration arc with calibration tied to specific contest runs. How to apply: when user says "test on X", they mean run Argus on X and capture the new failure mode for the next release.
  - `reference_test_targets.md` (type=reference): test target paths — `/Users/mac/Documents/rust-test/vault-protocol/`, `/Users/mac/Documents/2025-11-swafe/`, `/Users/mac/Documents/2025-10-reflector/`.

---

## 11. Operating rules from `argus/CLAUDE.md`

When extending Argus on the new Mac, follow these:

- **One skill, one purpose.** Argus does end-to-end Rust audit + fix verification — that is the entire scope. Do not turn it into a multi-skill marketplace.
- **`SKILL.md` stays under 200 lines.** All detail goes to `references/`. New stages, new angles, new platforms each get their own file.
- **VERSION bump on any user-visible change.** Update `CHANGELOG.md` BEFORE the change is considered complete. Never modify entries for already-released versions.
- **Code citations always include `file:line`.** Prose alone is not evidence. Code samples must be valid Rust (parseable by `rustc --crate-type lib`).
- **No fabricated examples.** Outputs must reflect real model behavior on real Rust code.
- **Stage discipline.** New stages need INPUT/OPERATIONS/OUTPUT/VERDICT/KILL CRITERIA/EXIT CONDITION. New stages cannot UPGRADE severity — only Pass D in Stage 4 can. Later stages may DOWNGRADE only.
- **AI-provenance discipline.** Every output to the user carries the manual-validation reminder. Cantina explicitly bans unverified AI output.
- **Live page wins.** Bundled platform criteria are kept current; the live bounty page is authoritative when WebFetch can reach it.

---

## 12. Inputs Argus expects from the user (Stage 1 prompt)

Use `AskUserQuestion` once at the start of Stage 1:

- **target path** (default = cwd) — Rust project root
- **bounty URL** (Stage 6) — Immunefi / HackenProof / Cantina / Sherlock / Code4rena page. If absent: `program-mode = generic`, Stage 6 caps at 65 confidence.
- **GitHub repo URL** (Stage 7). If absent: `dup-mode = local-only`, Stage 7 caps at 75 confidence.
- **manual-validation acknowledgment** (Stage 5 — required for Cantina targets only).

Do not re-ask later.

---

## 13. Outstanding TODOs / unfinished work

- **Validate v0.1.6 + 0.1.7 + 0.1.8 + 0.1.9 against fresh Reflector / swafe re-run**: deferred until user requests. Expected outcome documented in CHANGELOG.
- **v0.1.10 candidate — calibration "impact-amplification" axis**: add to historical-severity heuristic table to fix the under-grading regression (Argus undergraded 3 of 6 caught Reflector findings). Proposed but not pushed pending user confirmation.
- **C4 M-05 (`x_last_price` global-timestamp partial-update)**: missed entirely by Argus on Reflector. Not addressed by v0.1.9. Stage 2 catalogue gap — needs new attack-vector entry (V64 candidate: "global timestamp tracking partial update across multi-asset data").
- **Judge re-pass on Reflector's 4 not-in-C4 findings (H-1, M-1, L-3, QA)**: recommended but not yet done. v0.1.9 should drop M-1 and downgrade L-3, leaving H-1 and QA as the survivors worth Judge-validating.

---

## 14. Useful commands when resuming

```bash
# Inspect skill state on the new Mac
ls /Users/mac/Desktop/pashov2.0/argus/
cat /Users/mac/Desktop/pashov2.0/argus/VERSION
head -60 /Users/mac/Desktop/pashov2.0/argus/CHANGELOG.md

# Run Argus
# In Claude Code:
/argus
# Then provide: target path, bounty URL (or "none"), GitHub repo URL (or "none")

# Run Stage 9 fix-verification only:
/argus-fix-verify
# Then provide: vulnerability description + fix diff

# Test runs to compare against
ls /Users/mac/Documents/2025-10-reflector/argus/20260506T022358Z/8-final/submission-formatted/
ls /Users/mac/Documents/2025-11-swafe/argus/20260505T233135Z/
```

---

## 15. Quick reference — what to read first on the new Mac

When Claude on the new Mac picks up this work, read in order:

1. `HANDOFF.md` (this file) — full context.
2. `argus/SKILL.md` — methodology.
3. `argus/CLAUDE.md` — extension rules.
4. `argus/CHANGELOG.md` — version history (v0.1.9 entry first).
5. `argus/references/hacking-agents/shared-rules.md` — mandatory FINDING schema fields, all the v0.1.7 / 0.1.8 / 0.1.9 discipline.
6. `argus/references/adversarial-review.md` — Stage 4 (longest, most-iterated reference).
7. `argus/references/pipeline-overview.md` — per-stage handoff contract.

That's the minimum context for resuming. Everything else is on-demand via the routing table in `SKILL.md`.

---

> **End of handoff.** If anything in this file is wrong or stale on the new Mac, trust the live files in `argus/` and the live test-run directories — this doc is a snapshot at 2026-05-06, not authoritative.
