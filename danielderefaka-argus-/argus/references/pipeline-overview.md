# Pipeline Overview — handoff contract for every Argus stage

This file is the spine. Read it at Stage 1 and keep it in context for the rest of the run. Every later reference assumes the contract defined here.

## The finding state machine

A finding is created in Stage 2 with ID `F-NN` and is in exactly one state at any moment:

```
candidate ─[3 PoC gate]→ poc-proven ─[4 A/B/C/D]→ adversarial-survived
                            │                              │
                            │ KILL(no-poc)                 │ KILL(challenge holds)
                            ▼                              ▼
                          DISCARD                       DISCARD / DOWNGRADE
                                                           │
                                                           │  Pass D may UPGRADE or DOWNGRADE severity
                                                           ▼
                                                     platform-aligned ─[6]→ program-in-scope ─[7]→ dup-clear ─[8]→ SUBMIT
                                                           │                       │                    │
                                                           │ KILL(auto-invalidator)│ KILL(out-of-scope) │ KILL(hard-dup)
                                                           ▼                       ▼                    ▼
                                                       DISCARD                  DISCARD              DISCARD / REFINE
```

The validity state never reverses. A finding KILL'd at Stage 3 never reappears in Stage 5. **Severity, however, is independent**: Stage 4 Pass D re-grades severity from the verified attack path, and may UPGRADE as well as DOWNGRADE. The Stage-2 claimed severity is not a ceiling.

Stage 9 (fix verification) is independent — it consumes a vulnerability description + a fix diff and produces a `PASS | FAIL | NEEDS REVIEW` verdict outside the validity state machine.

## Stage contract template

Every stage obeys this template:

```
STAGE N — <name>
INPUT:    <prior stage artifacts + source files allowed>
OPERATIONS: <what the stage does>
OUTPUT:   <files written under $RUN_DIR/<N>-<slug>/>
VERDICT:  per-finding ADVANCE | DOWNGRADE(severity) | KILL(reason)
KILL CRITERIA: <hard rules that drop a finding>
EXIT CONDITION: <when the stage is allowed to end>
```

A stage ends only when every input finding has a verdict file. No "we'll get to it later".

## Stage 0 — Cost Preview (runs BEFORE Stage 1)

**v0.5.0** — Stage 0 also bootstraps the checkpoint manifest at `$RUN_DIR/_manifest.json` per [`checkpoint-protocol.md`](checkpoint-protocol.md). If the manifest already exists at the supplied `$RUN_DIR`, Stage 0 defers to `/argus-resume <run-dir>` instead.

```
INPUT:    user-supplied target path, bounty URL (optional), GitHub repo URL (optional)
OPERATIONS:
  - if $RUN_DIR/_manifest.json exists → defer to /argus-resume (DO NOT overwrite)
  - run scripts/enumerate.sh <target> > /tmp/argus-enum-<timestamp>.txt
  - run scripts/estimate-cost.py <target> --enumerate-output /tmp/argus-enum-<timestamp>.txt \
        --depth-tier <light|core|thorough> [--bounty-url-set] [--dup-mode local-only|full]
  - capture the structured cost-preview output
  - use AskUserQuestion (or codex_driver.py ask under Codex) to present the preview and collect:
      [A] Proceed with full audit
      [B] Cap at Stage N — stop after stage N if cost-tracking exceeds estimate by >20%
      [C] Reduce scope — re-run estimator with --scope <subset>
      [D] Cancel — abort before Stage 1
  - bootstrap manifest: codex_driver.py manifest --run-dir $RUN_DIR --init \
        --platform <claude|codex> --mode <smart-contract|infra> --depth-tier <tier> \
        --project-root <abs> --git-commit <sha> [--bounty-url <url>]
  - mark stage 0 completed: codex_driver.py manifest --end-stage 0 --status completed \
        --output-files "preview.md,depth-tier.txt[,cap.txt]"
OUTPUT:
  $RUN_DIR/_manifest.json               — checkpoint manifest (bootstrap entry + Stage 0 completion)
  $RUN_DIR/0-cost-preview/preview.md    — the full cost-preview text + user's choice
  $RUN_DIR/0-cost-preview/depth-tier.txt — light | core | thorough
  $RUN_DIR/0-cost-preview/cap.txt       — written if user picked [B], specifies stage N
VERDICT:
  PROCEED       — user picked [A]; continue to Stage 1
  CAPPED(N)     — user picked [B]; pipeline stops after stage N
  RESCOPED      — user picked [C]; re-estimate with reduced scope and re-ask
  CANCELLED     — user picked [D]; abort pipeline before any artifacts written
EXIT CONDITION: cost preview written AND user choice captured AND manifest entry sealed.
```

