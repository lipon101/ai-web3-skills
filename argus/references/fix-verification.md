# Fix Verification — Optional Stage 9

This stage runs ONLY when the user invokes Argus to verify a fix that has been applied for a previously-found vulnerability. It is independent of Stages 1-8 and produces its own verdict (`PASS | FAIL | NEEDS REVIEW`).

Read this file at Stage 9 start.

## When to use

- After applying a fix for a security finding (yours or from an audit)
- Before merging a security-related PR
- When reviewing someone else's patch for a vulnerability
- When a researcher reports a fix is incomplete

Stage 9 works on any local Rust codebase regardless of whether Stages 1-8 ran. The user provides:

1. **The vulnerability** — one of:
   - A pasted vulnerability description / report text
   - A reference to a prior `$RUN_DIR/8-final/submission-grade.md` finding (`F-NN`)
   - A CVE ID, advisory, or platform report URL
   - A plain-English explanation

2. **The fix** — one of:
   - The current working tree changes (`git diff`)
   - A specific commit or commit range (`git diff <commit1>..<commit2>`)
   - A branch comparison (`git diff main..fix-branch`)
   - A PR number (read diff from local git)
   - If unspecified, use unstaged + staged changes in the current repo

## Workflow

Use `AskUserQuestion` once at Stage 9 start to collect both inputs.

### Phase 1 — Understand the vulnerability

Parse the vulnerability description to extract:

- **Root cause** — what is fundamentally wrong (missing access check, unchecked deserialization, panic on user input, missing PDA-bump enforcement, etc.)
- **Attack vector** — how an attacker exploits it (call sequence, malicious input, frontrun)
- **Affected component** — crate / module / function / instruction handler / extrinsic
- **Impact** — what happens if exploited (fund loss, unauthorized access, DoS)

If the vulnerability references specific code (line numbers, function names), locate it in the codebase. If the user provided an `F-NN` reference, read the corresponding files in `$RUN_DIR/<run-id>/2-candidate-findings/F-NN.md`, `$RUN_DIR/<run-id>/3-poc/F-NN/`, `$RUN_DIR/<run-id>/4-adversarial/F-NN.md` for context.

### Phase 2 — Analyze the fix

Read the git diff to identify all changed files, functions, and lines.

For each change, classify as:

- **Direct fix** — directly addresses the root cause
- **Supporting change** — necessary refactoring or test update to support the fix
- **Unrelated change** — not connected to the vulnerability (flag for review)

Map the changes back to the root cause:

- Does the fix address the root cause, or just a symptom?
- Does the fix cover all code paths where the vulnerability exists?
- Are there other locations with the same pattern that are NOT fixed?

### Phase 3 — Completeness checklist

Run through every item. Mark each as PASS, FAIL, or UNKNOWN.

#### Root cause

- [ ] The fix addresses the root cause, not just a symptom or a specific exploit path
- [ ] If the root cause is a missing check, the check is now present on ALL relevant code paths
- [ ] If the root cause is a logic error, the corrected logic handles all input combinations

#### Coverage

- [ ] Search the codebase for the same pattern — are there other instances NOT fixed?
- [ ] If the vulnerable function is called from multiple places, fix works regardless of caller
- [ ] If the vulnerability spans multiple modules / pallets / contracts, all are patched

#### Edge cases

- [ ] Zero / empty / null inputs (`u64::MIN`, empty `Vec`, `None`, `Pubkey::default()`) — fix handles them?
- [ ] Maximum values — `u64::MAX`, `u128::MAX`, max-`Vec` length, max account size — fix handles?
- [ ] Boundary conditions — off-by-one, exactly-equal-to-threshold cases
- [ ] Ordering — fix works regardless of call ordering or transaction sequencing?

#### Error handling

- [ ] If the fix adds a new `require!` / `ensure!` / `if … return Err`, error message is descriptive?
- [ ] If the fix adds a new error condition, could it be triggered by legitimate users in normal operation?
- [ ] If the fix modifies error handling, errors still propagate correctly to callers?

