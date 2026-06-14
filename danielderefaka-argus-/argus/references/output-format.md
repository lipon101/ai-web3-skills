# Output Format — Stage 8

Stage 8 produces the final, selective, cold output. The goal is *fewer, stronger* findings — not volume.

Read this file at Stage 8 start.

## Stage 8 sub-phases

Stage 8 has three phases:

- **Phase 8a-pre — Dedupe pass**: detect citation overlap across Stage 7 ADVANCE findings; merge or force-re-pass through Stage 4.
- **Phase 8a — Triage**: write the three triage files (`submission-grade.md`, `refine.md`, `discard.md`) with all `F-NN` findings binned.
- **Phase 8b — Report formatting**: ask the user which platform's report template to format the SUBMIT findings in, then write per-finding writeups under `$RUN_DIR/8-final/submission-formatted/` matching that template.

If the SUBMIT bucket is empty after Phase 8a, skip Phase 8b — there's nothing to format.

## Phase 8a-pre — Citation-overlap dedupe (MANDATORY)

Run this before binning into the three triage files. Reasoning: in the monero-oxide v0.1.3-era run, F-03 and F-01 both cited `transaction.rs:282` as the bug location and shipped as separate SUBMIT findings — they were the same root cause filed twice. The Stage-2 dedupe by `group_key` missed it because the `bug_class` tags differed.

### Detection

For every pair of Stage 7 `ADVANCE` findings (F-A, F-B), compute citation overlap:

1. Collect every `file:line` and `file:line-range` reference from F-A and F-B (locations + exploit path code citations).
2. Compute the overlap ratio:
   - `lines_both = count of lines cited by both A and B`
   - `lines_either = count of lines cited by either A or B`
   - `overlap = lines_both / lines_either`
3. Also compute root-cause overlap: do A and B claim the same defect (same function, same logical bug class) even if framed differently?

### Resolution (TIGHTENED in v0.1.6)

| Overlap signal | Action |
|----------------|--------|
| `overlap ≥ 0.5` (50% line citation overlap) AND same root cause AND same fix | **MERGE**: combine into one finding, keep the higher severity, drop the duplicate. |
| `overlap ≥ 0.3` (lowered from 0.5 in v0.1.6) regardless of same/different root cause | **STAGE-4 RE-PASS** with the joint Pass C judge. Determines MERGE / DISTINCT / KILL_ONE. |
| `0.15 ≤ overlap < 0.3` (lowered from 0.2 in v0.1.6) | **FLAG**: include both in SUBMIT but add a `related_findings:` cross-reference field in each F-NN.md. |
| `overlap < 0.15` | **NO ACTION**: findings are independent. |

### Why thresholds were lowered in v0.1.6

The swafe v0.1.5 run had F-15 (= C4 M-01, Guardian share replay overwrite) and F-02 (= C4 M-04, Replayable recovery requests) at ~0.25 line overlap. The 0.2-0.5 FLAG range produced a soft cross-reference that was then collapsed by Stage 8 into "subsumed by F-02 chain" — losing F-15 from SUBMIT. The 0.3 threshold (re-pass) catches this case AND forces the joint Pass C to apply the new "different fixes → DISTINCT" rule (below).

### Stage-4 re-pass procedure (TIGHTENED in v0.1.6)

When Phase 8a-pre forces a re-pass, spawn a fresh Pass C judge (only Pass C, not the full Pass A/B) with the joint pair as input. The judge prompt is now explicit:

