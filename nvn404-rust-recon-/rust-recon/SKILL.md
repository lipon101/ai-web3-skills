---
name: rust-recon
description: Solana Anchor protocol reconnaissance - generates detailed recon reports from extracted facts
---

# rust-recon Orchestrator (Strict, Zero-Loss Recon)

This command is the only execution path for generating `recon.md`.
Once triggered, execution is non-interactive: do not ask for confirmation to write the report or run cleanup.

<critical_directives>
1. YOU ARE FORBIDDEN FROM WRITING PYTHON, BASH, OR NODE SCRIPTS TO PARSE JSON.
2. YOU MUST USE YOUR NATIVE FILE-READING TOOLS.
3. YOU MUST OUTPUT THE REPORT DIRECTLY USING NATIVE REASONING.
</critical_directives>

## Source Priority (Mandatory)

If guidance conflicts, resolve in this order:
1. `skill/core.md`
2. `skill/references/section-specs.md`
3. `skill/references/audit-patterns.md`
4. `skill/references/cpi-rules.md`
5. `skill/examples/*` (non-authoritative)

Do not invent formatting outside these rules.

## CRITICAL: Zero Data Loss

Before anything else, internalize this:
- EVERY instruction in extracted facts -> full 2a-2f subsection in the report.
- EVERY param in params[] -> row in 2a table.
- EVERY account in accounts[] -> row in 2b table.
- EVERY error in errors[] -> row in Section 6.
- NEVER write "omitted for brevity." NEVER skip an instruction.
- NEVER write "Not extracted" when data EXISTS in the JSON.

## Execution Guardrails (Non-Negotiable)

1. Do not use Python, shell templating, or custom scripts to generate recon report text.
2. Do not create helper generators in the skill directory during a run.
3. Use a strict two-pass flow:
    - Pass 1: extraction validation (with exact counts)
    - Pass 2: report synthesis (consuming ALL data)
4. Before Pass 2, print checklist PASS/FAIL and evidence checkpoints with counts.
5. If any required section, subsection, or table header is missing, fail the run.
6. If placeholder-only text appears where extracted data exists, stop and regenerate.
7. Before final output, include command transcript summary and explicit no-shortcut declaration.
8. Do not stop after extraction; report writing and cleanup are mandatory completion steps.

## Mandatory Cognitive Forcing Step

Before starting Pass 1, output this exact string:
"I am beginning a native reasoning pass over facts.json. I will not use temporary scripts. I will ensure zero data loss."

## Step 0 - Prerequisites Check

Before anything else, confirm:
1. You are in a Solana Anchor project directory.
2. `Anchor.toml` exists at workspace root.
3. Rust toolchain is available (`rustc --version`).

If `Anchor.toml` is missing, stop and return:
"This does not appear to be an Anchor workspace. Navigate to the project root and try again."

## Step 1 - Ensure rust-recon Binary

Check binary first:

```bash
rust-recon --help
```

If missing, install:

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

If install fails, report the exact error and stop.

## Step 2 - Generate Recon Data

From the Anchor project root:

```bash
rust-recon scope
rust-recon facts
```

Required outputs:
- `.rust-recon/scope.json`
- `.rust-recon/global_facts.json`
- `.rust-recon/facts/index.json`
- `.rust-recon/summary.json`

Instruction-level outputs (from index):
- `.rust-recon/facts/NN_instruction-name.json` for every instruction listed in `index.json`

Compatibility output (optional):
- `.rust-recon/facts.json` (legacy monolithic file)

If any file is missing, stop and report exactly which command/file failed.

Note: `rust-recon facts` automatically deploys skill configs into the project. If configs are missing, run:
```bash
rust-recon setup
```

## Step 3 - Read Context in Exact Order

Read these files in this exact sequence before drafting any report text:
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

### Split Facts Reading Requirements