### Per-stage manifest discipline (v0.5.0)

Every stage MUST surround its work with manifest writes:

```bash
# At stage start:
python3 $SKILL_DIR/scripts/codex_driver.py manifest --run-dir $RUN_DIR \
    --start-stage <N> --name <stage-name> [--tokens-in-est X --tokens-out-est Y]

# ... stage work ...

# At stage end (success):
python3 $SKILL_DIR/scripts/codex_driver.py manifest --run-dir $RUN_DIR \
    --end-stage <N> --status completed \
    --output-files "<comma-separated list of files actually written>" \
    [--tokens-in-actual X --tokens-out-actual Y]

# At stage end (failure):
python3 $SKILL_DIR/scripts/codex_driver.py manifest --run-dir $RUN_DIR \
    --end-stage <N> --status failed --note "<one-line reason>"
```

The manifest is the authority for `/argus-resume` and for Stage 8's final estimate-vs-actual cost reconciliation. Skipping manifest writes breaks resumability.

Cost preview is mandatory even in auto-mode. Cost authorization is the user's call, not the orchestrator's.

If the user cancels, do not write any subsequent stage output. The only artifact left in `$RUN_DIR/` is `0-cost-preview/preview.md` for the audit trail.

The cost preview's structure (per references/cost-estimation.md):
- Codebase metrics (nSLOC, file count, project shape, test coverage, unsafe count, git commits, finding-count estimate)
- Per-stage table (input tokens, output tokens, wall-clock minutes, cost range low–high)
- Subscription / API estimates (% of Pro / Max-5x / Max-20x 5h windows)
- Cost drivers specific to this run (Anchor project shape, large codebase, no-bounty-URL, etc.)
- Notes (Stage 4 is the most expensive, ±30% accuracy disclaimer)

**v0.6.0 — Pre-hunt vetting supplement**: When a bounty URL is supplied and `program-mode != generic`, Stage 0 ALSO runs [`references/pre-hunt-vetting.md`](pre-hunt-vetting.md) BEFORE the AskUserQuestion. The vetting report (`$RUN_DIR/0-cost-preview/vetting.md`) assesses P(fair treatment) across 5 signals (REP, SCOPE, PAY, EST, TRES) and surfaces red flags to the user alongside the cost preview. The user sees cost AND trustworthiness before authorizing the pipeline. Vetting score does not override user choice — RED programs are flagged but the user decides.

## Stage 0.5 — Signal Assessment (NEW v0.6.0)

```
INPUT:    Stage 0 output (project root, git SHA), source tree
OPERATIONS:
  - run mechanical signal extraction against the source tree:
      Complexity signal (nSLOC, crate count, multi-component, external integrations, async runtime)
      Innovation signal (novel consensus, ZK, new VM, custom crypto, no prior-art deployments)
      Optimization signal (unsafe density, inline assembly, manual memory, hand-written math, SIMD)
      Code Quality / Audit History signal (comment quality, naming, test coverage, Clippy, prior audits)
  - classify each signal on a 3-point scale (LOW / MEDIUM / HIGH)
  - compute composite bug-density prediction (CMPLX×0.40 + INNOV×0.30 + OPT×0.15 + QUAL×0.15)
  - auto-detect temporal signals: project age (first commit → now), days since last upgrade (git tags), fork ancestry (Stage 1 fork-ancestry check)
  - select strategy: Digger (high signal, mature) / Speedrunner (<30d old OR low signal) / Watchman supplement (<14d since upgrade) / Differ supplement (fork ancestry)
  - write signal-report.md
OUTPUT:
  $RUN_DIR/0-5-signal/signal-report.md   — 4-signal scores + composite + strategy selection + temporal signals
VERDICT:   STRATEGY = <digger | speedrunner | watchman | differ>; BUG_DENSITY = <low | medium | high | very-high>
EXIT CONDITION: signal-report.md written with all 4 signals scored and strategy selected.
```

Full methodology: `references/signal-assessment.md`. Strategy routing: `references/hunting-strategies.md`.

## Stage 1 — Protocol Mapping

**v0.4.0 — Threat-Model-First**: Stage 1 reads [`references/threat-model-first.md`](threat-model-first.md) at start and executes its 6-step ordered procedure (actors → boundaries → 10-point attack-surface walk → entry points → invariants → hot zones). Legacy entry-points-first ordering is rejected.

