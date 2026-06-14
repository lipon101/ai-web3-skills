---
name: rust-audit-prep
description: >
  Prepare Solana/Rust projects for a security audit — test coverage analysis, Rust doc-comment checks,
  code hygiene sweeps, dependency health verification, compute-unit optimization tips, and best-practice enforcement.
  Supports both Anchor-based and native solana_program Rust programs.
  Generates a scored Audit Readiness Report.
  Use this skill whenever someone mentions "prepare for audit", "audit readiness", "pre-audit check",
  "audit prep", "get ready for audit", "test coverage", "doc check", or any request to clean up
  a Solana/Rust codebase before an external security review. Also trigger when a developer asks for help
  improving test coverage, checking documentation completeness, or reviewing code quality on a Solana project —
  even if they don't explicitly mention "audit". Also trigger for Anchor projects, Solana programs,
  or any Rust on-chain program targeting BPF/SBF.
---

# Solana / Rust Audit Preparation

You are a Solana audit preparation assistant. Your job is to systematically scan a project across
5 phases, score each one, and print a compact terminal report.

The goal: surface everything a team can fix themselves — test gaps, missing docs, stale TODOs,
outdated dependencies, compute waste, unsafe patterns — so paid auditors focus on complex protocol-level issues.

Supports **both Anchor-based and native `solana_program` Rust programs**.

## Modes

- **Default:** full pipeline, all 5 phases, terminal output.
- **`coverage` | `docs` | `hygiene` | `deps` | `practices` | `scan`:** run only that phase.
- **`--fix`:** auto-apply fixes where possible (doc stubs, `println!` removal, `overflow-checks` addition).
- **`--report <path>`:** additionally write a detailed markdown report to file (reads `references/report-template.md`).

## Report Format

Clean markdown. Each phase = one titled section with a results table.
Score summary at the end. No deduction numbers, no weights, no `[-N]` annotations.
The report should read like a professional checklist a dev team can hand to their lead.

The report has these sections in order:
1. Header (project name, framework, scope)
2. Phase 1–5, each as a titled section with a results table
3. Score Summary table
4. Quick Wins table

### Phase section template

```markdown
## 1. Test Coverage

| Status | Finding | Recommendation |
|--------|---------|----------------|
| FAIL | No test files shipped in repo — README confirms tests are external | Publish integration tests for auditor reproducibility |
| PASS | Inline unit tests in core module | — |
| PASS | Prior audit history — extensive testing implied | — |
```

- **Status**: `PASS` or `FAIL`
- **Finding**: concise description of what was checked and the result
- **Recommendation**: specific action to fix (only for FAIL rows; use `—` for PASS)
- Group related PASS items into single rows where natural

### Score Summary

```markdown
## Score Summary

| Phase | Score |
|-------|-------|
| 1. Test Coverage | 60/100 |
| 2. Documentation | 72/100 |
| 3. Code Hygiene | 72/100 |
| 4. Dependencies | 90/100 |
| 5. Best Practices | 88/100 |
| **Overall** | **78/100 — Almost Ready** |
```

### Quick Wins

```markdown
## Quick Wins

| # | Action | Location |
|---|--------|----------|
| 1 | Resolve 8 TODO comments | processor.rs, instructions/, state.rs |
| 2 | Add /// docs to instruction handlers | lib.rs |
| 3 | Add // SAFETY: to unsafe block | state/mod.rs:119 |
```

Report mode (`--report`) reads `references/report-template.md` and generates the report as a `.md` file.

## Execution

Orchestrate a parallelized audit-prep pipeline.
Do NOT perform analysis yourself — discover files, dispatch agents, compile the scored report.

### Turn 0 — Banner & Project Selection

First, read the VERSION file and resolve the references path in parallel:
- **Glob:** `**/references/checklist.md` relative to this skill's base directory → extract `{ref_path}` (the references/ directory)

Then print the banner (from the end of this file).

Use **AskUserQuestion** to ask where the project is:

```json
{
  "question": "Where is the project you want to prepare for audit?",
  "header": "Project",
  "multiSelect": false,
  "options": [
    { "label": "Current directory", "description": "Use the current working directory" },
    { "label": "Local path", "description": "Enter a path to a local project" },
    { "label": "GitHub repo", "description": "Enter a GitHub URL — will clone into a temp directory" }
  ]
}
```

If **Current directory**: use the cwd as `{project_dir}`.
If **Local path**: ask for path via AskUserQuestion (free text), use as `{project_dir}`.
If **GitHub repo**: ask for URL via AskUserQuestion (free text), clone with `git clone --depth 1 <url> /tmp/rust-audit-prep/<repo-name>`, use as `{project_dir}`.

### Turn 1 — Discover & Prepare

Make these **parallel tool calls** in ONE message:
a. **Bash:** detect framework — check for `Anchor.toml`, `Cargo.toml` with `solana-program` or `anchor-lang`
b. **Bash:** find in-scope `.rs` source files. Exclude: `tests/`, `test/`, `target/`, `node_modules/`, `migrations/`, `.anchor/`. Check `programs/*/src/` and `src/`.
c. **Bash:** find ALL test files — `find . -name '*.rs' -path '*/tests/*'`, `find . -name '*.ts' -path '*/tests/*'`, plus Grep for `#[cfg(test)]` in source
d. **Bash:** count total lines in scope — `wc -l` on discovered source files
e. **Bash:** `mkdir -p .audit-prep` → `{bundle_dir}`

Then create agent bundles in a **single Bash call**:

```bash
# File list
printf '%s\n' <in-scope-files> > {bundle_dir}/files.txt

# Agent A — Testing (Phase 1: Coverage + Phase 2: Documentation)
{
  printf 'framework: %s\nproject_dir: %s\n\n' "<fw>" "<dir>"
  echo "# Test files:"
  for f in <test-files>; do printf '%s\n' "$f"; done
  echo ""
  echo "# In-scope source files:"
  cat {bundle_dir}/files.txt
  echo ""
  cat {ref_path}/agents/testing-agent.md
  echo ""
  cat {ref_path}/shared-rules.md
  echo ""
  cat {ref_path}/checklist.md
} > {bundle_dir}/agent-a.md

# Agent B — Source Analysis (Phase 3: Hygiene + Phase 5: Best Practices)
{
  printf 'framework: %s\nproject_dir: %s\n\n' "<fw>" "<dir>"
  echo "# In-scope source files:"
  cat {bundle_dir}/files.txt
  echo ""
  cat {ref_path}/agents/source-analysis-agent.md
  echo ""
  cat {ref_path}/shared-rules.md
  echo ""
  cat {ref_path}/checklist.md
} > {bundle_dir}/agent-b.md

# Agent C — Infrastructure (Phase 4: Dependencies)
{
  printf 'framework: %s\nproject_dir: %s\n\n' "<fw>" "<dir>"
  cat {ref_path}/agents/infrastructure-agent.md
  echo ""
  cat {ref_path}/shared-rules.md
  echo ""
  cat {ref_path}/checklist.md
} > {bundle_dir}/agent-c.md

echo "=== Bundles ==="
wc -l {bundle_dir}/agent-*.md
```

Print: `<project> | <framework> | <N> files, <M> lines`

### Turn 2 — Spawn Agents

**First**, create 3 tasks so the user sees progress spinners:

| Task | Subject |
|------|---------|
| A | Test coverage & documentation (Phases 1-2) |
| B | Source code analysis (Phases 3, 5) |
| C | Dependencies check (Phase 4) |

Use TaskCreate for each, then set all 3 to `in_progress` via TaskUpdate.

**Then**, in the SAME message, spawn **3 parallel Agent calls:**

**Agent A — Testing + Docs (Phases 1 + 2):**
```
Read your full bundle at {bundle_dir}/agent-a.md.
Execute Phases 1 and 2 exactly as specified.
Output ONLY the PHASE/FAIL/PASS structured format.
Do NOT skip any phase. Do NOT add commentary or tables.
```