`global_facts.json` + `facts/index.json` + per-instruction files contain ALL data. You MUST:
- Read `global_facts.json` fully for program-level arrays and program_id.
- Read every instruction file listed in `facts/index.json`.
- For each instruction file, process all sub-arrays: `params[]`, `accounts[]`, `body_checks[]`, `arithmetic[]`, `execution_steps[]`, `state_mutations[]`, `sol_flows[]`, `token_flows[]`, `set_authority_calls[]`, `events_emitted[]`, `cpi_calls[]`.
- Process all program-level arrays from `global_facts.json`: `data_structs[]`, `errors[]`, `flags[]`, `accounts[]`, `cpi_calls[]`, `risk_signals[]`.

Fallback compatibility mode:
- If split facts files do not exist, read `.rust-recon/facts.json` completely.

Fallback: If the global path `~/.rust-recon-skill/` is not accessible, read instructions from `CLAUDE.md` at the project root (deployed by `rust-recon setup`).

Important:
- Do not use examples to define schema.
- Examples may be consulted only for diagram readability when needed.

## Step 4 - Choose Format

- If user explicitly says `condensed`, use condensed mode.
- Otherwise default to `detailed`.

No third "standard" mode is allowed.

## Step 5 - Pass 1 Extraction Validation (Required)

Before drafting report content, print PASS/FAIL for:
1. Prerequisites complete
2. Tool availability complete
3. Extraction commands executed
4. Required output files exist
5. Required files read in exact order
6. Split facts fully consumed (or legacy facts.json fully consumed)

Then print evidence checkpoints:
1. Ordered command list with short purpose
2. Ordered list of files read (`global_facts.json`, `facts/index.json`, and all instruction fact files; or legacy `facts.json`)
3. Active schema source (`skill/core.md`, `skill/references/section-specs.md`)

Then print extraction counts from extracted facts:
```
Instructions: N
Total accounts across all instructions: N
Total params across all instructions: N
Data structs: N
Error codes: N
CPI calls: N
Parser flags: N
```

These counts MUST match the final report. If instruction count = 14, Section 2 must have exactly 14 instruction subsections.

If any check fails, stop and report exact failure reason.

## Step 6 - Generate Report (Pass 2 Only)

Write `recon.md` at project root.
Do not prompt the user for permission once this command is triggered.

Mandatory constraints:
- Follow section order 1-9 from `skill/core.md`.
- For EVERY instruction in extracted facts, include subsections 2a-2f in order.
- Section 2a table header must be exactly: `Param | Type | Notes`
- Section 2b table header must be exactly: `Account | Type | Mut | Signer | Unchecked | Constraint Summary`
- Section 2e table header must be exactly: `Op | Style | Expression | Impact`
- No `Risk` or `Severity` column in Section 2 tables.
- No red/yellow/blue indicator emoji in findings sections.
- Diagrams must be ASCII only.
- **NEVER omit instructions. NEVER write "omitted for brevity."**
- **NEVER write "Not extracted" when the corresponding JSON array has data.**

## Step 7 - Quality Gate (Fail Closed)

Before returning output, validate:
1. All 9 sections exist in the required order.
2. Every instruction from extracted facts has all subsections 2a-2f.
3. Table headers exactly match required schema.
4. No forbidden columns (`Risk`, `Severity`) in Section 2 tables.
5. Section 4 diagrams show directional flow (not flat lists).
6. Section 8 checklist has one item per line.
7. Placeholder text is not used as a bulk substitute for extracted content.
8. Any `Not extracted - verify manually.` line corresponds to a genuinely empty JSON array.
9. **Instruction count in report == instruction count from Pass 1.**
10. **No "omitted for brevity" or truncation phrases.**
11. **Error count in Section 6 == errors[] count from extracted facts.**

If any check fails, regenerate the affected section(s) and re-run this gate.

## Step 8 - Output Attestation (Required)

Before final output, provide:
1. Command transcript summary: every command run, in order, with purpose.
2. Explicit declaration: `No shortcut report generator was used.`
3. Reviewer statement: skill-compliant schema check passed.
4. Count verification: `Instructions in report: N/N from extracted facts. Errors in report: N/N from extracted facts.`

## Step 9 - Mandatory Cleanup (Fail Closed)

Immediately after attestation:
1. Run: `rust-recon clean`
2. If it fails, run fallback: `rm -rf .rust-recon`
3. Verify `.rust-recon` does not exist

If cleanup verification fails, return a failure state and include the exact cleanup error. Do not report success.