```
INPUT:    project source tree (Rust crates, workspace), Cargo.toml(s), README, docs/, on-chain integration hints
OPERATIONS:
  Phase A — Threat model (NEW v0.4.0, before surface enumeration):
  - identify actors (per threat-model-first.md § Step 1)
  - identify trust boundaries (per § Step 2)
  - walk the 10-point OpenZeppelin attack-surface checklist (per § Step 3)

  Phase B — Surface enumeration (informed by Phase A):
  - enumerate the workspace: crates, binaries, programs, pallets, contracts
  - identify the runtime (Solana / Anchor / CosmWasm / Substrate / generic Rust service)
  - extract entry points: instruction handlers, message handlers, extrinsics, public HTTP/RPC, exposed traits
  - classify entry points: permissionless | role-gated (signer/authority) | privileged
  - extract invariants: doc-stated, NatSpec-equivalent (`/// invariant:` comments), arithmetic bounds, conservation laws (lamports/coins in == out); each invariant carries `actor_that_could_violate` + `boundary_that_enforces`
  - identify external integrations: CPI targets, oracle reads, off-chain feeds, IBC channels, RPC dependencies
  - identify test gaps: presence of unit / integration / fuzz / property / proptest / kani targets
  - identify hot zones: SURFACE-WEIGHTED ranking (surface_points × 2 + boundaries × 3 + untrusted_actors × 2 + untested_lines × 0.01 + churn × 0.05); legacy churn-only ranking deprecated
OUTPUT:
  $RUN_DIR/1-protocol-map/overview.md       — what this protocol does in 200 lines max
  $RUN_DIR/1-protocol-map/attack-surface.md — entry points table + trust boundaries
  $RUN_DIR/1-protocol-map/trust-model.md    — actors and what they can do, and what would break if any actor is malicious
  $RUN_DIR/1-protocol-map/entry-points.md   — every public/external function, classified
  $RUN_DIR/1-protocol-map/invariants.md     — doc-stated, code-extracted, and inferred invariants
  $RUN_DIR/1-protocol-map/hot-zones.md      — ranked list of files/modules to focus Stage 2 on
VERDICT: N/A (no findings yet) — stage produces a briefing, not findings.
EXIT CONDITION: all six map files written and non-empty.
```

The output of Stage 1 is the *audit briefing*. Stage 2 must use it to scope its search; Stage 4 will use the trust model to challenge findings; Stage 6 will reuse the entry-point table for in-scope checks.

**v0.6.0 — Deployed-code verification supplement**: After protocol mapping completes, Stage 1 ALSO runs [`references/deployed-code-verification.md`](deployed-code-verification.md). This verifies that the repository source code matches what is actually deployed on-chain — preventing dead-code audits (repo ahead of deployed) and proxy-behind-implementation divergence. Per-chain procedures for Solana, CosmWasm, Substrate, and generic Rust services. Outputs `$RUN_DIR/1-protocol-map/deployed-code-report.md` with per-identifier verification status (VERIFIED / MISMATCH / UNVERIFIABLE). A PROGRAM_CLOSED result HALTS the pipeline. STALE_REPO results in scope adjustment (post-deployment changes excluded from Stage 2). UNVERIFIED results in a `deployed-code: UNVERIFIED` confidence flag on all findings.

## Stage 2 — Rust Audit / Candidate Finding Generation

```
INPUT:    Stage 1 output (full), project source files, matching protocol-type profile from rust-protocol-types.md
OPERATIONS:
  - dispatch the hacking angles from SKILL.md Stage 2 dispatch table (up to 12 parallel, including Differ v0.6.0)
    - Path A (≤10 source files): run angles sequentially in the orchestrator
    - Path B (>10 source files): dispatch all 8 as parallel general-purpose subagents in ONE message
  - each angle reads its bundle (hot-zones, entry-points, invariants, trust-model + this guidance + matched protocol profile)
  - each angle produces structured FINDING / LEAD blocks per the Shared Rules format with `group_key = crate::module::function|bug_class`
  - orchestrator dedupes by group_key (exact match, then synonymous bug_class merge)
  - orchestrator promotes LEADs to FINDINGs ONLY on cross-angle convergence (2+ angles flagged same group_key as LEAD) → confidence 75
  - orchestrator checks for composite chains: A's output feeds B's precondition AND combined impact > either alone
OUTPUT:
  $RUN_DIR/2-candidate-findings/F-NN.md  — one file per surviving FINDING
  $RUN_DIR/2-candidate-findings/leads.md — all unpromoted LEADs in a single file, sorted by group_key
  Each F-NN.md has: title, location(file:line), root cause, exploit path, proof, claimed_severity, confidence (0-100), stage1_ref, test_coverage, [angles: N]
