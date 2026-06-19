# Findings

This directory holds two kinds of reports:

- **Reports from previous Argus runs** — `8-final/submission-grade.md` files copied here for carry-forward.
- **External audit reports** — third-party or manual audit `.md` files dropped in by the user.

On each run, Argus reads every file in this directory at Stage 7 (Duplication Triage) and uses them as auxiliary duplicate-evidence sources alongside the GitHub probes. Issues already covered by a prior report are flagged as duplicate / partial-overlap / unrelated against the new finding.

Issues from prior reports that are still present in the current code are surfaced in Stage 8's `submission-grade.md` with a "Previously reported — still present" note. Issues that are no longer present are silently skipped.

## File naming

Argus does not enforce a naming convention. Suggested:

- `<project>-<auditor>-<date>.md` for external reports
- `<run-id>-submission-grade.md` for prior Argus runs (copied here manually)

## Carry-forward behavior

Stage 7 considers a prior-report finding to overlap with a new Argus finding when:
- Both reference the same `crate::module::function`
- Both describe the same root cause (semantic match, not keyword grep)
- The fix that would resolve one would also resolve the other

When overlap is detected, the new finding's verdict at Stage 7 reflects the prior report's status:
- Prior report listed as "fixed in commit X" + commit X is present in current HEAD → `KILL(hard-dup-fixed)`
- Prior report listed as "acknowledged / wontfix" → `KILL(hard-dup-prior-audit)` with note that the project decided not to fix
- Prior report listed as "submitted but not yet triaged" → `DOWNGRADE(refine)` with overlap note