### Phase 4 — Regression checklist

Run through every item.

#### Interface changes

- [ ] No public function signatures changed (unless intentional and documented)
- [ ] No `#[program]` instruction shape changed (Solana — would break clients)
- [ ] No `ExecuteMsg` / `QueryMsg` enum variant added/removed without migration (CosmWasm)
- [ ] No `#[pallet::call]` extrinsic signature changed (Substrate — would break tooling)
- [ ] No event / log signatures changed (would break indexers / subgraphs)
- [ ] Return values haven't changed type or meaning

#### Behavioral changes

- [ ] Existing valid inputs still produce same outputs
- [ ] State transitions that worked before still work (no new unexpected reverts)
- [ ] CU / gas / weight consumption hasn't increased dramatically for normal operations
- [ ] No new blocking conditions that prevent legitimate operations

#### Trust assumptions

- [ ] No new admin / privileged roles introduced
- [ ] No new external dependencies added (oracles, other programs)
- [ ] No existing permission checks weakened or removed
- [ ] Timelocks and delays not reduced or bypassed

#### Integration impact

- [ ] Functions called by other programs (CPI) still behave as expected
- [ ] Functions called by external integrations (DEX routers, aggregators, IBC) still work
- [ ] If a constraint / modifier was changed, all functions using it are still correct

#### Test integrity

- [ ] If test files modified, changes update expectations (not weaken assertions)
- [ ] No test deletions without replacement
- [ ] If new error conditions added, corresponding tests exist
- [ ] If behavior changed, tests reflect new expected behavior

### Phase 5 — Smart-contract-specific checks (Rust-tuned)

Apply when the affected component is a Solana / CosmWasm / Substrate / on-chain-Rust contract.

#### Re-entry (Solana CPI / CosmWasm submessage / SPL Token-2022 transfer-hook)

- [ ] If fix adds a re-entry guard, verify it covers ALL CPI / submessage calls in the function, not just the one exploited
- [ ] If fix reorders state changes (CEI), verify new order is correct for ALL state variables
- [ ] Cross-function re-entry: are there other functions reading the same state that could be called during re-entry?
- [ ] Cross-program re-entry: does fix account for callbacks from other programs in the protocol?

#### Auth / Account / Origin

- [ ] If fix adds a `signer` / `has_one` / `ensure_signed` / `info.sender` check, uses correct role/permission (not weaker)?
- [ ] Verify auth check cannot be bypassed via CPI / proxy / dispatch_as / migration
- [ ] If fix restricts function to specific caller, verify caller can't be manipulated (PDA seeds, address derivation)

#### Arithmetic

- [ ] If fix addresses overflow/underflow, covers ALL arithmetic in the function (not just one line)?
- [ ] If using `checked_*`, no `unchecked_*` / `wrapping_*` / `saturating_*` / `overflowing_*` bypasses it?
- [ ] If fix changes precision or decimal handling, rounding direction favors protocol (not attacker)?

#### State and storage

- [ ] If fix modifies storage layout (Anchor `#[account]`, CosmWasm `Item`/`Map`, Substrate `Storage`), compatible with existing deployments?
- [ ] If fix changes a mapping/map/storage, no stale data can be read?
- [ ] If fix adds new state variable, initialization handled — especially for upgrades / migrations?

#### External calls

- [ ] If fix changes how external calls (CPI, submessages, dispatch) are made, return values checked?
- [ ] If fix adds new external call, can't be used to manipulate state?
- [ ] If fix adds callback guard, doesn't break legitimate integrations?

#### Token handling