VERDICT:  every FINDING starts at state `candidate` and proceeds to Stage 3.
KILL CRITERIA: a candidate without a `proof:` field is demoted to LEAD; a candidate without file:line citation is rejected at creation.
EXIT CONDITION: every angle has returned, dedup has run, and per-finding F-NN.md files exist.
```

Cap candidate FINDINGs at ~30 to stay focused. If more, prune by claimed severity and Stage-1 alignment.

### Stage 2 file-hash caching (NEW v0.1.10 — opt-in)

When `--cache` flag is passed to `/argus`, the orchestrator caches per-angle outputs by file hash:

- **Cache key**: `sha256("argus_v{VERSION}::{angle_name}::{file_path}::{file_content_sha256}")`.
- **Cache location**: `$HOME/.cache/argus/stage2/<key>.json`.
- **Cache value**: the angle's structured FINDING / LEAD output for that file.
- **Eviction**: LRU; max 10 GB total cache size.

Behavior:
- On Stage 2 dispatch, the orchestrator computes the cache key for each (angle, file) pair.
- Cache hit → reuse cached output, log `cache: hit` in run metadata.
- Cache miss → dispatch subagent; on success, write the result to cache.
- Cache is keyed by Argus version: a v0.1.10 run will not reuse a v0.1.9 cache entry. Forces re-audit when angle definitions change.

Discipline: caching is OFF by default (correctness > speed). Enable via `--cache` flag at run start, or `cache: enabled` in Stage 0 run-config. Surfaces in mode-warnings if enabled.

### Cross-program / multi-contract scope (NEW v0.1.10)

For Solana protocols spanning multiple programs (CPI graph) OR CosmWasm protocols spanning multiple contracts (`WasmMsg` graph), Stage 1 enumerates ALL programs/contracts in the workspace and their cross-call dependencies. Stage 2 angles can read across programs/contracts.

Stage 1 produces an additional file:

```
$RUN_DIR/1-protocol-map/cpi-graph.md
```

Schema:

```markdown
# CPI / Cross-call graph

## Programs in scope
| Program | Crate | Role |
|---------|-------|------|
| Vault | crates/vault | core deposit/withdraw |
| Strategy | crates/strategy | external-yield CPI from Vault |
| Oracle | crates/oracle | Pyth wrapper read by Vault |

## Edges
| Caller | Callee | Trust assumption |
|--------|--------|------------------|
| Vault::deposit | Strategy::deposit | "Strategy reports correct gain" |
| Vault::withdraw | Oracle::get_price | "Oracle returns fresh, valid price" |
| Strategy::harvest | Vault::report_gain | "Vault correctly accrues to LP shares" |

## Cross-program invariants
- (Vault.total_assets() == Strategy.locked_balance() + Vault.idle_balance()) at every block.
- (Oracle.last_update_ts >= Vault.cached_oracle_ts) at every Vault.deposit / Vault.withdraw.
```

Stage 2's Auth/Account, Execution Trace, and Invariant angles specifically:
- Read across programs to trace CPI authority chains.
- Look for cross-program invariants that hold ONLY when both programs cooperate.
- Flag findings where one program assumes another's behavior without the assumption being verifiable.

Cross-program findings carry a `crosses_programs: [<list>]` field in their FINDING block.

## Stage 3 — PoC Generation (the GATE)

```
INPUT:    every F-NN.md in candidate state from Stage 2
OPERATIONS:
  PRE-FLIGHT — run scripts/install-deps.sh <project-root> --dry-run. If exit 2 (missing tools),
  use AskUserQuestion to ask: install / skip-with-tier-3-cap / cancel. On install, run --install,
  then --dry-run again to verify. See poc-standards.md "Pre-flight" section for the full rules.

  for each candidate, attempt — in this preference order — to produce proof:
    (a) Tier-1 E2E test against the real harness — PRIMARY TARGET. Includes RPC discovery
        (Anchor.toml, solana config, solana-test-validator, devnet, mainnet-fork) and actually
        running the test, not just writing it. See poc-standards.md "Tier 1 — End-to-end" + "RPC
        discovery" sections for the full discovery-and-run procedure.
    (b) Tier-2 custom integration test — fallback ONLY when Tier-1 RPC discovery genuinely failed
    (c) Tier-3 minimal reproducer — THIS IS THE FLOOR for any non-allowlist finding (state-only sim)
    (d) Tier-4 written derivation — RESTRICTED; permitted only when the 8-question Tier-3-buildable
        self-audit (in poc-standards.md) confirms infeasibility on every question

  CERTAINTY FLOOR: every Stage 3 verdict assigns a certainty score (0-100):
    Tier 1 actually-run E2E:          90-100
    Tier 2 integration:                75-89
    Tier 3 minimal reproducer:         60-79
    Tier 4 written derivation:         30-59
    Exempt allowlist (citation-only):  75 baseline
  Findings with certainty < 80 → Stage 3 returns DOWNGRADE(refine), NOT ADVANCE. Weak proof
  does not advance to Stage 4. The 80-floor protects Stage 4 from the F-03/F-10-class false
  positives where citation-only proofs slipped through.

  Tier-1 verdict.md MUST include the RPC-discovery checklist (cluster identified, validator
  started, test command run, output captured, buggy/fix results). Any unchecked box → drop to
  Tier 2 and re-grade certainty.

  Tier 2/3/4 verdict.md MUST include a "Tier-1 attempted" section enumerating RPC discovery
  steps tried and the specific failure. Skipping Tier-1 RPC discovery entirely is a procedural
  failure — Stage 3 must re-attempt before accepting the verdict.

  Before writing any Tier-4 verdict, run the 8-question self-audit (math reduction / single-fn /
  two-fn sequencing / struct invariant / pure helper / state machine / borsh round-trip /
  crypto primitive). If ANY question is "yes", Tier-3 is buildable; write the reproducer. The
  self-audit table is mandatory in every Tier-4 verdict.md.

  When 2+ findings reduce to math/state on the same struct family, place their tests in a
  single shared reproducer crate at $RUN_DIR/3-poc/_<class>-reproducer/.

  WRITE poc.* (the actual file the test runs from), repro.md (steps to run + captured output),
  verdict.md (the gate decision + RPC-discovery checklist OR Tier-1-attempted section)
