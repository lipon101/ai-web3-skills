---
name: skill
description: Deterministic zero-loss runbook for generating Anchor protocol reconnaissance reports from rust-recon facts.
---

# rust-recon Skill Runbook (v3.1, Zero-Loss Recon)

This skill is a deterministic runbook for generating protocol reconnaissance reports from
`rust-recon` outputs.

This workflow is recon-first, not vulnerability-rating-first.

<critical_directives>
1. YOU ARE FORBIDDEN FROM WRITING PYTHON, BASH, OR NODE SCRIPTS TO PARSE JSON.
2. YOU MUST USE YOUR NATIVE FILE-READING TOOLS.
3. YOU MUST OUTPUT THE REPORT DIRECTLY USING NATIVE REASONING.
</critical_directives>

Before generating any report content, you MUST print this exact line:
"I am beginning a native reasoning pass over facts.json. I will not use temporary scripts. I will ensure zero data loss."

## CRITICAL: Zero Data Loss Policy

The report MUST contain ALL data from extracted facts. Specifically:
- Every instruction in `instructions[]` gets a full Section 2 subsection (2a-2f).
- Every param in `params[]` gets a row in 2a.
- Every account in `accounts[]` gets a row in 2b.
- Every step in `execution_steps[]` gets a line in 2c.
- Every mutation in `state_mutations[]`, `sol_flows[]`, `token_flows[]`, `set_authority_calls[]` gets a row in 2d.
- Every arithmetic op in `arithmetic[]` gets a row in 2e.
- Every error in `errors[]` gets a row in Section 6.
- Every flag in `flags[]` gets a row in Section 7.
- Every struct in `data_structs[]` gets a table in Section 3a.

"Omitted for brevity" is FORBIDDEN. "Not extracted" is only for genuinely empty arrays.

## Canonical Priority (Mandatory)

If instructions conflict, resolve by priority:
1. `skill/core.md`
2. `skill/references/section-specs.md`
3. `skill/references/audit-patterns.md`
4. `skill/references/cpi-rules.md`
5. `skill/examples/*` (examples are non-authoritative)

## Hard Rules

1. Follow execution steps in order and do not skip checks.
2. Stop if prerequisites fail or required files are missing.
3. Every claim must map to a field from:
   - `.rust-recon/scope.json`
   - `.rust-recon/global_facts.json` + `.rust-recon/facts/index.json` + `.rust-recon/facts/*.json` (PRIMARY split facts source)
   - `.rust-recon/summary.json` (SECONDARY — aggregated views)
4. If a JSON array is empty, write exactly:
   - `Not extracted - verify manually.`
5. NEVER write `Not extracted` when data exists in the JSON.
6. Do not invent sections, headings, or table schemas.
7. Do not use `Risk` or `Severity` columns in Section 2 tables.
8. Do not use red/yellow/blue indicator emoji in findings.
9. Diagrams in Section 4 must be ASCII only.
10. Do not generate report text using Python, shell templating, or custom scripts.
11. Keep the skill directory immutable during a run (no helper generators).
12. Use a strict two-pass flow: extraction validation first, report synthesis second.
13. Before report writing, emit checklist and evidence checkpoints with EXACT COUNTS.
14. If required schema is missing, fail the run and do not output a partial report.
15. Before final output, include command transcript summary and no-shortcut declaration.
16. NEVER omit instructions. NEVER truncate the report.

## Step 0 - Prerequisites

Confirm all of the following before running extraction:
1. In Anchor workspace root
2. `Anchor.toml` exists
3. `rustc --version` succeeds

If `Anchor.toml` is missing, stop and return:
"This does not appear to be an Anchor workspace. Navigate to the project root and try again."

## Step 1 - Install rust-recon (if needed)

Check:
```bash
rust-recon --help
```

If missing:
```bash
export TARGET_DIR=~/.rust-recon_tool
if [ ! -d "$TARGET_DIR" ]; then
  git clone https://github.com/NVN404/rust-recon.git "$TARGET_DIR"
else
  cd "$TARGET_DIR" && git pull
fi
cd "$TARGET_DIR"
cargo install --path cli
rust-recon --help
```

Stop on install failure.

## Step 2 - Generate Data

From project root:
```bash
rust-recon scope
rust-recon facts
```