```
You are a Stage-8 dedupe re-pass judge. Two findings cite overlapping code; you must
determine whether they are the same bug or distinct bugs.

## Finding A
{F-A.md content + Stage 4 verdict}

## Finding B
{F-B.md content + Stage 4 verdict}

## Citation overlap
overlap ratio = {ratio}
shared lines = {file:line ranges}

## Decision rules (apply STRICTLY in this order)

1. **Fix-subsumption check (NEW in v0.1.8) ⇒ KILL_ONE if subsumed.** Before applying
   any other rule, ask: "Would A's fix, applied alone, prevent B's exploit path from
   firing?" Equivalently: "Does B's exploit case open with words like 'after a successful
   exploit of A...' or 'combined with A...' or 'between A's defect and the next legitimate
   tx...'?" If yes, B is **hardening under A**, not a separate finding. Mark `KILL_ONE(B)`
   with rationale: "B's exploit path requires A's defect to also exist; A's fix prevents
   B's exploit." B's recommended-fix delta gets folded into A's writeup as a complementary
   hardening recommendation.

   Example (the swafe v0.1.5 / Judge re-pass case):
   - H-2 fix: per-guardian on-chain approval-counter on Recovery branch.
   - H-3 fix: cnt-bump in RecoveryRequestMessage to prevent replay.
   - M-2 fix: atomic on-chain `RevokeAssoc` action (closes the client-vs-chain race).
   - M-4 fix: post-recovery timelock + cancel-recovery action.

   H-2's fix forces guardian approval on every Recovery → H-3, M-2, M-4 exploit paths
   all collapse (no Recovery succeeds without majority guardian approval, regardless of
   replay / race / cooldown). KILL_ONE(H-3, M-2, M-4); their fixes become hardening notes
   inside H-2's Recommendations section.

   Heuristic: if Finding B's writeup contains the substring "Combined with A" or
   "After a successful but unauthorized recovery (per A)" or similar contingency
   language, B is a strong candidate for fix-subsumption.

2. **Different fixes ⇒ DISTINCT (only if neither fix subsumes the other).** If A's fix
   would NOT also prevent B's exploit AND B's fix would NOT also prevent A's exploit,
   the findings are DISTINCT. They share a subsystem, not a root cause.
   Example: A's fix is "add cnt to RecoveryRequestMessage" (replay protection); B's fix
   is "add session_id to GuardianShare" (cross-session-replay protection on a DIFFERENT
   data structure). A's fix doesn't touch GuardianShare; B's fix doesn't touch
   RecoveryRequestMessage. Different fixes AND no subsumption. DISTINCT.

3. **Same fix on the SAME line ⇒ MERGE.** If both findings recommend the identical
   modification to the same line(s), they are the same bug. Combine.

4. **One is a strict subset of the other ⇒ KILL_ONE.** If A's exploit path is a
   special case of B's (e.g., A is "this fires when threshold=0", B is "this fires for
   any threshold"), kill A. The killed finding's mitigation is mentioned as
   "hardening" under the kept finding's writeup.

5. **Otherwise ⇒ DISTINCT.** When in doubt, keep both and cross-reference.
   Better to file two related Mediums than to merge two distinct C4-payable findings —
   but the fix-subsumption check (rule 1) MUST be applied first; it is not "doubt."

## Output
**Verdict**: MERGE / DISTINCT / KILL_ONE(F-N)
**Distinguishing line**: <single sentence explaining what makes A and B different>
**Different fixes?**: yes / no — <explain by quoting each finding's "Recommendations" section>
**Confidence**: HIGH / MEDIUM / LOW
**Reasoning**: <3-5 sentences>
```

The re-pass verdict goes in `$RUN_DIR/8-final/_dedupe-repass/F-A_F-B.md` and updates the binning before the triage files are written.

#### v0.1.5 swafe run that motivated this change

Phase 8a-pre evaluated F-15 ↔ F-02 at ~0.25 overlap, which fell in the FLAG band, so both stayed in SUBMIT — but then somewhere in the bin-to-SUBMIT step F-15 was downgraded to REFINE with the rationale "subsumed by F-02 chain." That step did not apply the "different fixes" rule.

- F-02 fix: `cnt` binding in `RecoveryRequestMessage` → replay protection
- F-15 fix: `session_id` binding in `GuardianShare` → cross-session-replay protection on share storage

Different fixes. Different code surfaces (recovery branch in `account/v0.rs` vs share storage in `upload_share.rs` + `backup/v0.rs`). DISTINCT, not subsumed. The new threshold (0.3 → re-pass) and rule-order ("different fixes ⇒ DISTINCT" applied first) catch this case.

### Output

Write `$RUN_DIR/8-final/_dedupe-summary.md`:

```markdown
# Citation-overlap dedupe — Phase 8a-pre

| Pair | Overlap | Action | Result |
|------|---------|--------|--------|
| F-01, F-03 | 0.71 | STAGE-4 RE-PASS | KILL_ONE(F-03): parser-side mirror of F-01 |
| F-02, F-05 | 0.34 | FLAG | both kept; cross-referenced |
| ... | | | |
```

If no pairs overlap ≥ 0.2, write the file with `No citation overlap detected — dedupe pass clean.`

## Three triage files (Phase 8a)

`$RUN_DIR/8-final/` contains these three files plus the `submission-formatted/` directory from Phase 8b:

1. **`submission-grade.md`** — every finding that ended Stage 7 with `ADVANCE`. Sorted: severity desc, confidence desc, dup-risk asc.
2. **`refine.md`** — every finding that ended any stage with `DOWNGRADE` and did not auto-recover. Each entry says exactly what is needed to lift it to SUBMIT.
3. **`discard.md`** — every finding that was `KILL`'d. Records the killing stage and the kill reason.

Every F-NN from Stage 2 appears in **exactly one** of these three files. No finding can be in two files. No finding can be missing.

`submission-grade.md` is allowed to be empty. An empty SUBMIT is a successful run when nothing survived. Do not invent findings to fill it.

## submission-grade.md schema

Argus uses a hybrid of Solidity Auditor's compact-list format and a per-finding detail block. The compact list at the top gives the user a one-screen overview; the detail blocks below give a self-contained writeup per finding.

```markdown
# Submission-Grade Findings — <project name>

> ⚠️ **AI-provenance reminder.** Argus is AI tooling. Before submitting any finding to a platform — especially Cantina, but in practice all of them — manually re-read the cited code, independently re-derive the exploit path, run the PoC yourself, re-verify scope against the live program page, and re-write the writeup in your own words. The findings below are AI-generated drafts, not finished submissions.

- **run id**: <UTC timestamp>
- **target**: <project root>
- **bounty URL**: <url or "generic">
- **target repo**: <url or "local-only">
- **platform (Stage 5)**: <platform>
- **mode warnings**: <"none" | list of: generic-program-mode, local-only-dup-mode, severity-divergence, criteria-divergence, etc>
- **manual-validation acknowledgment**: yes (Cantina) | recommended (other) | n/a

---

## Findings list

| # | Severity | Confidence | Title | Location |
|---|----------|------------|-------|----------|
| 1 | Critical | 92 | <title> | `<crate>::<module>::<function>` |
| 2 | High     | 84 | <title> | `<crate>::<module>::<function>` |
| ... |

---

## Findings

### [92] **F-01: <title>**

`<crate>::<module>::<function>` · Confidence: 92 · Severity: Critical (calibrated)

**TL;DR (v0.1.10)** *(executive summary, three sentences max)*
1. **What's broken**: <one sentence — the defect>
2. **Who can exploit and how**: <one sentence — actor + minimal call sequence>
3. **What they get + recommended fix**: <one sentence — impact + fix in a phrase>

**Validation summary**
| Stage | Verdict | Note |
|-------|---------|------|
| 2 — Audit | candidate at <severity>, conf <N> | <brief> |
| 3 — PoC | ADVANCE / DOWNGRADE | tier <N> |
| 3.5 — Automated Verification | <KILL(kani-verified) / UPGRADE / NOT_APPLICABLE / SKIPPED> | <brief> |
| 4 — Adversarial Pass D | calibrated <severity> (divergence: <CONFIRMED / UPGRADED N-tier / DOWNGRADED N-tier>) | strongest surviving challenge: <name> |
| 4.5 — Combination Attack | <NO_PAIR / WEAK / STRONG (combined with F-XX as F-AB-NN)> | <brief> |
| 5 — Platform | ADVANCE at <severity>, rubric score <N>/16 | <brief> |
| 6 — Program | in-scope, impact maps to <category> | <brief> |
| 7 — Duplication | no hard duplicates | <probes summary> |

**Severity decision path (NEW v0.1.10)**
\`\`\`
rubric_default: <Pass D rubric output, e.g., "High (theft requiring realistic preconditions)">
→ historical-table-match: <bug shape match OR "no match">
   (suggested <severity> per table)
→ value_at_stake_check:
     estimated_value_at_risk_usd: <number or "unbounded">
     one_tx_drain_demonstrated: yes | no
     override_threshold_breached: yes | no
   (override <upward / downward / none>)
→ trust_threshold:
     level: <1-5>
     layers_bypassed: <count>
   (cap <none / Informational / DOWNGRADE one tier / DOWNGRADE N tiers>)
→ mitigation_check: <SOLVABLE / TRADE_OFF / UNCERTAIN>
   (cap <none / Low>)
→ scope_carveout: <OUTSIDE / WITHIN strong / PARTIAL strong>
   (cap <none / Low>)
final_severity: <severity>
\`\`\`

**Root cause**

<one paragraph naming the underlying defect, not the symptom>

**Location**

- `<crate>::<module>::<function>` — `<file>:<line-range>`

**Exploit path**

1. <step, concrete, citing code line or PoC operation>
2. <step>
3. <step>

**Proof of concept**

- **tier**: <Stage 3 tier 1-4 or exempt-N>
- **file**: `$RUN_DIR/3-poc/F-01/poc.<ext>`
- **reproduction**: see `$RUN_DIR/3-poc/F-01/repro.md`
- **proven impact**: <one paragraph>

**Impact**

<concrete: who loses, how much, under what conditions, with citation of program's in-scope impact category>

**Recommendation (unified diff — MANDATORY in v0.1.10)**

The recommendation MUST be a unified diff that applies cleanly via `git apply --check` against the cited commit. Verbal-only recommendations are rejected at Stage 8 binning.

```diff
--- a/<crate>/src/<module>.rs
+++ b/<crate>/src/<module>.rs
@@ -<from-line>,<count> +<to-line>,<count> @@
 <context line>