OUTPUT:
  $RUN_DIR/3-poc/F-NN/poc.rs (or .toml, or whichever file is needed)
  $RUN_DIR/3-poc/F-NN/repro.md   — exact reproduction steps + captured stdout/stderr
  $RUN_DIR/3-poc/F-NN/verdict.md — STATUS, certainty score, RPC-discovery checklist
VERDICT (per finding):
  ADVANCE         — PoC runs end-to-end AND certainty ≥ 80 AND demonstrated impact matches claim
  DOWNGRADE(sev)  — PoC produces weaker impact than claimed; severity lowered to match
  DOWNGRADE(refine) — certainty < 80; finding does not advance to Stage 4 with weak proof
  KILL(no-poc)    — no PoC tier worked AND not in the poc-exempt allowlist (see poc-standards.md)
KILL CRITERIA:
  - PoC requires assumptions inconsistent with on-chain reality
  - PoC requires a TRUSTED role to do something the trust model says they would never do
  - "PoC" is hand-waved English that does not run
  - Tier-1 was not attempted AND the bug requires real chain state (procedural failure)
EXIT CONDITION: every Stage 2 finding has a verdict.md with certainty score.
```

This is the strongest gate in the pipeline. A finding without a real, runnable PoC has not earned the right to advance. The exception list in `poc-standards.md` is short and explicit — do not expand it.

## Stage 4 — Adversarial Challenge + Severity Calibration

```
INPUT:    every F-NN that ADVANCED or DOWNGRADED out of Stage 3
PRE-CHECKS (mandatory; surface in verdict file before Pass A):
  - Docstring-disclaimer pre-check: for every cited function in the finding's location,
    quote any /// disclaimer verbatim. If a disclaimer is present and the finding claims
    "this function should enforce X", SC-2 MUST appear in Pass A's top-4.
  - Comparator-claim audit: if the finding's impact case relies on "external system X
    behaves differently", check whether the comparator's source is cited. Uncited comparator
    claims force Pass C in CLOSE_CALL_REVIEW (comparator-claim) mode.
