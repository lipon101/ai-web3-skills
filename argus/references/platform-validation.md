# Platform Validation — Stage 5

Stage 5 separates "technically real" from "likely to be paid". A finding can be a real bug AND simultaneously a finding that this platform's judges will reject. Stage 5 catches the second case.

Read this file at Stage 5 start, together with the matching `platform-criteria/<platform>.md` file.

## ⚠️ Per-finding output is MANDATORY (NEW v0.1.11)

Stage 5 produces `$RUN_DIR/5-platform/F-NN.md` for every finding entering this stage. A single `_summary.md` is INVALID. The rubric scorecard (4 criteria × 0-4) MUST be computed per finding — collapsed-to-prose Stage 5 output is rejected.

Stage 6 entry requires: per-finding F-NN.md count matches Stage-4-ADVANCE+DOWNGRADE count. If short, the orchestrator re-runs Stage 5 on missing findings.

## Platform identification

Determine the target platform from the bounty URL collected at Stage 1:

| URL pattern | Platform | Criteria file |
|-------------|----------|---------------|
| `immunefi.com/bug-bounty/...` | Immunefi | `platform-criteria/immunefi.md` |
| `cantina.xyz/competitions/...` | Cantina Competition | `platform-criteria/cantina-comp.md` |
| `cantina.xyz/bounties/...` | Cantina BB | `platform-criteria/cantina-bb.md` |
| `audits.sherlock.xyz/contests/...` | Sherlock Competition | `platform-criteria/sherlock.md` |
| `audits.sherlock.xyz/bug-bounty/...` | Sherlock BB | `platform-criteria/sherlock-bb.md` |
| `code4rena.com/audits/...` | Code4rena | `platform-criteria/code4rena.md` |
| `hackenproof.com/programs/...` | HackenProof | `platform-criteria/hackenproof.md` |
| anything else, or none | Generic | `platform-criteria/generic.md` |

If no URL was supplied at Stage 1, use Generic.

## ⚠️ Cantina manual-validation acknowledgment gate

If the target platform is **Cantina** (Competition or BB):

At Stage 5 start, before processing any finding, use `AskUserQuestion` to confirm:

> "Cantina bans unverified AI-generated findings (rule AI-3) and enforces detection aggressively. Argus is AI tooling. Do you confirm that, before submitting any finding from this run, you will:
> 1. Manually re-read the cited code at the cited line numbers
> 2. Independently re-derive the exploit path
> 3. Run the PoC and confirm the output
> 4. Re-verify scope against the live program page
> 5. Re-write the writeup in your own words"

Options: `Yes — I commit to manual validation before submission` | `No — abort this run`

If the user responds `No`, Argus aborts before processing Stage 5. The user can re-run with a different platform target or with the explicit decision to use Cantina with manual validation.

If the user responds `Yes`, record the acknowledgment in `$RUN_DIR/5-platform/cantina-acknowledgment.md` with timestamp and proceed.

For non-Cantina platforms, the gate is **strongly recommended** (surfaced in Stage 8 output) but not blocking.

## Loading platform criteria

Read the matching `platform-criteria/<platform>.md` file in full at Stage 5 start. It contains:
- Severity definitions specific to the platform
- Numbered automatic-invalidator list (AI-1, AI-2, …)
- PoC requirements (mandatory? severity-conditional?)
- Quality-signal expectations
- Platform-specific rules (Immunefi program primacy, Sherlock thresholds, Cantina matrix, etc.)

The bundled criteria are kept current to project sources at the time of skill installation. **The live page wins** — if the user reports a discrepancy, Stage 5 should ALSO WebFetch the platform's published criteria URL once at Stage 5 start to check for divergence:

```
WebFetch(url=<platform_criteria_URL>, prompt="Summarize: severity definitions, automatic invalidators, PoC requirements, quality signals, scope rules")
```

If WebFetch returns content that materially differs from the bundled file, log the divergence in `$RUN_DIR/5-platform/criteria-divergence.md` and apply the live-page rules.

## Stage 5 phases (apply per finding)

For each finding entering Stage 5 (status was ADVANCE or DOWNGRADE out of Stage 4):

### Phase 1 — Automatic Invalidator Scan

Walk the platform's automatic-invalidator list. For each rule, ask: does this finding match? Cite the specific aspect of the finding that matches.

If any rule triggers an INVALID outcome → `KILL(auto-invalidator: <rule>)`.