-<vulnerable code lines>
+<fixed code lines>
 <context line>
```

For multi-file fixes: include one diff hunk per file. Stage 8 verifies all hunks apply cleanly.

If the fix is non-trivially multi-step (e.g., requires a migration), provide the diff for each step in order, with a one-line description before each diff explaining what that step does.

**Mitigation viability** (from Stage 4 Pre-Pass)
- classification: <SOLVABLE | TRADE_OFF | UNCERTAIN>
- if TRADE_OFF: <what the fix costs the protocol>

**Practical weaponisation** (from Stage 2)
- grade: <A | B | C | D>
- capital required: <amount>
- time required: <atomic | sustained>
- attacker class: <permissionless | needs-flash-loan | needs-MEV | needs-trusted-role>

---

### [84] **F-02: ...**

[same schema]

---

[Repeat for every SUBMIT finding, sorted by severity desc → confidence desc → dup-risk asc.]

---

## Leads (optional)

If Stage 2 produced unpromoted LEADs that the user may want to investigate manually, include a compact list at the bottom — title, location, code-smells, what remains unverified. **No** Fix block, **no** confidence score (LEADs are explicitly not findings).

```
- **<title>** — `<crate>::<module>::<function>` — Code smells: <missing guard, unsafe arithmetic, etc.> — <1-2 sentence description of the trail and what remains unverified>
```
```

## refine.md schema

```markdown
# Findings Needing Refinement — <project name>

These findings are real but were downgraded somewhere in the pipeline. They need work before submission.

---

## F-NN: <title>

- **current severity**: <severity post all downgrades>
- **claimed at Stage 2**: <severity>
- **calibrated at Stage 4 Pass D**: <severity>
- **stage that downgraded**: <Stage N>
- **reason**: <one sentence>

### What's needed to lift to SUBMIT

<numbered, concrete actions. Examples:
1. Build a Tier 1 PoC against the project's `solana-program-test` harness — current PoC is Tier 3.
2. Quantify loss with realistic pool size — current writeup is qualitative; Sherlock requires >1% AND >$10.
3. Differentiate framing from issue #142 — that issue covers same file but different code path.
4. Cantina manual-validation acknowledgment missing — confirm before resubmitting.>

### Validation summary
| Stage | Verdict | Note |
|-------|---------|------|
| ... | | |

### Brief
<2-3 sentence description of the underlying issue, in case the user wants to pick this up.>

---
```