OPERATIONS: for each finding, run the four passes in adversarial-review.md
  - Pass A: Selector MUST rank exactly 4 generic invalidators from the catalogue (UP/CP/DT/
    EG/US/SH/DI/TI/SC/IM/AM/OS/TR), checks top-2, passes bottom-2 to Pass C. Fewer than 4
    ranked entries = procedural-thinness failure → Pass C MUST fire.
  - Pass B: Issue-specific generator produces ≥3 new challenges (HIGH/MED/LOW confidence)
    and verifies them. Includes a comparator-verification challenge when finding makes a
    cross-system claim. Fewer than 3 challenges = procedural-thinness failure → Pass C
    MUST fire and explicitly account for missing slots.
  - Pass C: Symmetric Neutral Judge fires on:
      - HOLDS_REVIEW: any HIGH/MED HOLDS in Pass A or Pass B
      - CLOSE_CALL_REVIEW (uncertain): any UNCERTAIN
      - CLOSE_CALL_REVIEW (rejected-high): all FAILS but at least one was HIGH-conf at gen
      - CLOSE_CALL_REVIEW (procedural): Pass A < 4 OR Pass B < 3
      - CLOSE_CALL_REVIEW (comparator-claim): uncited comparator claim in finding
    Skip ONLY when all gates pass: clean walk + 4 Pass A + 3+ Pass B + no uncited comparator.
    HIGH-HOLDS handling: judge has 3 legitimate responses — INVALID, DOWNGRADE, or VALID
    with explicit `high_holds_overrides` field listing each HIGH-conf HOLDS that was
    overridden and the specific evidence making the orchestrator's reading wrong. "Stage 8
    will figure it out" / "let later stages handle" are REJECTED override justifications.
    Procedural-thinness mode: judge MUST generate the missing Pass A invalidators and Pass B
    challenges to complete the walk before rendering verdict.
  - Pass D: Severity Calibrator independently grades severity from the verified attack path
    (may UPGRADE), then clamps against caps (TRUSTED-role → INFORMATIONAL, trade-off → LOW,
    judge stricter → judge target).
OUTPUT:   $RUN_DIR/4-adversarial/F-NN.md — docstring-disclaimer pre-check + comparator audit +
          Pass A table (4 rows) + Pass B challenges (≥3) + Pass C judgment with high_holds_overrides
          if applicable + Pass D calibration with severity-divergence
VERDICT:
  ADVANCE         — finding survives every challenge; severity = Pass D calibrated value (may UPGRADE)
  DOWNGRADE(sev)  — a challenge holds OR Pass D recalibrates lower; severity = clamped value
  KILL(reason)    — Pass A HOLDS on EG/US/OS/SC/DT-1/DT-3/SH/TR-1 (HIGH conf), OR Pass C judge
                    returns INVALID with HIGH confidence
KILL CRITERIA:
  - Pass A HOLDS at HIGH confidence with cited evidence in EG/US/OS/SC/DT-1/DT-3/SH/TR-1 category
  - Pass C judge returns INVALID with HIGH confidence after weighing all challenges + advisory
SEVERITY HANDOFF: the value advancing to Stage 5 is `final_severity` from Pass D (after clamps),
NOT the Stage-2 claim. May be HIGHER than claimed.
EXIT CONDITION: every Stage 3 advancing finding has a Stage 4 verdict file with all mandatory
sections populated. Verdict files missing the docstring-disclaimer pre-check, comparator audit,
4-row Pass A, ≥3-row Pass B, or required high_holds_overrides are invalid and Stage 4 re-runs.
```

## Stage 5 — Platform Validation

```
INPUT:    every F-NN that ADVANCED or DOWNGRADED out of Stage 4 + the platform context (from bounty URL)
OPERATIONS:
  - identify platform from bounty URL → load matching platform-criteria/<platform>.md
  - if platform is Cantina (BB or Comp): use AskUserQuestion to collect manual-validation acknowledgment; abort run on `No`
  - WebFetch the platform's live criteria URL once; if it differs from bundled criteria, log divergence and apply live rules
  - per finding: Phase 1 auto-invalidator scan, Phase 2 severity alignment, Phase 3 quality signals, Phase 4 score (subtractive 100→5), Phase 5 verdict mapping
OUTPUT:   $RUN_DIR/5-platform/F-NN.md — per-finding 5-phase output
          $RUN_DIR/5-platform/cantina-acknowledgment.md (if Cantina target)
          $RUN_DIR/5-platform/criteria-divergence.md (if WebFetch differs from bundled)
VERDICT:
  ADVANCE         — predicted-valid (score ≥ 70) AND severity aligned
  DOWNGRADE(sev)  — score 40-69, or severity inflated by ≥1 level
  KILL(rejected)  — auto-invalidator triggers INVALID, OR score < 40, OR Cantina target without manual-validation acknowledgment
KILL CRITERIA: per-platform AI-N rule list in platform-criteria/<platform>.md; Cantina AI-3 mandates the acknowledgment gate.
EXIT CONDITION: every Stage 4 advancing finding has a Stage 5 verdict.
```

## Stage 6 — Program-Specific Triage

```
INPUT:    every F-NN that ADVANCED or DOWNGRADED out of Stage 5 + the bounty URL (collected at run start)
OPERATIONS:
  - WebFetch the bounty page; cache to $RUN_DIR/6-program/bounty-page.md
  - extract: in-scope assets/components, in-scope impact categories, severity-to-payout mapping, exclusions, PoC requirements, special rules
  - for each finding, decide: in-scope-target? in-scope-impact? meets program PoC requirements? hits an exclusion?
