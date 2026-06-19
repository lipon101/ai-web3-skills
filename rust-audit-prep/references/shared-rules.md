# Shared Rules

## Output Format

Every assigned phase MUST use this exact structure:

```
PHASE <N> | <Name> | SCORE: <X>/100

FAIL | <check> | <-N> | <file:line or n/a>
desc: <one factual sentence — what is wrong>
fix: <one sentence — specific action to fix it>

PASS | <check>
note: <brief evidence>

END PHASE <N>
```

Rules:
- Every assigned phase MUST appear between PHASE and END markers
- FAIL needs: check name, deduction, file location (or `n/a`)
- `desc:` = factual problem statement
- `fix:` = specific actionable instruction (command to run, file to create, code to change)
- PASS needs: check name, optional `note:` with evidence
- Score = 100 minus deductions (min 0, max 100). Apply deduction caps from your checklist.
- One blank line between each FAIL/PASS block

## DO NOT Report

Never flag: compute/gas optimizations (CU reduction, zero-copy suggestions, clone removal),
functions >60 lines, magic numbers, naming conventions, code style.
These are informational and do not affect audit readiness.

## DO NOT Do

- Do NOT perform security vulnerability analysis or threat modeling
- Do NOT suggest architecture changes or redesigns
- Do NOT produce prose, tables, summaries, or markdown formatting
- Do NOT output anything except the structured PHASE/FAIL/PASS format above
- Do NOT analyze files outside the project directory

## Scope

Only the project's own program source (programs/*/src/ or src/, excluding target/, tests/, test/, node_modules/, .anchor/).
- Inline `//` comments explaining purpose = documented (not a finding)
- `#[msg("...")]` on error variants = documented (not a finding)
- `/// CHECK:` on UncheckedAccount = documented (not a finding)
- `unsafe` with `// SAFETY:` = justified (INFO only, no deduction)
- Pinned older dependency versions in audited code = INFO only (no deduction)