## discard.md schema

```markdown
# Discarded Findings — <project name>

For transparency only. These findings were killed and should not be re-litigated unless new evidence emerges.

---

## F-NN: <title>

- **claimed severity (Stage 2)**: <severity>
- **calibrated severity (if reached Stage 4)**: <severity or n/a>
- **killed at**: Stage <N>
- **reason**: <reason category, e.g. "no-poc", "out-of-scope", "trusted-role-required", "hard-dup-fixed", "auto-invalidator-AI-N">
- **kill detail**: <one paragraph: which check, what evidence, citation>

---
```

## Phase 8b — Report formatting

After Phase 8a writes the three triage files, AND ONLY IF `submission-grade.md` is non-empty, run Phase 8b.

### Step 1 — Ask the user for the template

Use `AskUserQuestion` exactly once:

> "Argus produced <N> SUBMIT findings. Which platform's report template should I format them in?"

Options (always in this order):
1. `Code4rena` — competitive audit format, `[H-N]` / `[M-N]` / `[L-N]` prefixed titles
2. `Sherlock` — H/M-only, with quantified loss thresholds
3. `Cantina` — Impact × Likelihood matrix, mandatory PoC inline, AI-3 manual-validation acknowledgment
4. `Immunefi` — bug bounty format, mandatory PoC, in-scope-impact-list mapping
5. `HackenProof` — pre-validation gates self-checklist, commit/version mandatory
6. `CodeHawks (incl. First Flights)` — Cyfrin format, auto-judge-friendly summaries
7. `Generic Markdown` — portable default with full validation trace + AI-provenance disclosure
8. `Skip — triage files only` — don't generate Phase 8b output

If the user selected one of options 1-7, read the matching file in `references/report-templates/<platform>.md`.

### Step 2 — Format each SUBMIT finding

For every finding in `submission-grade.md` (in the order they appear there — already sorted by severity desc, confidence desc, dup-risk asc):

1. Read the finding's full per-stage verdict files (`$RUN_DIR/2-candidate-findings/F-NN.md`, `3-poc/F-NN/`, `4-adversarial/F-NN.md`, `5-platform/F-NN.md`, `6-program/F-NN.md`, `7-duplication/F-NN.md`).
2. Apply the template from `references/report-templates/<platform>.md`. Substitute the placeholder fields with concrete content from the per-stage files.
3. Write to `$RUN_DIR/8-final/submission-formatted/F-NN.md`.

ID assignment: Code4rena / Sherlock / CodeHawks templates use `[H-N]` / `[M-N]` / `[L-N]` prefixes. Compute these by sorting SUBMIT findings by severity (Critical > High > Medium > Low) and assigning:
- Critical findings: `[H-1]`, `[H-2]`, … (Code4rena treats Critical as High; if the platform has a Critical bucket, use `[C-N]` instead — only Immunefi/HackenProof/Cantina have Critical)
- High findings: `[H-N]` (continuing from where Critical left off if conflated)
- Medium findings: `[M-N]`
- Low findings: `[L-N]`

For Cantina / Immunefi / HackenProof / Generic, severity goes in a structured field, not the title prefix.

### Step 3 — Write a combined index

Also write `$RUN_DIR/8-final/submission-formatted/index.md`:

```markdown
# Submission-Formatted Findings — <project name>

Template: <platform>
Generated from: $RUN_DIR/8-final/submission-grade.md
Run: <UTC timestamp>

> ⚠️ AI-provenance: every finding below was produced by Argus. Manually re-read the cited code, re-derive each exploit, run each PoC, and rewrite each writeup in your own words before submission.

## Findings

| # | Severity | Title | File |
|---|----------|-------|------|
| H-1 | High | <title> | `F-01.md` |
| ... | | | |

## Submission order

Submit in the order above (severity desc). For platforms with first-reporter priority (Immunefi, Sherlock BB), submit highest-severity first to minimize duplicate-pre-empt risk on the most valuable finding.
```

### Step 4 — Update terminal print

The terminal print at end of run now also surfaces:

```
Formatted output: <$RUN_DIR>/8-final/submission-formatted/
Template applied: <platform>
```

If the user picked "Skip", omit these lines.

## Phase 8c — Format-adversarial polish (NEW v0.1.10, OPT-IN)

After Phase 8b template formatting, optional Phase 8c spawns an LLM-judge subagent simulating the platform's triager. This is opt-in, not default — the user must explicitly enable.

### Activation

`AskUserQuestion` after Phase 8b completes:

> "Argus produced N formatted SUBMIT findings. Phase 8c can simulate the platform's triager and rewrite each finding for higher acceptance likelihood. This costs ~30k tokens per finding. Run polish?"
>
> Options:
> - `Yes — polish all findings`
> - `Yes — polish only Critical / High (default)`
> - `Skip — submit as-is`

### Per-finding polish

For each finding selected for polish:

1. **Spawn judge subagent** (Opus model) with this prompt:

```
You are a {Code4rena | Cantina | Sherlock | Immunefi | HackenProof | CodeHawks | Generic} judge
reviewing this submission. Apply the platform's actual rubric.

## Submission to evaluate
{F-NN.md content from submission-formatted/}

## Platform rubric notes
{platform-specific evaluation criteria from references/platform-criteria/<platform>.md}

## Your task
Score on these criteria:
  - Clarity of impact (does the writeup explain why this matters concretely?)
  - PoC quality (does the PoC convince you the bug is real?)
  - Severity appropriateness (does the severity match the demonstrated impact?)
  - Submission quality (does the writeup follow the platform's preferred structure?)

## Output
acceptance_likelihood: 0..100
weakest_section: <which subsection is weakest, e.g., "Impact paragraph" / "PoC trace">
specific_objections: [<list of concrete things a triager would object to>]
rewrite_suggestions: [<concrete edits, each ≤ 2 sentences>]
```

2. **Process verdict**:

| acceptance_likelihood | Action |
|----------------------|--------|
| ≥ 90 | Accept submission as-is; no rewrite |
| 70-89 | Single-pass rewrite using suggestions; re-evaluate; accept the better |
| 40-69 | Two-pass rewrite cycle; cap at 3 cycles total |
| < 40 | Surface the judge's objections to the user; recommend manual rewrite. Do NOT auto-rewrite — at this score the structural issue exceeds polish |

3. **Rewrite procedure** (when triggered):

Spawn a writer subagent (Sonnet) with the original F-NN.md + the judge's `weakest_section` + `rewrite_suggestions`:

```
Rewrite the following submission to address the judge's concerns. Preserve every
file:line citation and every PoC reference. Strengthen the {weakest_section}.

## Judge's weakest section
{weakest_section}

## Judge's rewrite suggestions
{rewrite_suggestions}

## Original submission
{F-NN.md content}

## Output
The rewritten submission, in the same template format.
```

Re-evaluate via the judge subagent. Accept the rewrite if `acceptance_likelihood` improves; revert if it regresses.

4. **Cap**: max 3 polish cycles per finding. After 3 cycles, accept the highest-scoring version.

### Output

`$RUN_DIR/8-final/submission-formatted/F-NN-polished.md` (only when polish runs):

- The polished submission text.
- A footer: `polish_cycles: N`, `final_acceptance_likelihood: K`, `reverted_to: original | cycle-1 | ...`.

`$RUN_DIR/8-final/_polish-summary.md`:

```markdown
# Phase 8c polish summary

| Finding | Cycles | Initial likelihood | Final likelihood | Action |
|---------|--------|--------------------|------------------|--------|
| F-01 | 0 | 92 | 92 | accepted as-is |
| F-02 | 2 | 75 | 91 | rewritten (2 cycles) |
| F-03 | 3 | 60 | 78 | partially-improved; user manual review recommended |
```

### Discipline rules

- **Polish does NOT change severity, PoC tier, or any factual claim.** It rewrites prose only. Severity is locked at Pass D + Stage 5 + Stage 6 clamps.
- **Polish does NOT add new evidence.** If the judge says "PoC is weak", polish cannot fabricate stronger PoC; it surfaces the objection to the user.
- **AI-provenance reminder still applies.** Polished output is still AI-generated; user must manually re-write before submission per the AI-provenance discipline.
- **Polish is opt-in.** Default behavior (no flag, no opt-in answer) is to skip Phase 8c and submit Phase 8b output as-is.

