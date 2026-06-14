# REFINE-Bucket Auto-Loop (`infra` mode, NEW v0.3.3)

> When Stage 6/7/8 lands a finding in REFINE with a "needs X verification" rationale, the orchestrator **does not stop**. It auto-invokes a refinement sub-stage that builds the X verification, runs it, and resolves the finding to SUBMIT / DISCARD / INCONCLUSIVE. Manual review is reserved for cases the auto-loop genuinely cannot resolve.
>
> **Motivating gap**: in the 2026-05-12 monero-oxide run, 5 findings landed in REFINE with notes like "needs wallet2-comparator verification", "partial-dup of open #152", "Scanner quadratic CPU DoS; no matching bounty tier". Pre-v0.3.3 Argus dropped these in the user's lap. v0.3.3 makes the orchestrator attempt each refinement automatically.

## Trigger

The refine-loop fires at the end of Stage 8 Phase 8a for every finding in `$RUN_DIR/8-final/refine.md` whose REFINE rationale matches a known refinement pattern (see §"Refinement patterns" below).

It does NOT fire for:
- KILL'd findings (terminal at the killing stage).
- SUBMIT findings (already advance).
- REFINE findings whose rationale is `human-judgment-required` (e.g., "the bounty page wording is ambiguous, ask the user") — these stay in manual queue.

## Refinement patterns

Each pattern names: a recognition signal, a verification step, and the resolution rule.

### Pattern R1 — "needs comparator verification"

**Recognition**: REFINE rationale contains "needs <comparator> verification" / "compare against <comparator>" / "depends on whether <external system> behaves as claimed".

**Verification**:
1. Identify the comparator (cited external system, e.g., wallet2, OpenZeppelin, Pyth).
2. Spawn a Sonnet subagent with the comparator name + the cited claim + WebSearch / WebFetch / direct comparator-source-clone access.
3. Subagent verifies whether the comparator actually behaves as the finding claims by reading the comparator's source code at the relevant function.
4. Returns: COMPARATOR_BEHAVIOR_MATCHES_CLAIM | COMPARATOR_DIFFERS | COMPARATOR_UNVERIFIABLE.