- [ ] If fix involves token transfers, handles SPL Token-2022 transfer fees / hooks (if applicable)?
- [ ] If fix involves token approvals / SPL delegate, no approval-frontrun introduced?
- [ ] If fix involves native-token transfers, handles edge cases (account-doesn't-exist, ED, etc.)?

#### Upgrade safety

- [ ] If contract is upgradeable (Anchor `program_upgrade_authority`, Substrate `set_code`, CosmWasm `migrate`), fix doesn't break storage layout?
- [ ] If fix changes initializer / instantiator, can't be called again on existing deployment?
- [ ] If fix changes a function's entrypoint shape, dispatch routing still works?

### Phase 6 — Verdict

Produce the verdict file using the schema below. Use exactly this format.

## Per-finding output schema

`$RUN_DIR/9-fix-verification/F-NN.md`:

```markdown
# Fix Verification Report — F-NN: <title>

## Verdict: PASS | FAIL | NEEDS REVIEW

## Vulnerability

- **Root cause**: <one-line description of what was fundamentally wrong>
- **Attack vector**: <how it could be exploited>
- **Affected component**: `<crate>::<module>::<function>` or instruction handler / extrinsic name

## Fix Analysis

- **What the fix does**: <one-line description of the change>
- **Root cause addressed**: Yes / No — <explain>
- **All instances covered**: Yes / No — <list any unfixed instances>
- **Diff scope**: <commit / range / branch comparison>
- **Files changed**: <count>
- **Lines changed**: +<additions>/-<deletions>

## Completeness

| Check | Status | Notes |
|-------|--------|-------|
| Root cause fixed | PASS / FAIL | <detail> |
| All code paths covered | PASS / FAIL | <detail> |
| Edge cases handled | PASS / FAIL | <detail> |
| Error handling correct | PASS / FAIL | <detail> |

## Regressions

| Check | Status | Notes |
|-------|--------|-------|
| No interface changes | PASS / FAIL / N/A | <detail> |
| No behavioral regressions | PASS / FAIL / N/A | <detail> |
| No new trust assumptions | PASS / FAIL / N/A | <detail> |
| Integration impact | PASS / FAIL / N/A | <detail> |
| Test integrity | PASS / FAIL / N/A | <detail> |

## Smart-contract-specific (Rust-tuned)

| Check | Status | Notes |
|-------|--------|-------|
| Re-entry coverage | PASS / FAIL / N/A | <detail> |
| Auth / account / origin | PASS / FAIL / N/A | <detail> |
| Arithmetic | PASS / FAIL / N/A | <detail> |
| State and storage | PASS / FAIL / N/A | <detail> |
| External calls | PASS / FAIL / N/A | <detail> |
| Token handling | PASS / FAIL / N/A | <detail> |
| Upgrade safety | PASS / FAIL / N/A | <detail> |

## Similar Patterns Found

<List any other locations in the codebase with the same vulnerability pattern, even if not in the original report. If none found, write "No additional instances found.">

## Patch-bypass prior (MANDATORY for PASS verdicts)

- **empirical base rate**: ~15% of security patches require subsequent fixes (Netlas 2025); 8% incomplete; 4% fundamentally incorrect.
- **PASS verdict status**: single-patch analysis; multi-patch sufficiency NOT proven here.
- **what could still be missing**:
  - <list specific sibling locations, follow-up exploit classes, integration breakage>
- **manual confirmation recommended before merge**: yes / no — <reason if no>

## Undecidable-patch flag

- **undecidable_patch**: yes / no
- <if yes: list hunks and what each plausibly fixes; verdict defaults to NEEDS REVIEW>

## Recommendation

<What should the developer do next? Merge as-is, apply additional changes, or investigate further. Be specific.>
```

## Verdict criteria

- **PASS**: Root cause addressed, all instances covered, no regressions found, no similar patterns elsewhere.
- **FAIL**: Root cause not addressed, fix is incomplete, or fix introduces a regression. Always explain what's wrong.
- **NEEDS REVIEW**: Fix looks correct but aspects you cannot fully verify (complex economic logic, external system behavior, production-state dependencies). Always explain what needs manual review and why.

## Patch-bypass calibration prior (MANDATORY in PASS verdicts)

Empirical patch-completeness studies on security CVEs find that **15.5% of security patches require subsequent fixes; 8.05% are classified as incomplete; 4.15% are fundamentally incorrect** (Netlas 2025, "When Patches Fail"). A Stage 9 PASS verdict that looks complete in isolation has, as a population prior, a ~15% chance of being the first of multiple patches required to fully fix the class.

Every PASS verdict file MUST include a `patch_bypass_prior` block surfacing this:

```markdown
## Patch-bypass prior (calibration context)

- **empirical base rate**: ~15% of security patches require subsequent fixes (Netlas 2025).
- **PASS verdict status**: this is a single-patch analysis; multi-patch sufficiency is NOT proven here.
- **what could still be missing**: 
  - sibling locations with the same root-cause pattern (see "Similar Patterns Found" section)
  - a follow-up exploit class enabled by the fix's new error path / new state field
  - integration breakage in downstream protocols composing this contract
- **manual confirmation recommended before merge**: yes
```

For FAIL and NEEDS REVIEW verdicts the prior block is optional but encouraged.

### Undecidable-patch flag

If the diff spans more than one logical change and the root cause is not unambiguously attributable to a single hunk, set `undecidable_patch: yes` in the verdict frontmatter and default the verdict to NEEDS REVIEW (per the MONO 2025 "undecidable patch" classifier: when expert reviewers cannot determine which hunk fixes which class, automated patch classifiers are wrong ~16.7% of the time). The verdict should explicitly list the hunks and what each plausibly fixes, so the user can decide which to validate manually.

### Executable subsumption check (v0.2.x candidate, NOT YET IMPLEMENTED)

When Stage 9 is invoked as part of a Stage 8 Phase 8a-pre joint Pass C re-pass — i.e., the question is "would patch A also prevent finding B's exploit?" — the strongest evidence is **executable**: apply A's diff to a worktree, re-run B's Stage 3 PoC, observe whether the PoC still fires.

Argus does not currently automate this. The Pass C judge reasons about fix-subsumption in English. The empirical patch-bypass rate above (15.5%) is the same prior that applies — judges who reason about subsumption without re-running the PoC are wrong at roughly that rate.

If you have local infrastructure to run the subsumption check (cargo worktrees, anchor test harness), do it manually and record the result in the verdict file. A future Argus version will automate this path. Until then, when Stage 9 is invoked in a fix-subsumption context (multi-finding collapse), default the verdict to NEEDS REVIEW unless a manual executable check is reported.

### References (literature backing this section)

- Netlas (2025), *When Patches Fail: An Analysis of Patch Bypass and Incomplete Security* — 15.5% / 8.05% / 4.15% rates.
- MONO (arXiv:2506.03651, 2025) — "undecidable patch" classifier; 16.7% of CVEs have undecidable patches.
- DISPATCH (USENIX Security 2021, `usenix.org/conference/usenixsecurity21/presentation/nguyen-tuan`) — decomposes entangled commits; preprocessing for multi-commit fix-verification.
- TreeVul (ICSE 2023, doi:10.1109/ICSE48619.2023.00088) — CWE-tree patch classification.
- DualLM / "What Do They Fix?" (NDSS 2026, arXiv:2509.22796) — LLM-aided patch categorization.

## Output rules

- Always produce a clear PASS / FAIL / NEEDS REVIEW verdict.
- Always explain reasoning — never just say "looks good".
- If FAIL, explain exactly what's wrong and suggest what to change.
- If NEEDS REVIEW, explain what you're uncertain about and what the developer should manually verify.
- If you find the same vulnerability pattern elsewhere, report those locations even if the original fix is correct.
- Keep output actionable — developers should know exactly what to do next.

## Quality bar

- Ground every assessment in the actual diff and codebase — never speculate about code you haven't read.
- If you can't determine whether the fix is complete, say so and explain why, rather than guessing.
- Treat the fix as suspicious by default — the goal is to find problems, not rubber-stamp.
- Consider both happy path and adversarial conditions when evaluating the fix.
- Apply the AI-provenance reminder from SKILL.md: even a Stage 9 PASS verdict is an AI-generated draft. The user remains responsible for manually reviewing the diff before merging.
