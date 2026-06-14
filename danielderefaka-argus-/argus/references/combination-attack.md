# Stage 4.5 — Combination Attack pass

Stage 4.5 is a pairwise analysis stage between Stage 4 (Adversarial) and Stage 5 (Platform). It identifies pairs of independently-survived findings whose combined exploit produces strictly greater impact than either alone.

This is a v0.1.10 addition driven by DeepSeek's external review Item 2.

Read this file at Stage 4.5 start.

## Why

Argus pre-v0.1.10 treats every finding as independent except in Stage 8 dedupe (which only merges *duplicates*). Many real-world exploits chain two seemingly-modest defects:

- A V37 unbound-merkle-leaf finding (Medium: "anyone can claim if they observe a proof") + a V44 nonce-not-incremented (Medium: "claim can be replayed") → combined: "anyone can drain the airdrop pool" (Critical).
- A V18 oracle-staleness (Low) + a V19 single-block-manipulable spot price as fallback (Low) → combined: "during oracle freeze, attacker manipulates fallback to drain liquidations" (High).
- A V40 init-front-run (Medium) + a V69 reply-handler-msg-id-missing (Medium) → combined: "attacker initializes contract with hostile config that makes subsequent submessages misroute" (Critical).

Stage 4.5 surfaces these chains explicitly.

## When Stage 4.5 fires

After Stage 4 produces verdicts for every finding. Operates on the set of findings with status `ADVANCE` or `DOWNGRADE` (any survivor of Stage 4).

If fewer than 2 surviving findings, skip Stage 4.5 (no pairs to analyze).

## Pair selection

For N surviving findings, naively there are N(N−1)/2 pairs. To bound cost:

1. **Cap at top 20 by severity × confidence.** Sort by `(severity_rank * 100 + confidence_interval.point)`. Take the top 20. Pairs are drawn from this set: at most 190 pairs.
2. **Group by shared `crate::module`** to focus pair analysis on findings that touch related code (chains across unrelated modules are rare).
3. **Skip pairs already merged at Stage 8 dedupe** (no need to combine duplicates).

For projects with > 20 surviving findings, the "top 20" cap means lower-severity findings are not paired with each other. This is acceptable: combinations of two Lows rarely produce more than a Medium, and Stage 8's compound-finding rules already promote duplicates.

## Per-pair analysis

For each pair (F-A, F-B):

### Step 1 — Precondition chaining check

Read both findings' `path:` fields (caller → function → state change → impact).

Ask:
- **Forward chain**: does F-A's `state change` or `impact` create a precondition that F-B's `caller → function` requires?
- **Reverse chain**: does F-B's `state change` or `impact` create a precondition that F-A requires?

A precondition match means the finding chains: `Trigger A → state evolved → B's preconditions now met → trigger B`.

Examples:
- F-A's impact: "attacker becomes admin via init front-run". F-B's precondition: "admin can change oracle". → Forward chain: A enables B.
- F-A's impact: "MEV searcher front-runs tx with crafted bundle". F-B's precondition: "stale state at slot N+1 readable". → Forward chain: A's MEV creates B's stale-state window.

### Step 2 — Joint-impact check

Assume both fire in sequence (forward or reverse chain). Compute the combined attack-path:

```
combined_path:
  step 1: <A's preconditions met (initial state)>
  step 2: <A's call sequence>
  step 3: <state after A>  (now matches B's precondition)
  step 4: <B's call sequence>
  step 5: <state after B>
  step 6: <total combined impact>
```

Ask:
- Is the combined impact strictly greater than `max(A_impact, B_impact)`?
- Specifically: does the combined attack reach a higher severity tier than either alone?

If combined impact is just "A and B both happened" without a multiplicative effect, the pair is NOT a combination — it's two independent findings that happen to co-occur.

### Step 3 — Verdict

| Forward or reverse chain holds? | Combined impact > max(A, B)? | Action |
|---------------------------------|------------------------------|--------|
| no | n/a | NO_COMBINATION — pair is independent; no joint finding |
| yes | no | WEAK_COMBINATION — the chain works but adds nothing material; record cross-reference only |
| yes | yes | STRONG_COMBINATION — emit joint finding F-AB |

## Joint finding F-AB schema

For STRONG_COMBINATION pairs, write `$RUN_DIR/4-5-combination/F-AB.md`:

```markdown
# F-AB — Combined Finding (F-A × F-B)

- **components**: F-A, F-B
- **chain direction**: forward (A→B) | reverse (B→A) | bidirectional
- **claimed_severity (combined)**: <Critical | High | Medium | Low>
- **calibration**: Pass D re-runs against the combined attack path
- **status**: ADVANCE | DOWNGRADE | KILL  (initially set by Stage 4.5; finalized by Pass D re-run)

## Combined attack path

\`\`\`
step 1: <initial state>
step 2: <F-A's trigger sequence>
step 3: <state after F-A; F-B's precondition met>
step 4: <F-B's trigger sequence>
step 5: <state after F-B>
step 6: <combined impact>
\`\`\`

## Component findings

### F-A — <title>
- severity (alone): <severity>
- impact (alone): <impact>
- contribution to combined: <how A enables B>

### F-B — <title>
- severity (alone): <severity>
- impact (alone): <impact>
- contribution to combined: <how B uses A's output>

## Why combined > components

<2-4 sentences explaining the multiplicative effect>

## Pass D re-calibration

<Pass D verdict on the combined attack path. The combined severity may UPGRADE
beyond either component's individual severity.>
```

## Pass D re-run

Each F-AB requires Pass D to recalibrate severity from the combined attack path. Run the standard Pass D rubric (with the combined `attack_path_summary`) plus:

- Apply C4 historical-severity table override-upward if `value_at_stake` for the *combined* path > $1M.
- Apply trust-threshold layers-bypassed-count for the combined path (combined attacks may bypass MORE layers than either alone).
- Apply mitigation-viability check separately for the combined attack: is the fix for the chain trivial (fix A or fix B and the chain breaks) or compound (must fix both)?

## F-A and F-B retention

Both F-A and F-B remain in their original triage destinations from Stage 4. Stage 8 may surface them in SUBMIT alongside F-AB (a judge may credit one, both, or all three depending on platform). The orchestrator does NOT remove F-A or F-B in favor of F-AB.

The cross-reference tags:
- F-A's writeup adds `combined_with: [F-AB]`
- F-B's writeup adds `combined_with: [F-AB]`
- F-AB's writeup adds `references: [F-A, F-B]`

## Output

`$RUN_DIR/4-5-combination/_pairs-summary.md`:

```markdown
# Stage 4.5 Combination Attack — pair summary

- pairs analyzed: N
- STRONG_COMBINATION: K
- WEAK_COMBINATION: J
- NO_COMBINATION: M

| Pair | Chain | Combined severity | F-AB ID |
|------|-------|-------------------|---------|
| F-01 × F-03 | forward (F-01 → F-03) | High (was M+M) | F-AB-01 |
| F-02 × F-05 | reverse (F-05 → F-02) | Critical (was H+M) | F-AB-02 |
| ... | | | |
```

Per-pair `$RUN_DIR/4-5-combination/F-AB-NN.md` per STRONG_COMBINATION.

## Subagent decomposition

For >10 surviving findings, dispatch one general-purpose subagent per pair (or batched groups of 5 pairs) to draft the chaining + joint-impact analysis. Orchestrator runs Pass D re-calibration directly.

## Cap on F-AB output

If Stage 4.5 produces more than 5 STRONG_COMBINATION findings, sort by combined severity × confidence and take the top 5. Document the trim in `_pairs-summary.md`. Bug bounty submissions of >5 compound-findings tend to swamp the writeup; better to submit the top 5 chains and let the others surface as Stage 8 cross-references.

## What Stage 4.5 does NOT do

- Does NOT consider chains of 3+ findings. Only pairs. Triple chains are computationally explosive and almost never bounty-relevant.
- Does NOT alter F-A or F-B's verdicts. They survive to Stage 5 as set by Stage 4.
- Does NOT trigger ITERATE (Stage 4.5's discoveries are joint findings; ITERATE is for parallel-defect discoveries).

## Cost

N(N−1)/2 pair analyses, capped at 190. Per-pair: ~30k tokens (chaining-check + joint-impact + Pass D re-run). Worst case: 190 × 30k = 5.7M tokens, but the cap-at-top-20 keeps typical runs at 20–50 pairs ≈ 600k–1.5M tokens.

Stage 0 cost preview includes a Stage 4.5 line: `pair_count_estimate × 30000` tokens.

## Skip mode

User can disable via Stage 0 run-config:

```
COMBINATION_ATTACK: disabled
```

Disabled mode: Stage 4.5 is skipped entirely. Mode warning in Stage 8: `combination-attack-skipped: yes`.