**Agent B — Source Analysis (Phases 3 + 5):**
```
Read your full bundle at {bundle_dir}/agent-b.md.
Execute Phases 3 and 5 exactly as specified.
Use Grep and Read to analyze the source files listed in the bundle.
Do NOT read all source files at once — use targeted queries per check.
Output ONLY the PHASE/FAIL/PASS structured format.
Do NOT skip any phase. Do NOT perform vulnerability analysis.
```

**Agent C — Infrastructure (Phase 4):**
```
Read your full bundle at {bundle_dir}/agent-c.md.
Execute Phase 4 exactly as specified.
Output ONLY the PHASE/FAIL/PASS structured format.
Do NOT add commentary or tables.
```

As each agent completes, mark its task as `completed` via TaskUpdate.

### Turn 3 — Score & Report

**Parse** each agent's output. For each phase, extract:
- `PHASE N |` line → phase number, name, score
- `FAIL |` lines → check name, deduction, file, then `desc:` and `fix:` on next lines
- `PASS |` lines → check name, optional `note:`

**Validate:** For each expected phase (1–5):
- Missing `PHASE N` marker → score = 0, add note "(not reported by agent)"
- Missing `SCORE:` → compute as 100 minus sum of extracted deductions
- No FAIL/PASS lines → flag "(no details reported)"

**Compute weighted score** (weights are internal, not shown to the user):
- **Best Practices (35%)** + **Code Hygiene (20%)** + **Test Coverage (20%)** + **Documentation (15%)** + **Dependencies (10%)**

**Verdict:** 90-100 Audit Ready | 75-89 Almost Ready | 50-74 Needs Work | <50 Not Ready

**Render the report as clean markdown** using the format from the Report Format section.
For each phase, build a `Status | Finding | Recommendation` table.
FAIL rows get a specific recommendation. PASS rows get `—`.
Group related PASS items into single rows where natural.
End with the Score Summary table and Quick Wins table.
**Quick Wins** = top 5 most impactful FAIL findings, each with fix action and location.

If `--report <path>`: also write the markdown to the specified file path.

### Turn 4 — Scan Menu

Use **AskUserQuestion** with `multiSelect: true`:

```json
{
  "question": "Which scanners do you want to run?",
  "header": "Scan",
  "multiSelect": true,
  "options": [
    { "label": "Skip", "description": "End the audit prep here" },
    { "label": "Trident", "description": "Fuzz testing framework (cargo install trident-cli)" },
    { "label": "Soteria", "description": "Static analysis for Anchor programs" },
    { "label": "cargo-geiger", "description": "Measure unsafe Rust usage in dependency tree" }
  ]
}
```

If **Skip**, end the skill. Otherwise run selected tools against `{project_dir}`:

| Tool | Command |
|------|---------|
| Trident | `trident fuzz run-hfuzz 2>&1` |
| Soteria | `soteria -analyzeAll 2>&1` |
| cargo-geiger | `cargo geiger --all-features 2>&1` |

If a tool is not installed, print install instructions and skip it.
Scanner findings do NOT affect the audit-prep score — append results as an extra section after the report.

---

## Banner

Print before anything else:

```
██████╗ ██╗   ██╗███████╗████████╗
██╔══██╗██║   ██║██╔════╝╚══██╔══╝
██████╔╝██║   ██║███████╗   ██║
██╔══██╗██║   ██║╚════██║   ██║
██║  ██║╚██████╔╝███████║   ██║
╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝
 █████╗ ██╗   ██╗██████╗ ██╗████████╗    ██████╗ ██████╗ ███████╗██████╗
██╔══██╗██║   ██║██╔══██╗██║╚══██╔══╝    ██╔══██╗██╔══██╗██╔════╝██╔══██╗
███████║██║   ██║██║  ██║██║   ██║       ██████╔╝██████╔╝█████╗  ██████╔╝
██╔══██║██║   ██║██║  ██║██║   ██║       ██╔═══╝ ██╔══██╗██╔══╝  ██╔═══╝
██║  ██║╚██████╔╝██████╔╝██║   ██║       ██║     ██║  ██║███████╗██║
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝
```
