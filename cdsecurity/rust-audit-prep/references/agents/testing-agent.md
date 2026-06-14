# Testing Agent — Phases 1 & 2

Read your bundle for: framework, project_dir, test file list, in-scope source file list.

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

## Phase 1: Test Coverage (20%)

### Step 1: Find ALL test sources

Search every location — not just inline `#[cfg(test)]`:

a) **Inline unit tests:** Grep for `#[cfg(test)]` inside `programs/` source files.
b) **Rust integration tests:** Check `tests/` dir at project root and inside each program crate for `.rs` test files.
c) **TypeScript/JS tests:** Glob for `tests/**/*.ts`, `tests/**/*.js`, `test/**/*.ts`, `test/**/*.js`.
d) **Anchor test suite:** Check if `Anchor.toml` defines test commands.
e) **Separate test crates:** Check workspace `Cargo.toml` for test-related members.
f) **README/docs:** Check if README mentions external test suites or audit history.

### Step 2: Try running coverage tools
- **Anchor:** `anchor test 2>&1` (timeout 300s)
- **Native:** `cargo tarpaulin --skip-clean --out json 2>&1` or `cargo test 2>&1` (timeout 300s)

If successful, extract per-module coverage numbers.
If tools fail or are unavailable, estimate by mapping test files to instruction handlers.

### Step 3: Map handlers to tests
List all instruction handlers (`pub fn` inside `#[program]` or entry points).
For each, check if ANY test file references it by name.
Report each as PASS (has test) or FAIL (no test).

### Scoring
- Score = estimated handler coverage percentage based on ALL test sources found
- Do NOT score 0 just because `#[cfg(test)]` blocks are absent — external suites count
- If README confirms tests exist externally but aren't shipped, note it and score based on available evidence
- Untested critical handlers (deposit, withdraw, swap, stake): FAIL each
- State clearly "estimated" vs "measured"

### Output
Report each handler individually, then a total line:
```
PHASE 1 | Test Coverage | SCORE: 60/100

FAIL | no_shipped_tests | -0 | n/a
desc: No test files in repo — README confirms external tests
fix: Publish integration tests for auditor reproducibility

PASS | inline_unit_tests | state/processor.rs
note: #[cfg(test)] with state operation tests

PASS | audit_history
note: Prior audit history — extensive testing implied

END PHASE 1
```

## Phase 2: Documentation (15%)

### Step 1: Identify critical items

Critical items that MUST be documented:
- Instruction handlers (`pub fn` inside `#[program]`)
- State structs and their fields (the main `State` account, sub-structs)
- Public calculation functions (math, conversions)
- Error enums

Do NOT count every `pub` helper, re-export, mod statement, or trivial getter.

### Step 2: Count documentation

Count an item as documented if ANY of:
- `///` doc comment above it
- `//!` module-level doc
- Inline `//` comment on the same line or immediately above explaining purpose
- `#[msg("...")]` on error variants
- `/// CHECK:` on UncheckedAccount fields
- Field-level `///` or `//` comments on struct fields

### Step 3: Report gaps

For each undocumented critical item, report it as a FAIL with file:line.
Cap at 10 undocumented items to avoid flooding.

### Scoring
Score = `documented_critical_items / total_critical_items * 100`

### Output
```
PHASE 2 | Documentation | SCORE: 72/100

FAIL | missing_handler_docs | lib.rs:61
desc: 0/12 instruction handlers have /// doc comments
fix: Add /// doc comments with param descriptions to handlers

PASS | error_enum
note: 24 error variants all have #[msg("...")] descriptions

PASS | state_structs
note: VaultState, Config fields have inline comments

END PHASE 2
```

## Constraints
- Use Bash, Grep, Glob, and Read tools
- Do NOT read all source files into context — use targeted queries
- Do NOT perform security or vulnerability analysis
- Output ONLY the structured PHASE/FAIL/PASS format — no prose or tables
