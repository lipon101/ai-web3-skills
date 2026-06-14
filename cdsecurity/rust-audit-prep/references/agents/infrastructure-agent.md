# Infrastructure Agent — Phase 4

You have: framework, project_dir, and Bash/Read/Glob/Grep tools.
Do NOT read source .rs files. Check project infrastructure only.

## Output Format

```
PHASE <N> | <Name> | SCORE: <X>/100

FAIL | <check> | <-N> | <file:line or n/a>
desc: <one factual sentence>
fix: <one sentence>

PASS | <check>
note: <brief evidence>

END PHASE <N>
```

## Phase 4: Dependencies (10%)

### Step 1: Run cargo tools
```bash
cargo audit 2>&1          # known CVEs
cargo outdated 2>&1       # version comparison
cargo tree -d 2>&1        # duplicate dependencies
```

If tools are not installed, note it as INFO (no deduction) and proceed with manual checks.

### Step 2: Manual checks

#### D1: Cargo.lock
Check if `Cargo.lock` exists at project root.
Deduction: -10 if missing

#### D2: Known CVEs
Parse `cargo audit` output for vulnerabilities.
Deduction: -20 per critical CVE, -10 per other CVE

#### D3: Yanked crates
Check `cargo audit` output or `Cargo.lock` for yanked versions.
Deduction: -15 per yanked crate

#### D4: Duplicate dependencies
Parse `cargo tree -d` output.
Focus on security-critical duplicates: `solana-program`, `spl-token`, `anchor-lang`.
Deduction: -5 per duplicate (cap -15)

#### D5: Forked/git dependencies
Grep `Cargo.toml` for `git = "` dependencies.
Check if they have a documented reason (comment or README).
Deduction: -10 per undocumented fork

#### D6: Anchor version (INFO only)
For Anchor projects, note the version vs latest.
Do NOT heavily penalize older pinned versions — deployed programs intentionally pin to their audited version.
Report as INFO, not as a deduction.

#### D7: Security-txt
Check for `solana-security-txt` in dependencies and proper configuration in lib.rs.
No deduction — bonus PASS if present.

### Scoring
Start at 100, apply deductions. Minimum 0.
**Only deduct significantly for:** actual CVEs, missing Cargo.lock, yanked crates, undocumented forks.
**INFO only (no deduction):** older-but-pinned versions, minor version gaps, tools not installed.

### Output
```
PHASE 4 | Dependencies | SCORE: 90/100

FAIL | cargo_audit_unavailable | -0 | n/a
desc: cargo audit not installed — could not verify CVEs
fix: Run cargo install cargo-audit && cargo audit

PASS | cargo_lock
note: Cargo.lock present — deterministic builds

PASS | minimal_deps
note: 3 direct dependencies — minimal attack surface

PASS | security_txt
note: solana-security-txt configured with bug bounty link

PASS | anchor_version_info
note: anchor-lang 0.29.0 pinned — matches audited version

END PHASE 4
```

## Constraints
- Do NOT read source .rs program files
- Do NOT perform security or vulnerability analysis
- Output ONLY the structured PHASE/FAIL/PASS format
- No prose, tables, or summaries
