# Commit Fix Analysis Guide

## Output Schema

Save the completed report to `<repo_root>/git-fix-finder-report.md` unless the user asked for a different filename.

Start the file with:

```markdown
# Git Fix Finder Report

- Repository: `<repo path>`
- Scope: `<revset or full history>`
- Generated: `<YYYY-MM-DD>`
```

Use one summary table and then short writeups for the non-rejected candidates.

Table columns:

`sha | date | classification | vulnerability | contracts/functions | confidence`

Per-commit writeup:

```markdown
### <short sha> <subject>

- Classification: `CONFIRMED FIX | LIKELY FIX | NOT A VULN FIX`
- Vulnerability: <plain-language bug description>
- Pre-fix behavior: <what the old code allowed>
- Fix mechanism: <what the patch changed>
- Reachability: <entrypoint or call chain, or explain why reachability is inferred>
- Code snippets:
  - Before: short excerpt from the parent revision that shows the vulnerable logic, with a file reference
  - After: short excerpt from the fixed revision that shows the guard/accounting change, with a file reference
- Evidence:
  - Commit: `<sha>`
  - Files: `path:line` references from the fixed tree or the parent tree
  - Tests: note whether the commit adds a regression test
- Confidence: `high | medium | low`
- Open questions: <only if needed>
```

Snippet rules:

- Keep each excerpt short and focused on the changed invariant, not the whole function.
- Prefer one `before` and one `after` snippet per vulnerability statement.
- Label snippets with the tree they came from, for example `parent` and `fixed`.
- Always pair each snippet with a `path:line` reference so the reader can inspect the full function.

Prefer one vulnerability statement per commit. If a single commit fixes multiple unrelated issues, split them.

End the report with a rejected-candidates section when applicable:

```markdown
## Rejected Candidates

- `<sha>` `<subject>`: short reason it is not a vulnerability fix
```

## Triage Rubric

Positive signals:

- Commit message mentions `fix`, `patch`, `security`, `exploit`, `permit`, `oracle`, `overflow`, `reentrancy`, `malleability`, `liquidation`, `issuance`, or similar terms.
- Diff adds or tightens guards such as `require`, access control, signature validation, safe transfer wrappers, arithmetic bounds, or accounting updates.
- Critical state machines or pool/accounting contracts change.
- A regression test lands in the same commit and documents a previously failing sequence.

False-positive signals:

- Only docs, scripts, release metadata, or CI files change.
- The diff is only event emission cleanup, logging, comments, or dead variable removal.
- The change is a version bump or broad refactor without a narrowed security invariant.

Review habits:

- Compare the parent revision to the fixed revision before naming the bug.
- If the patch is subtle, inspect the touched invariant and downstream assumptions, not only the inserted line.
- A fix commit can still leave residual risk or introduce a new bug. Do not assume "post-fix" means "safe."

## Worked Examples From This Repo

### Likely fix: `2a1fe27` `fix: fix as per SECFIN2-1 [#12]`

Why it ranks high:

- Touches `contracts/DebtToken.sol` permit-style signature recovery.
- Replaces raw `ecrecover` with OpenZeppelin-style `ECDSA.recover`.
- Adds lower-half-`s` and valid-`v` checks in the bundled library.

Likely vulnerability statement:

- Signature malleability or invalid-signature acceptance in the debt token permit flow.

Why the label is `LIKELY FIX` by default:

- The diff clearly hardens signature validation.
- Exploitability still depends on the surrounding nonce/deadline logic, so inspect the full permit path before upgrading it to `CONFIRMED FIX`.

### False positive: `c819e45` `fix: fix as per SECFIN2-2 [#12]`

Why it should usually be rejected:

- The diff only adds missing `emit` keywords and removes an unused local variable.
- Missing events can matter for monitoring and integrations, but this patch does not obviously close a protocol exploit path.

Default classification:

- `NOT A VULN FIX`, unless another contract or off-chain safety system relied on those events as a hard security control.

### Important caution: `ac88166` `fix: fix protocol token allocation issue [#35]`

Why it is still worth deep review:

- It changes reward issuance accounting in `contracts/ProtocolToken/CommunityIssuance.sol` and rewires the funding flow.
- It adds tests, so it looks like a canonical "bug fix" commit.

Why this is a useful example for the skill:

- A commit can fix one issue while leaving another accounting bug or business-logic edge case behind.
- When a patch changes global accounting rules, always restate the old invariant and the new invariant in plain language and test both.