**Resolution rule**:
| Subagent result | New verdict |
|----------------|-------------|
| MATCHES_CLAIM (comparator behaves as finding describes) | promote finding to SUBMIT (assuming Stage 5/6 gates pass) |
| DIFFERS (comparator doesn't actually exhibit the claimed difference) | DISCARD with reason `comparator-claim-refuted` |
| UNVERIFIABLE | stay REFINE with note `comparator-research-inconclusive` |

**Example from monero-oxide run**: F-05 (phantom WalletOutput via Extra::keys identity-substitution) noted "needs wallet2-comparator verification before submitting". The auto-loop would:
- Identify comparator: `monero-project/monero/src/wallet/wallet2.cpp` `process_unconfirmed`/`process_new_blockchain_entry`
- Spawn subagent with: "verify whether wallet2 emits phantom outputs when ECDH-shared-secret is identity"
- Subagent reads wallet2 source, compares to `monero-oxide/wallet/src/scan.rs:170-199`, returns verdict.

### Pattern R2 — "partial-dup of #<issue>"

**Recognition**: REFINE rationale contains "partial-dup of #N" / "partial-dup of open #N" / "related to existing report #N".

**Verification**:
1. Fetch the cited GitHub issue / PR / advisory via `gh issue view N --comments` or WebFetch.
2. Compare the finding's mechanism (root cause + trigger + impact) against the issue's described mechanism.
3. Decide:
   - **EXACT_DUPLICATE**: same root cause, same trigger, same impact → already-known.
   - **RELATED_DIFFERENT_MECHANISM**: cited issue is in the same area but the new finding's root cause / trigger is genuinely distinct.
   - **RELATED_NARROWER**: new finding is a special case of the cited issue.
   - **RELATED_BROADER**: new finding generalizes the cited issue.

**Resolution rule**:
| Comparison result | New verdict |
|------------------|-------------|
| EXACT_DUPLICATE | DISCARD with reason `dup-of-#N` |
| RELATED_DIFFERENT_MECHANISM | promote to SUBMIT with reframing note explaining the distinction from #N |
| RELATED_NARROWER | DISCARD with reason `subsumed-by-#N` |
| RELATED_BROADER | promote to SUBMIT with reframing note (this is the more-impactful framing) |

**Example from monero-oxide run**: F-02 "Extra::read 40× memory amplification; partial-dup of open #152" — the loop fetches #152, compares mechanism, resolves to one of the four categories above. No manual click-and-read by the user.

### Pattern R3 — "needs live E2E PoC" / "needs runnable reproducer"

**Recognition**: REFINE rationale contains "needs runnable PoC" / "Tier-1-live-e2e not yet built" / "harness compilation failed" (from Stage 3 INCONCLUSIVE with that reason).

**Verification**: invoke the Tier-1-live-e2e build procedure per `e2e-test-discipline.md` per the finding's component type. The orchestrator:
1. Determines the component-type from the cited target's Stage-1 classification.
2. Looks up the E2E pattern from `e2e-test-discipline.md` § per-component-type.
3. Spawns a Sonnet subagent to write the harness per the pattern.
4. Runs `cargo check` → if compilation fails, retry once with error feedback (capped at 3 retries).
5. Runs the harness, captures output.
6. Writes `$RUN_DIR/3-verification/F-NN/e2e/verdict.md` (REPRODUCED / UNREACHABLE / INCONCLUSIVE).

**Resolution rule**:
| E2E verdict | New finding verdict |
|------------|---------------------|
| REPRODUCED | promote to SUBMIT (re-run Stages 4-7 with the harness as evidence) |
| UNREACHABLE | DISCARD with reason `e2e-proved-unreachable` + cite the trigger-API zero-hit grep |
| INCONCLUSIVE | stay REFINE; record reason: `harness_compilation_failed` / `output_ambiguous` / `tool_timeout` |

This is the most important pattern. It's the one that would have automated Codex's F-07 verification: build a project that uses the in-scope crate, exercise the cited API, observe whether the bug fires.

### Pattern R4 — "no matching bounty tier"

**Recognition**: REFINE rationale contains "no matching bounty tier" / "outside bounty payout categories" / "Argus-severity-X but bounty-tier-Y".

**Verification**: WebFetch the bounty page's impact-category list, compare the finding's actual impact (from Stage 4 impact-analysis) against each category, choose the closest fit.

**Resolution rule**:
| Mapping result | New verdict |
|----------------|-------------|
| Bounty category exists at a different (lower) tier | DOWNGRADE the finding's Stage-5 severity to match; advance to SUBMIT at the bounty-supported tier |
| No bounty category fits | DISCARD with reason `out-of-scope-impact-category` |
| Bounty category exists at HIGHER tier than Argus assigned (rare) | promote to SUBMIT at the bounty-supported tier; record the Argus-vs-bounty severity divergence for calibration |

**Example from monero-oxide run**: F-01 "Scanner quadratic CPU DoS; no matching bounty tier" — the loop fetches the Immunefi monero-oxide impact list, checks for "denial of service" / "CPU exhaustion" / "block-stuffing" / "infinite loop" entries, decides whether F-01 maps to one of those at any tier.

### Pattern R5 — "root cause of F-X / F-Y"

**Recognition**: REFINE rationale contains "root cause of F-NN" / "fix-subsumed by F-NN" / "underlying defect for F-NN".

**Verification**: re-run Stage 8 Phase 8a-pre dedupe judge with the explicit hypothesis "F-NN is the root finding; F-X / F-Y are surface manifestations". Apply fix-subsumption check from `output-format.md`.

**Resolution rule**:
| Joint judge result | Action |
|-------------------|--------|
| F-NN's fix subsumes F-X / F-Y | merge F-X / F-Y into F-NN as hardening notes; promote F-NN to SUBMIT |
| F-NN and F-X / F-Y are distinct | promote all to SUBMIT with cross-references |
| F-NN is itself subsumed by F-X | flip the relationship; F-X promotes, F-NN merges |

**Example from monero-oxide run**: F-03 "TransactionPrefix miner-tx unbounded; root cause of F-01/F-02". Auto-loop runs the joint judge with F-01, F-02, F-03 → determines whether fixing F-03's unboundedness kills F-01 and F-02 entirely OR whether F-01 / F-02 have distinct trigger paths.

### Pattern R6 — "needs Stage 1 invariant verification"

**Recognition**: REFINE rationale contains "needs README invariant check" / "documented behavior contradicts finding" / "may be intentional design".

**Verification**: re-run the v0.1.8 `readme_invariant_check` against the finding's mechanism + the v0.1.9 `scope_carveout_check` against the README. Both are pure file-reads; no subagent needed.

**Resolution rule**: per the existing verdict matrices in `shared-rules.md`. Output → SUBMIT / DOWNGRADE / DISCARD.

## Sub-stage execution order

The refine-loop runs as **Stage 8.5** (between Phase 8a and Phase 8b). For each REFINE finding:

```
for finding in $RUN_DIR/8-final/refine.md:
    pattern = match_refinement_pattern(finding.rationale)
    if pattern == None:
        # rationale doesn't match any known auto-loop pattern; keep in REFINE bucket
        continue
    
    result = run_pattern(pattern, finding)
    write $RUN_DIR/8.5-refine-loop/F-NN.md with the loop's verdict + evidence
    
    if result.new_verdict == SUBMIT:
        move finding from refine.md to submission-grade.md
        re-run Phase 8b template formatting for that finding
    elif result.new_verdict == DISCARD:
        move finding from refine.md to discard.md
    elif result.new_verdict == STAY_REFINE:
        update the finding's rationale in refine.md with the loop's note
```

Findings that the loop cannot resolve (no pattern match, INCONCLUSIVE E2E, comparator-unverifiable) stay in REFINE with the loop's note appended. The user reviews these manually — but the set is much smaller than pre-v0.3.3.

## Output schema

`$RUN_DIR/8.5-refine-loop/F-NN.md`:

```markdown
# F-NN — REFINE auto-loop verdict (Stage 8.5)

- **original_refine_rationale**: <quoted from refine.md>
- **matched_pattern**: R1 | R2 | R3 | R4 | R5 | R6 | unmatched
- **loop_action**: <what the loop did>
- **subagent_dispatched**: yes / no (which: comparator-research | github-dup-check | e2e-harness-build | bounty-mapping | joint-judge | invariant-check)
- **evidence**: <captured output / fetched issue text / E2E verdict>
- **new_verdict**: SUBMIT | DISCARD | STAY_REFINE
- **rationale**: <2-4 sentences>
- **artifacts_path**: <if E2E harness built: path to the harness directory>
```

## Cost budget

The refine-loop adds variable cost per REFINE finding:

| Pattern | Avg cost | Notes |
|---------|----------|-------|
| R1 (comparator) | 1 Sonnet call + 1 WebSearch | ~30s wall-clock |
| R2 (dup check) | 1 gh + 1 LLM compare | ~20s |
| R3 (E2E build) | 1-3 Sonnet calls + cargo build + run | 5-15 min |
| R4 (bounty mapping) | 1 WebFetch + 1 LLM compare | ~30s |
| R5 (joint judge) | 1 Opus call | ~1 min |
| R6 (invariant check) | pure file-reads | ~10s |

For a 5-REFINE-finding run, expect ~15-30 min added wall-clock. Cheap compared to the user-time it saves on manual refinement.

## Coordination with other stages

- **Stage 3** (`infra-verification-stage.md`): R3 (E2E build) calls into the Stage-3 verification logic for harness writing, build, run.
- **Stage 4** (`infra-impact-analysis.md`): when R3 reproduces, the finding re-enters Stage 4 for severity re-computation with the new live evidence.
- **Stage 5** (`disclosure-paths.md`): when R4 remaps severity, re-route disclosure path.
- **Stage 6** (`cve-triage.md`): when R5 merges findings, re-run CVE decision.
- **Stage 7** (`duplication-check.md`): R2 (GitHub dup check) supplements Stage 7's probe set with deeper analysis.
- **Phase 8b**: re-runs template formatting for newly-promoted findings after loop resolution.

## What this does NOT close

- **Pattern matching of REFINE rationales is keyword-based.** Rationales written in unanticipated language slip through (= `unmatched`). The pattern list is extensible; add R7+ as new patterns surface in real runs.
- **Subagent reliability.** The R1 / R2 / R3 / R5 subagents can produce inconclusive output (especially R3's harness build failing 3 times). Argus surfaces these as `loop_action: inconclusive` and routes back to manual queue.
- **Loop termination.** The loop runs once per finding, not iteratively. If R3 reproduces a bug AND R5 (joint judge with another finding) is also relevant, the orchestrator picks the strongest applicable pattern, not all patterns.
- **Cost overrun.** If R3 E2E build/run consumes significantly more than the Stage 0 budget, the orchestrator surfaces a cost warning via AskUserQuestion. The user can choose to continue, cap, or abandon.
