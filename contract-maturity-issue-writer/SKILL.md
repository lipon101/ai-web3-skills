---
name: contract-maturity-issue-writer
description: Use when assessing a smart contract repository with code maturity criteria and converting concrete gaps into structured GitHub issues.
---

# Contract Maturity Issue Writer

## Overview

Use this skill for Solidity or protocol repositories when the goal is to turn a code maturity assessment into concrete, file-backed GitHub issues.

This skill does not replace the assessment. It first uses the Trail of Bits-based `code-maturity-assessor`, then converts concrete findings into issue drafts or approved GitHub issues.

## When to Use

Use when:
- a smart contract repo needs a backlog derived from a maturity assessment
- the user wants actionable issues instead of a long assessment report
- findings need exact file paths, code locations, and test scope

Do not use when:
- the repository is not a smart contract or protocol repo
- the user wants a pure security audit without backlog generation
- there is not enough evidence to tie a finding to specific files or code locations

## Workflow

1. Confirm repository fit
   - Verify the repo is Solidity or protocol focused.
   - If it is not, explain that `code-maturity-assessor` is contract-centric and stop or switch approaches.

2. Verify the prerequisite skill exists and matches the expected source
   - Check whether `code-maturity-assessor` is available in the current skill set.
   - Confirm the installed skill is the one based on Trail of Bits' "Building Secure Contracts - Code Maturity Evaluation" framework.
   - If it is missing, invoke `skill-installer` and install the correct `code-maturity-assessor` before continuing.
   - If a different local skill with the same name exists but does not clearly match the Trail of Bits framework, stop and tell the user the prerequisite is ambiguous.

3. Run maturity assessment
   - Invoke the Trail of Bits-based `code-maturity-assessor`.
   - Reuse its evidence instead of re-scoring the repo from scratch.

4. Extract concrete gaps
   - Keep only findings that can be tied to specific files, functions, branches, or test gaps.
   - Separate current behavior from proposed behavior.

5. Cluster into issue-sized themes
   - Group findings by coherent implementation area such as:
     - state-machine boundaries
     - access control
     - bond or accounting logic
     - query or read APIs
     - governance or decentralization gaps
     - documentation or monitoring gaps
   - Do not combine unrelated categories into one issue just to reduce count.

6. Write issue drafts
   - Default to drafts first.
   - Use the issue template below.
   - For timing or threshold logic, specify `boundary - 1`, `boundary`, and `boundary + 1`.
   - For auth logic, name exact revert or custom errors when the code exposes them.
   - For accounting logic, state the balance, reserve, or allowance effect that tests should assert.

7. Publish only after approval
   - Present the issue drafts to the user.
   - Only after approval, use `gh issue create` or `gh issue edit`.

## Issue Template

```md
## Summary
[One short paragraph describing the gap and why it matters.]

## File Path
- `path/to/primary/file.ext`
- `path/to/existing/test_file.ext`
- `path/to/related/helper_or_mock.ext`

## Code Locations
- `functionOrModuleA(...)` at `path/to/file.ext:LINE`
- `branch/check/event` at `path/to/file.ext:LINE`
- `related getter/helper` at `path/to/file.ext:LINE`

## Current Coverage
- Existing tests already cover [what is already tested].
- Missing coverage is mainly around [boundary/default/error-path/state-transition/etc.].

## Detailed Scope
- Add tests for [specific function or path]:
  - [exact input/state]
  - [expected success or revert]
  - [expected state change / emitted event / returned value]
- Add tests for [another path]:
  - [boundary - 1]
  - [boundary]
  - [boundary + 1]
- Add tests for [negative case]:
  - [unauthorized caller]
  - [invalid state]
  - [missing dependency / zero address / insufficient balance]
- If current behavior is surprising but intentional, say so explicitly:
  - [document current behavior rather than changing semantics in this issue]

## Why
[2-4 sentences on risk: security, accounting, state machine, API contract, regression risk, etc.]

## Acceptance Criteria
- Every listed path has direct test coverage.
- Tests assert exact errors, return values, and state fields, not only "call succeeds".
- Boundary behavior is covered explicitly where timing, math, or threshold logic is involved.
- Uninitialized or default-state behavior is covered where relevant.
- Tests are readable enough that expected behavior can be inferred from test names alone.
```

## Writing Rules

- Always include `File Path`.
- Always include `Code Locations` with exact lines if available.
- Describe current behavior, not guessed behavior.
- Distinguish existing coverage from missing coverage.
- Prefer one issue per coherent theme.
- Do not write vague TODO issues that lack a concrete implementation surface.

## Common Mistakes

- Assuming any `code-maturity-assessor` is acceptable without checking that it is the Trail of Bits-based framework.
- Skipping the maturity assessment and jumping straight to issues.
- Writing issues from category names alone without file-backed evidence.
- Confusing current behavior with desired behavior.
- Writing "add more tests" without naming specific functions, branches, or revert paths.
- Using broad issue scopes that mix testing, governance, and accounting changes together.

## Output Modes

- Draft mode:
  - Produce issue markdown only.
- Publish mode:
  - After user approval, create or edit GitHub issues with `gh`.

Default to draft mode unless the user explicitly asks to post or update issues.