### Cost

Per finding: ~30k tokens (judge eval × 1-3 cycles + writer rewrite × 0-2 cycles).
For N polished findings: ~30N k tokens. Surfaced in Stage 0 cost preview if user opts in pre-emptively.

### Discipline rules

- **Never auto-pick a template.** Even in auto-mode, Phase 8b stops to ask.
- **Never paste Argus's prose verbatim into the formatted writeups.** The point of the AI-provenance discipline is rewriting in the user's own words. Phase 8b produces *drafts* that the user MUST manually rework before submission.
- **The platform's discipline rules govern the formatting.** If `report-templates/cantina.md` says the manual-validation acknowledgment is mandatory, include it in every Cantina-formatted finding.
- **Severity in the formatted report = Stage 4 Pass D calibrated severity, after Stage 5/6 clamps.** Don't re-grade at Phase 8b.

## Final terminal print

After writing all output files (Phase 8a + Phase 8b), print exactly:

```
═════════════════════════════════════════════
Argus run complete.
─────────────────────────────────────────────
SUBMIT:  <count>  finding(s) ready for submission (after manual validation)
REFINE:  <count>  finding(s) need work
DISCARD: <count>  finding(s) killed
─────────────────────────────────────────────
Output: <$RUN_DIR>/8-final/

Mode warnings:
  - <warning if any>

⚠️ Manual validation reminder:
  Re-read cited code, re-derive exploit, run PoC, re-verify scope, re-write writeup
  before submitting. Argus output is an AI-generated draft, not a finished submission.
─────────────────────────────────────────────
```

Then list each SUBMIT finding's title and severity, one per line. Nothing else. Don't summarize the REFINE/DISCARD contents in the terminal — they exist in the files.

## Selection discipline

Stage 8 is allowed to apply *one final pass* of cold judgment: if two SUBMIT findings have the same root cause but different locations, decide whether to merge them into one finding (often correct: a single bug in shared code) or keep them separate (correct when separate exploit paths exist with different impact).

When in doubt, merge. Two findings that read like one finding will be merged by the program's triage anyway.

## Sorting rule

Within `submission-grade.md`, sort findings by:

1. severity (Critical > High > Medium > Low) — desc
2. confidence — desc
3. dup-risk (low < unknown) — asc
4. F-NN order — asc (tie breaker only)

Within `refine.md`, sort by the same rule on the post-downgrade severity.

Within `discard.md`, sort by Stage of kill ascending (so KILL-at-Stage-3 comes before KILL-at-Stage-7), then F-NN order.

## Confidence reduction for mode warnings

If the run is in `program-mode = generic` or `dup-mode = local-only`, every SUBMIT finding gets a confidence cap:

- generic-program-mode: cap headline confidence at 75
- local-only-dup-mode: cap at 75
- both: cap at 65
- severity-divergence-warning (Stage 4 Pass D LOW confidence + ≥2-tier divergence): cap at 70 AND surface in mode warnings
- criteria-divergence (Stage 5 WebFetch differed from bundled criteria): cap at 75 AND surface

The cap is applied at Stage 8 final compute. The original Stage 5 score is preserved in the validation table; only the headline confidence is capped.

## What Stage 8 must NOT do

- Do not include findings that didn't run through every prior stage. If something appears in Stage 7 verdict files but never had a Stage 4 verdict file, the pipeline is broken — surface this as an error, do not paper over it.
- Do not edit the per-stage verdict files. Stage 8 reads them; it does not modify them.
- Do not include findings whose KILL stage came earlier than Stage 7 in `submission-grade.md` or `refine.md` — they belong in `discard.md`.
- Do not output volume. If 12 findings entered Stage 2 and 1 survives to Stage 8, that one finding is the output. The other 11 go to `discard.md`. This is correct, not a failure.
- Do not present findings as finished submissions. The AI-provenance reminder is mandatory — both in the file header and in the terminal print.