OUTPUT:
  $RUN_DIR/6-program/bounty-page.md — cached, dated extraction
  $RUN_DIR/6-program/F-NN.md        — per-finding triage decision with quoted scope text
VERDICT:
  ADVANCE                     — target & impact in scope, no exclusion hit, PoC requirement met
  DOWNGRADE(impact-mapping)   — finding real but program only pays for smaller impact than claimed; remap and lower severity per program payout
  DOWNGRADE(refine)           — borderline result + reversibility rule (HackenProof-inherited) prefers requesting evidence over killing
  KILL(out-of-scope)          — target component or impact category is excluded
  KILL(known-issue)           — exact root cause + location matches program's published known-issues list
  KILL(version-mismatch)      — bug does not exist at the program's applicable commit/tag
REVERSIBILITY RULE: when result is borderline AND confidence is LOW, default to DOWNGRADE(refine) over KILL.
KILL CRITERIA: program scope is the source of truth; program-specific exclusions override generic platform assumptions.
EXIT CONDITION: every Stage 5 advancing finding has a Stage 6 verdict AND bounty-page.md exists.
```

If the bounty URL was not supplied, write `bounty-page.md` with the line `program-mode: generic — no bounty URL supplied at run start. Stage 6 verdicts use platform default scope rules; reviewers must re-validate scope before submission.` and continue. Stage 8 will surface this as a confidence reduction.

## Stage 7 — Duplication Triage

```
INPUT:    every F-NN that ADVANCED or DOWNGRADED out of Stage 6 + the GitHub repo URL
OPERATIONS: run the probes in duplication-check.md against the target repo (issues, PRs, commits, comments, code blame). For each finding, classify the duplication signal.
OUTPUT:   $RUN_DIR/7-duplication/F-NN.md — probes run, hits found (with links), classification, recommendation
VERDICT:
  ADVANCE          — no clear duplicate evidence; finding is fresh
  DOWNGRADE(refine)— partial overlap (related discussion exists; finding's framing must change to differentiate)
  KILL(hard-dup)   — strong evidence the issue is already known, already reported, already fixed in a recent commit, or has an open PR addressing it
KILL CRITERIA:
  - a recent commit / merged PR fixes the exact root cause at the exact location
  - a public issue describes the exact attack with the exact precondition
  - a referenced audit report (linked from the repo) lists the same finding
EXIT CONDITION: every Stage 6 advancing finding has a Stage 7 verdict.
```

## Stage 8 — Final Submission-Grade Output

```
INPUT:    every F-NN file from Stages 2–7
OPERATIONS:
  Phase 8a-pre — Citation-overlap dedupe (MANDATORY before Phase 8a):
    For every pair of Stage 7 ADVANCE findings, compute citation overlap (shared file:line
    references / total cited lines). Resolution per output-format.md:
      overlap ≥ 0.5 + same root cause          → MERGE into one finding
      overlap ≥ 0.5 + different root cause     → STAGE-4 RE-PASS (joint Pass C only) to
                                                  resolve "one bug or two?" with verdict
                                                  MERGE / DISTINCT / KILL_ONE
      0.2 ≤ overlap < 0.5                      → FLAG (cross-reference both findings)
      overlap < 0.2                            → no action
    Output: $RUN_DIR/8-final/_dedupe-summary.md + (if re-pass triggered)
            $RUN_DIR/8-final/_dedupe-repass/F-A_F-B.md per pair.
  Phase 8a — Triage:
    aggregate (post-dedupe), rank, format per output-format.md. Sort SUBMIT findings by
    (severity desc, confidence desc, dup-risk asc).
  Phase 8b — Report formatting (skip if SUBMIT bucket is empty):
    use AskUserQuestion to ask which platform's report template to format SUBMIT findings in.
    Options: Code4rena | Sherlock | Cantina | Immunefi | HackenProof | CodeHawks | Generic | Skip.
    Read references/report-templates/<platform>.md and write per-finding writeups under
    $RUN_DIR/8-final/submission-formatted/F-NN.md plus an index.md.
OUTPUT:
  $RUN_DIR/8-final/_dedupe-summary.md          — citation-overlap pairs and resolutions
  $RUN_DIR/8-final/_dedupe-repass/F-A_F-B.md   — per-pair re-pass verdicts (if any)
  $RUN_DIR/8-final/submission-grade.md         — Stage-7-ADVANCE findings (post-dedupe)
  $RUN_DIR/8-final/refine.md                   — DOWNGRADE'd findings with refinement plan
  $RUN_DIR/8-final/discard.md                  — KILL'd findings with stage + reason
  $RUN_DIR/8-final/submission-formatted/F-NN.md — per-finding template-formatted writeups
  $RUN_DIR/8-final/submission-formatted/index.md — sorted submission order with [H-N]/[M-N] IDs
EXIT CONDITION:
  - dedupe summary written before triage files
  - every finding from Stage 2 appears in exactly one of the three triage files (post-dedupe)
  - submission-grade.md may be empty; this is allowed and a successful run when nothing survived
  - if SUBMIT non-empty AND user picked a template, every SUBMIT finding has a submission-formatted F-NN.md
```

After writing all Stage 8 files, print the terminal summary defined in `output-format.md` (counts, SUBMIT titles, mode warnings, formatted-output path if Phase 8b ran, AI-provenance reminder).

## Stage 9 — Fix Verification (OPTIONAL)

Independent of Stages 1-8. Runs only when the user invokes Argus to verify a fix has been correctly applied.

```
INPUT:    a vulnerability description (text, F-NN reference, CVE, advisory, or plain English) AND a fix (git diff, commit range, branch comparison, or PR number)
OPERATIONS: 6 phases per fix-verification.md
  - Phase 1: Understand the vulnerability (root cause, attack vector, affected component, impact)
  - Phase 2: Analyze the fix (classify each change as direct/supporting/unrelated; map to root cause)
  - Phase 3: Completeness checklist (root cause + coverage + edge cases + error handling)
  - Phase 4: Regression checklist (interface + behavior + trust + integration + tests)
  - Phase 5: Smart-contract-specific checks (re-entry + auth + arithmetic + state + external + token + upgrade)
  - Phase 6: Verdict (PASS / FAIL / NEEDS REVIEW)
OUTPUT:   $RUN_DIR/9-fix-verification/F-NN.md
VERDICT:
  PASS          — root cause addressed, all instances covered, no regressions, no similar patterns elsewhere
  FAIL          — root cause not addressed, fix incomplete, or fix introduces a regression
  NEEDS REVIEW  — fix looks correct but aspects you cannot fully verify (complex economic logic, external system behavior, production-state dependencies)
EXIT CONDITION: verdict file written.
```

Stage 9 inherits the AI-provenance reminder: even a PASS is an AI-generated draft. The user remains responsible for manually reviewing the diff before merging.

## Cross-stage invariants

- **One file per finding at stages 4-7 (NEW v0.1.11 — procedural).** Stages 4 / 5 / 6 / 7 produce ONE `F-NN.md` PER finding entering that stage. A single `_summary.md` is INVALID. Before advancing to the next stage, the orchestrator validates: `find $RUN_DIR/<stage> -name 'F-*.md' | wc -l ≥ count of findings entering this stage`. If short, the missing per-finding files are produced before advancing. This rule prevents the v0.1.10 monero-oxide failure mode where Stages 4-7 produced collapsed summaries and the rigorous per-finding gates (Pre-Pass External Research, 3-judge Pass C, rubric scorecard, whitelist-mode impact match) never ran.
- **No data re-derivation.** Stage 4 reads Stage 3's `verdict.md`; it does not re-run the PoC.
- **Severity is independent at Pass D.** Pass D may UPGRADE as well as DOWNGRADE — claimed Stage-2 severity is NOT the ceiling. The pipeline's earlier rule ("severity only goes down") was wrong; Stage 4 fixes the asymmetry. After Pass D, severity may only go *down* in Stages 5-7 (platform / program / dup downgrades), never back up.
- **Code citation is always required.** Every claim in every stage cites `file:line` from the project source, not from prose.
- **Dead findings stay dead.** A KILL'd finding does not appear in later stages' verdict files. It only appears in `discard.md` at Stage 8.
- **Subagent results are advisory.** If you delegate sub-work in a stage, the orchestrator must verify any decisive claim against the source code itself. (X-Ray's "code reading wins" principle.)
- **AI-provenance reminder is mandatory in Stage 8 output.** No SUBMIT finding presents as a finished submission. Manual validation is the user's responsibility.
- **Cantina target = mandatory acknowledgment gate.** Stage 5 will not ADVANCE Cantina-platform findings without the user's explicit manual-validation acknowledgment.