If a rule triggers a severity cap (e.g., HackenProof's "no PoC → Need more info") → record the cap and proceed.

### Phase 2 — Severity Alignment

Compare the *current* severity (post Stage 3 + Stage 4 calibration) against the platform's severity definitions. Determine: ALIGNED / INFLATED-by-N / DEFLATED-by-N. Cite the platform's specific severity definition.

- INFLATED-by-1 → DOWNGRADE one tier in Stage 5
- INFLATED-by-2-or-more → DOWNGRADE to platform's correct tier OR KILL if correct tier is below platform's payable threshold (e.g., Sherlock Competition doesn't pay below Medium)

### Phase 3 — Quality Signals

Apply platform-specific weight (PoC mandatory on Immunefi / Cantina / HackenProof BB / Sherlock BB / generic).

| Element | Strong | Weak | Missing |
|---------|--------|------|---------|
| Root cause clearly identified | identifies cause + mechanism | only the symptom | not addressed |
| Maximum impact demonstrated | quantified loss / attack chain endpoint | qualitative claim | unstated |
| Step-by-step or PoC | runnable PoC (Stage 3 Tier 1-3) | written steps only | none |
| Code snippets | quoted with file:line | only file refs | none |
| Remediation steps | specific, applies to root cause | generic advice | none |
| Realistic preconditions | enumerated + plausible | enumerated + borderline | not enumerated |

### Phase 4 — Score Calculation (UPDATED in v0.1.10 — rubric scorecard)

**v0.1.10 change**: replaces the subtractive 100→5 model with a 4-criterion 0-4 rubric. The subtractive model over-punished implicit-but-correct findings (Mediums where root-cause was inferable from description fell below 70 and got killed). The rubric mirrors what real platform judges use and reduces false kills.

**The four criteria**, each scored 0-4:

| Criterion | 0 | 1 | 2 | 3 | 4 |
|-----------|---|---|---|---|---|
| **Vulnerability identification** | unclear / not addressed | symptom-only mention | symptom + likely cause | root cause named, no citation | root cause + mechanism cited at file:line |
| **Impact** | unstated / "could be bad" | qualitative ("loss of funds") | qualitative + harmed party | quantified loss OR specific party | quantified loss + harmed-party + scope-of-attack identified |
| **Exploitability** | hand-waved / "in theory" | written derivation, gaps | written derivation, complete | runnable PoC, weak | runnable PoC matching exact claim |
| **Remediation** | wrong / missing / contradicts root cause | generic ("add validation") | specific suggestion, untested | specific patch, tested locally | unified-diff patch tied to root cause + mitigation-viability classified |

**Score = sum of all four**, range 0-16.

**Verdict mapping**:

| Sum | Severity-aligned | Verdict |
|-----|------------------|---------|
| ≥ 12 | yes | ADVANCE |
| ≥ 12 | inflated by 1 tier | DOWNGRADE one tier; ADVANCE at new tier |
| 8–11 | any | DOWNGRADE; the writeup needs work (specific weakest-criterion noted) |
| < 8 | any | KILL(rejected) |

**Half-credit rules**:

- If PoC is missing but a *rigorous* written derivation is present (every assumption listed, math derived from cited code, no hand-waving), the Exploitability criterion gets `2` instead of the would-otherwise `1`. Applies on platforms accepting written derivations: Sherlock for logic bugs, Generic. Does NOT apply on Cantina (which mandates runnable PoC).
- If Remediation is verbal but the root cause is unambiguously addressable via a well-known pattern (e.g., "use `checked_add`" for V12), the criterion gets `2` instead of `1`. The reviewer can produce a patch from the verbal description.

**Auto-invalidator override**: any platform AI-N rule that produces INVALID at Phase 1 is a KILL outright before the rubric runs. Cantina AI-3 manual-validation acknowledgment gate is a Stage-5-entry block, not a Phase-4 score input.

### Phase 4.5 — Longest-fund-loss-chain framing (NEW v0.2.0)

Claude Web's 4-stream empirics show ~55% of all promotion failures are "submitter framed it too narrowly" — a Medium gets filed at Low, a High gets filed at Medium. ChatGPT's representation-failure diagnosis says the same: the system's verdict can only be as good as the impact framing it operates on.

**Rule**: before computing the rubric score, automatically generate the **longest plausible fund-loss chain** from the finding's exploit path. Do NOT default to the narrow per-function impact the Stage-2 angle wrote.

**Procedure**:

1. Read the finding's `exploit_path:` (Stage-2 / Stage-4 verdict trace).
2. Identify the most-distant downstream impact from the bug location:
   - "Function A panics" → "the panicking function is reachable from RPC entry, so block-author DoS" → "DoS during `liquidate` window means borrower escapes liquidation" → "if the panicking function is on the liquidate path AND borrower has bad-debt-shaped position, attacker drains insolvent borrower's collateral via timed panic-griefing".
3. The Stage-5 rubric scoring is performed against this longest-chain framing, not the narrow framing.
4. The verdict file's "Impact" criterion notes BOTH the narrow framing the angle produced AND the longest-chain framing. Pass D severity is calibrated against the longest chain.
5. Cap: the longest chain must be plausible. "Function panics → therefore unbounded fund loss" without an intermediate-step argument is rejected.

**Effect**: prevents the 55%-narrow-framing failure mode by making longest-chain the default and narrow-framing the override-with-justification.

**Output addition** to verdict file:

```
impact_framing:
  narrow (per Stage-2 angle): <one-line description>
  longest_plausible_chain: <multi-step description>
  chain_steps: [<each step + cited code path>]
  framing_used_for_rubric: longest | narrow_with_justification
  justification_if_narrow: <reason longest-chain doesn't apply>
```

### Phase 5 — Verdict mapping

The rubric scorecard from Phase 4 is the verdict. Phase 5 surfaces the per-criterion breakdown to the user when DOWNGRADE fires (so they know which criterion was weakest and what to improve).

When DOWNGRADE fires, the verdict file's "Improvement notes" section MUST quote the weakest criterion's row from the rubric and provide concrete actions to reach the next score.

### Legacy subtractive scoring (DEPRECATED in v0.1.10, removed in v0.2.0)

The subtractive model from v0.1.0..v0.1.9 is still computed for one release as a sanity-check fallback:

- If subtractive score and rubric verdict diverge by ≥2 tiers (e.g., subtractive says KILL but rubric says ADVANCE, or vice versa), surface a `scoring_divergence_warning` in the verdict file.
- The rubric verdict is authoritative; the subtractive number is informational.

In v0.2.0, the subtractive scoring section is removed entirely.

## Per-finding output schema

`$RUN_DIR/5-platform/F-NN.md`:

```markdown
# F-NN Stage 5 verdict

- **finding**: <title>
- **platform**: <Immunefi | Sherlock Comp | ...>
- **calibrated severity (Stage 4 Pass D)**: <severity>
- **predicted severity (Stage 5)**: <severity>
- **score**: <N>/100
- **status**: ADVANCE | DOWNGRADE(<sev>) | KILL(<reason>)
- **manual-validation acknowledgment**: yes (Cantina target) | n/a (other platform) | recommended

## Phase 1 — Automatic invalidators

- **<rule ID or "none triggered">**: <quoted rule, why it applies, result>

## Phase 2 — Severity alignment

<2-4 sentences: how the platform defines this severity, whether the finding meets the bar, citation of the rule>

## Phase 3 — Quality signals

| Element | Status | Note |
|---------|--------|------|
| Root cause | strong/weak/missing | <if not strong, what's missing> |
| Max impact | ... | |
| PoC | ... | |
| Step-by-step | ... | |
| Remediation | ... | |
| Preconditions | ... | |

## Phase 4 — Rubric scorecard (v0.1.10)

| Criterion | Score | Notes |
|-----------|-------|-------|
| Vulnerability identification | <0-4> | <evidence: file:line citation OR description gap> |
| Impact | <0-4> | <quantified vs qualitative; harmed-party identified> |
| Exploitability | <0-4> | <PoC tier vs derivation; matches claim?> |
| Remediation | <0-4> | <unified diff vs verbal; tested locally?> |
| **Total** | **<0-16>** | |

| half-credit applied | yes/no — <which criterion + reason> |
| platform PoC requirement met | yes / no |
| auto-invalidator override | yes(rule) / no |

**(Legacy subtractive score, informational only)**:
\`\`\`
Subtractive: <NN>/100   (deprecated; removed in v0.2.0)
\`\`\`
**scoring_divergence_warning**: yes (rubric and subtractive disagree by ≥2 tiers) / no

## Phase 5 — Reasoning

<4-8 sentences as if you were the platform's judge. Reference specific rules, not generic advice. If borderline, say which way it tips and why.>

## Improvement notes (only if status is DOWNGRADE)

<2-5 concrete actions tied to specific rules. Not "add more detail" — say exactly what.>

## Criteria divergence

If the WebFetch'd live criteria differs from the bundled file:
<note divergence + which version was applied>
```

## Calibration

- Be strict. Judges are strict.
- A 70 still means real rejection risk. Don't celebrate scores in the 70s.
- Never give 90+ unless: concrete PoC, realistic preconditions, clear root cause, correct severity, strong writeup — all present.
- Argus's role is the judge's internal monologue, not the writer's advocate.
- When in doubt, err toward the platform's stricter interpretation. Judges don't give the benefit of the doubt.

## Subagent decomposition

For >10 findings entering Stage 5, spawn one general-purpose subagent per finding to draft the per-finding output (running Phase 1 + 2 + 3 + 4). The orchestrator runs Phase 5 (verdict) directly, verifying any decisive auto-invalidator citation by re-reading the platform-criteria file and the cited finding aspect before accepting the verdict.

For ≤10 findings, run sequentially in the orchestrator.
