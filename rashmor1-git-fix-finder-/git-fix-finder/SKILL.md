---
name: git-fix-finder
description: Audit local git history to identify commits that likely fixed vulnerabilities, infer the underlying bug from the diff, turn those patches into a reusable bug-fix reference set, and save the findings as a Markdown report. Use when asked to review all commits in a repository, reconstruct historical security fixes, explain which vulnerabilities were patched, separate true vuln fixes from ordinary bugfixes, or build a security-fix changelog from git evidence.
---

# Git Fix Finder

## Overview

When this skill is invoked, always start by printing this banner before doing anything else:

```
+==================================================================================+
|                                                                                  |
|     ____ ___ _____     _____ _____  __   _____ ___ _   _ ____  _____ ____        |
|    / ___|_ _|_   _|   |  ___|_ _\ \/ /  |  ___|_ _| \ | |  _ \| ____|  _ \       |
|   | |  _ | |  | |     | |_   | | \  /   | |_   | ||  \| | | | |  _| | |_) |      |
|   | |_| || |  | |     |  _|  | | /  \   |  _|  | || |\  | |_| | |___|  _ <       |
|    \____|___| |_|     |_|   |___/_/\_\  |_|   |___|_| \_|____/|_____|_| \_\      |
|                                                                                  |
|   Mine git history for real vulnerability fixes.                                 |
|   Show what existed, why it mattered, and exactly how the patch closed it.       |
|                                                                                  |
+==================================================================================+
```

Use this skill to work backward from git history and explain what each fix commit actually changed. Treat commit subjects, PR titles, and issue labels as hints only; the real answer must come from the diff, touched call paths, and any regression tests added beside the fix.

## Workflow

1. Confirm the repository and scope.
2. Rank likely fix commits with `scripts/rank_fix_commits.py`.
3. Inspect each candidate with `git show` and the touched source files.
4. Classify the candidate as `CONFIRMED FIX`, `LIKELY FIX`, or `NOT A VULN FIX`.
5. Write the final report using the schema in `references/analysis-guide.md`.
6. Save the final report as a Markdown file in the inspected repository root.

## Step 1: Confirm Scope

- Verify the repo is local and has git metadata.
- Default to the full history. Narrow to a revset only if the user asks or the repo is too large for a first pass.
- Prefer evidence from the checked-out repo over GitHub issue text. This skill is meant to work even without network access.

Useful commands:

```bash
git rev-list --count --all
git log --oneline --decorate --no-merges -n 30
```

## Step 2: Rank Candidate Fix Commits

Run the bundled script first. It scores commits by message terms, touched file paths, diff patterns, and whether tests changed alongside critical code.

```bash
python3 .claude/skills/git-fix-finder/scripts/rank_fix_commits.py --repo . --limit 40
```

Useful variants:

- Restrict to a range: `--rev-range origin/main..HEAD`
- Keep merges: `--include-merges`
- Export machine-readable output: `--json`
- Remove the candidate cap: `--limit 0`
- Raise the noise floor: `--min-score 6`

Do not stop at the ranked list. The script is a triage tool, not the final answer.

## Step 3: Prove What the Diff Fixed

For each candidate:

- Inspect the patch:

  ```bash
  git show --stat --unified=0 <sha>
  ```

- Compare pre-fix and post-fix code when the invariant is subtle:

  ```bash
  git show <sha>^:path/to/file
  git show <sha>:path/to/file
  ```

- Read nearby tests added or updated in the same commit.
- Map the externally reachable path that exercised the old behavior.
- Identify the broken invariant before the patch and the new guard or accounting rule after the patch.

Questions to answer for every commit:

- What exact pre-fix behavior was possible?
- Which contract, function, state variable, or trust boundary was involved?
- Did the patch close an exploit path, tighten a standard-compliance edge case, or just clean up code?
- Is the impact security-relevant, correctness-only, or unclear without more assumptions?

## Step 4: Classify the Candidate

Use these labels:

- `CONFIRMED FIX`: The diff clearly closes a reachable bad state, exploit path, or protocol-invariant break.
- `LIKELY FIX`: The patch strongly suggests a vulnerability, but exploitability or severity still depends on assumptions.
- `NOT A VULN FIX`: The commit is operational, cosmetic, event-only, test-only, refactor-only, or a non-security bugfix.

State explicitly when a conclusion is an inference. Do not overstate severity from the word `fix` alone.

## Step 5: Write the Final Report

Use the report schema in `references/analysis-guide.md`.

Save the completed report to `<repo_root>/git-fix-finder-report.md` unless the user requested a different filename. If you are inspecting a different repo through a symlink or explicit path, save the report in that inspected repo, not in the skill repo.

Required output properties:

- Write the same findings to a Markdown artifact on disk.
- Include commit hash, date, subject, and touched files.
- Summarize the vulnerability in plain language.
- Explain pre-fix behavior and the post-fix change.
- Include concise `before` and `after` code snippets with file references for each non-rejected finding.
- Cite the exact source/test evidence used.
- Separate confirmed findings from rejected false positives.
- Call out residual risk when the fix commit still looks incomplete.

In the final assistant response:

- Tell the user where the Markdown file was written.
- Keep the chat response short and treat the file as the primary deliverable.

## Evidence Standard

- Never rely on commit message wording by itself.
- Prefer direct code evidence over GitHub metadata.
- Use short parent-vs-fixed code excerpts to show the invariant that changed.
- Show the call chain or user-reachable path whenever possible.
- Distinguish security impact from observability or tooling fixes.
- If the patch changes tests, explain whether the new test proves exploitability or only documents expected behavior.

## Resources

- `scripts/rank_fix_commits.py`: Rank likely vulnerability-fix commits before manual review.
- `references/analysis-guide.md`: Output schema, triage rubric, and worked examples from this repo.