Required outputs:
- `.rust-recon/scope.json`
- `.rust-recon/global_facts.json`
- `.rust-recon/facts/index.json`
- `.rust-recon/summary.json`

Instruction-level outputs:
- Every file listed in `.rust-recon/facts/index.json`

Compatibility fallback:
- `.rust-recon/facts.json` (legacy monolithic format)

If any are missing, stop and report exact file(s).

Note: `rust-recon facts` automatically deploys skill configs (CLAUDE.md, .claude/rust-recon/SKILL.md, .claude/commands/recon.md alias, .cursorrules) into the project. If configs are missing, run:
```bash
rust-recon setup
```

## Step 3 - Read Context in Exact Order

Read in this sequence:
1. `~/.rust-recon-skill/skill/core.md`
2. `~/.rust-recon-skill/skill/references/facts-schema.md`
3. `~/.rust-recon-skill/skill/references/section-specs.md`
4. `~/.rust-recon-skill/skill/references/audit-patterns.md`
5. `~/.rust-recon-skill/skill/references/cpi-rules.md`
6. `.rust-recon/scope.json`
7. `.rust-recon/global_facts.json`
8. `.rust-recon/facts/index.json`
9. Every file listed in `.rust-recon/facts/index.json`, in ascending `order`
10. `.rust-recon/summary.json`

Fallback: If split files are not present, read `.rust-recon/facts.json` completely.

Fallback: If the global path is not available, check if `CLAUDE.md` exists at the project root (deployed by `rust-recon setup`) and read instructions from there.

Do not use examples to infer schema.

## Step 4 - Select Report Mode

- Default: `detailed`
- Optional: `condensed` (only when user explicitly requests)

No third mode is allowed.

## Step 5 - Pass 1 Extraction Validation (Fail Closed)

Before drafting any report content, print PASS/FAIL for:
1. Prerequisites complete
2. Tool availability complete
3. `scope` and `facts` commands ran
4. Required JSON files exist
5. Required files read in exact order
6. Split facts fully consumed (or legacy facts.json fully consumed)

Also print evidence checkpoints:
1. Ordered command list with purpose
2. Ordered file-read list (`global_facts.json`, `facts/index.json`, and each instruction fact file; or legacy `facts.json`)
3. Active schema source (`skill/core.md` and `skill/references/section-specs.md`)

Also print extraction counts from extracted facts:
```
Instructions in extracted facts: N
Total params: N
Total accounts: N
Data structs: N
Error codes: N
Parser flags: N
```

If any gate fails, stop and report the failure reason.

## Step 6 - Pass 2 Report Synthesis

Write `recon.md` in project root with the exact 1-9 section order defined in `skill/core.md`.

Section 2 is mandatory per instruction with 2a through 2f in order.
ALL instructions must be present. NO omissions.

Generate `recon.md` only after Step 5 passes.

## Step 7 - Quality Gate (Fail Closed)

Before final output, all checks must pass:
1. Sections 1-9 exist in exact order.
2. Every instruction includes 2a, 2b, 2c, 2d, 2e, 2f.
3. Section 2a header is exactly: `Param | Type | Notes`
4. Section 2b header is exactly:
   `Account | Type | Mut | Signer | Unchecked | Constraint Summary`
5. Section 2e header is exactly: `Op | Style | Expression | Impact`
6. No forbidden columns in Section 2 (`Risk`, `Severity`).
7. Section 4 diagrams are ASCII with directional flow.
8. Section 8 checklist has one item per line.
9. Placeholder text is not used as bulk filler where evidence exists.
10. Any `Not extracted - verify manually.` line corresponds to a genuinely empty JSON array.
11. **Instruction count in report == instruction count in extracted facts.**
12. **No "omitted for brevity" or similar truncation.**
13. **Error count in Section 6 == errors[] count in extracted facts.**

If any check fails, regenerate only failed sections and re-run gate.

## Step 8 - Output Attestation (Required)

Before returning results, include:
1. Command transcript summary (every command run, in order, with purpose).
2. Explicit declaration: `No shortcut report generator was used.`
3. Reviewer note confirming skill compliance, not just completeness.
4. Count verification: `Instructions: N/N. Errors: N/N. Data structs: N/N.`
