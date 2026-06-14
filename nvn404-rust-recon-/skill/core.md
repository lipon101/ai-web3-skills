# rust-recon Core Rules (v3.1, Zero-Loss Recon)

This file is the canonical authority for report behavior.

If any instruction conflicts across files, use this precedence:
1. `skill/core.md`
2. `skill/guardrails.md`
3. `skill/references/section-specs.md`
4. `skill/references/audit-patterns.md`
4. `skill/references/cpi-rules.md`
5. `skill/examples/*` (examples are non-authoritative)

## Purpose

Generate deterministic, COMPLETE protocol reconnaissance reports from extracted facts.

This is a recon workflow, not a vulnerability rating workflow.

<critical_directives>
1. YOU ARE FORBIDDEN FROM WRITING PYTHON, BASH, OR NODE SCRIPTS TO PARSE JSON.
2. YOU MUST USE YOUR NATIVE FILE-READING TOOLS.
3. YOU MUST OUTPUT THE REPORT DIRECTLY USING NATIVE REASONING.
</critical_directives>

Before report synthesis, output this exact line:
"I am beginning a native reasoning pass over facts.json. I will not use temporary scripts. I will ensure zero data loss."

## ABSOLUTE RULE: ZERO DATA LOSS

The single most important rule in this entire skill:

**Every piece of data present in extracted facts MUST appear in the final report.**

- If extracted facts have 14 instructions, the report has 14 instruction sections.
- If an instruction has 9 accounts, all 9 appear in the 2b table.
- If an instruction has 5 params, all 5 appear in the 2a table.
- If there are 24 error codes, all 24 appear in Section 6.
- NO summarizing. NO "omitted for brevity." NO "see above pattern."

Violation of this rule makes the entire report worthless.

## Hard Rules

1. Follow workflow steps in order. Do not skip steps.
2. Stop immediately if prerequisites or generated files are missing.
3. Every claim must be traceable to one of these files:
   - `.rust-recon/scope.json`
   - `.rust-recon/global_facts.json` + `.rust-recon/facts/index.json` + `.rust-recon/facts/*.json` (PRIMARY split facts source)
   - `.rust-recon/summary.json` (SECONDARY source — aggregated views only)
   - Fallback compatibility source: `.rust-recon/facts.json`
4. If a JSON field is missing or its array is empty, write exactly:
   - `Not extracted - verify manually.`
5. NEVER write `Not extracted` when the data IS present in extracted facts.
6. Do not invent sections, table schemas, or column names.
7. In Section 2 tables, never use a `Risk` column or a `Severity` column.
8. Keep observations concise and evidence-based.
9. Do not use red/yellow/blue indicator emoji in findings.
10. Do not output Mermaid. Section 4 diagrams must be ASCII only.
11. If quality checks fail, regenerate before final output.
12. Do not use Python, shell templating, or custom scripts to generate recon report text.
13. Use only this skill workflow plus direct reasoning over extracted files.
14. Keep the skill directory immutable during a run; do not add helper scripts or ad-hoc generators.
15. Before report writing, produce a pass/fail pre-execution checklist.
16. Before report writing, print evidence checkpoints: exact command log, exact files read in order, and section schema source.
17. Use a mandatory two-pass flow: Pass 1 extraction validation, then Pass 2 report synthesis.
18. If forbidden placeholder patterns appear in core sections, stop and regenerate.
19. If any required section, subsection, or table header is missing, fail the run.
20. Before final output, provide an explicit no-shortcut declaration.

## Extracted Facts Field Consumption Checklist

During Pass 1, verify these fields exist and note their counts. During Pass 2, every non-empty field MUST produce report content:

### Program-level fields:
- `program` → Section 1 program name
- `program_id` → Section 1 program ID
- `instructions[]` → Section 2 (one subsection per entry, NO OMISSIONS)
- `data_structs[]` → Section 3a (one table per struct)
- `errors[]` → Section 6 (one row per error)
- `flags[]` → Section 7 (one row per flag)

### Per-instruction fields (for EVERY instruction):
- `name` → Section 2.N header
- `context` → Section 2.N header
- `params[]` → Section 2a table rows
- `accounts[]` → Section 2b table rows (use `wrapper_type`, `inner_type`, `is_mut`, `is_signer`, `unchecked`, `has_one[]`, `close_target`, `constraints`)
- `execution_steps[]` → Section 2c ordered list
- `body_checks[]` → Section 2c/2d validation entries
- `state_mutations[]` → Section 2d State Changes table
- `sol_flows[]` → Section 2d SOL Flows table
- `token_flows[]` → Section 2d Token Flows table
- `set_authority_calls[]` → Section 2d Authority Changes table
- `arithmetic[]` → Section 2e table rows
- `cpi_calls[]` → Section 5 and Section 2d/2f cross-references
- `events_emitted[]` → Section 2f notes
- `uses_remaining_accounts` → Section 2f/7/8 flag
- `error_codes_referenced[]` → Section 6 cross-reference

## Workflow (Strict Order)

0. Validate Anchor workspace and toolchain.
1. Ensure `rust-recon` binary is available.
2. Run `rust-recon scope` and `rust-recon facts`.
3. Verify split output files exist: `scope.json`, `global_facts.json`, `facts/index.json`, per-instruction files from the index, and `summary.json`.
   - Fallback compatibility: accept `facts.json` only if split files are not present.
4. Read rules and facts in required order.
5. Execute Pass 1 extraction validation gates.
6. Generate `recon.md` with exact section order (Pass 2 only after Pass 1 passes). You MUST generate ALL 9 sections exactly as defined in `section-specs.md`. DO NOT STOP EARLY. A report with fewer than 9 sections is a catastrophic failure.
7. Run quality gate and regenerate failed sections.
8. Run `rust-recon clean` to clean up the workspace (or manually run `rm -rf .rust-recon` if the command fails). The workspace MUST be cleaned before finishing.
9. Emit command transcript summary and no-shortcut declaration.

## Pre-Execution Checklist (Required)

Before any report text is drafted, print this checklist with PASS or FAIL:
1. Prerequisites check complete (`Anchor.toml`, `rustc --version`).
2. Tool availability check complete (`rust-recon --help`).
3. Extraction commands ran (`rust-recon scope`, `rust-recon facts`).
4. Required output files exist (`scope.json`, `global_facts.json`, `facts/index.json`, per-instruction files, `summary.json`; or fallback `facts.json`).
5. Required files were read in the mandated order.
6. Extracted instruction count: N (MUST match Section 2 instruction count).
7. Extracted error count: N (MUST match Section 6 row count).
8. Extracted data_structs count: N (MUST match Section 3a struct count).
9. Extracted flags count: N (MUST match Section 7 row count).

If any item fails, stop and report failure reason. Do not draft the report.

## Evidence Checkpoints (Required)

Before report synthesis, print:
1. `Commands run (ordered):` command plus short purpose.
2. `Files read (ordered):` exact file paths — include `global_facts.json`, `facts/index.json`, and every per-instruction file (or fallback `facts.json`).
3. `Schema source:` `~/.rust-recon-skill/skill/core.md` and `~/.rust-recon-skill/skill/references/section-specs.md` (or `CLAUDE.md` if global path unavailable).
4. `Instruction count from extracted facts:` exact number.
5. `Error count from extracted facts:` exact number.

If this evidence block is missing, the run is invalid.

## Pass Model (Mandatory)

Pass 1: Extraction Validation
1. Validate checklist and evidence checkpoints.
2. Confirm required JSON fields are present for all mandatory sections.
3. Print exact counts: instructions, params per instruction, accounts per instruction, errors, data_structs, flags.
4. Approve or fail with explicit reason.

Pass 2: Report Synthesis
1. Start only after Pass 1 is approved.
2. Generate report with strict section and table schemas.
3. EVERY instruction from extracted facts gets full 2a-2f treatment.
4. Run quality gate.

Do not merge both passes into a single unchecked generation step.

## Report Modes

- Default mode: `detailed`
- Optional mode: `condensed` (only when explicitly requested)

## Section Order (Mandatory)

1. Protocol Overview
2. Instruction Surface
3. Account and PDA Catalogue
4. Authority and Trust Model
5. Token and CPI Flows
6. Error Code Registry
7. Recon Signals Summary
8. Manual Verification Checklist
9. Recon Metadata

## Section 2 Non-Negotiables

For EVERY instruction in extracted facts, include 2a through 2f in order.

- 2a: Populate from `params[]`. Table header: `Param | Type | Notes`
- 2b: Populate from `accounts[]`. Table header: `Account | Type | Mut | Signer | Unchecked | Constraint Summary`
- 2c: Populate from `execution_steps[]`. Ordered step list with [KIND] tags.
- 2d: Populate from `state_mutations[]`, `sol_flows[]`, `token_flows[]`, `set_authority_calls[]`.
- 2e: Populate from `arithmetic[]`. Table header: `Op | Style | Expression | Impact`
- 2f: Condensed recon notes using `[fact]`, `[check]`, `[gap]` prefixes.

## Recon Signals Rules (Section 7)

- Use concise signal rows with evidence and required checks.
- Do not include numeric severity labels in table columns.
- If `flags[]` contains severity, treat it as internal parser metadata only.

## Quality Gate (Must Pass)

1. Section order is exactly 1 through 9.
2. Every instruction has 2a, 2b, 2c, 2d, 2e, 2f.
3. Section 2 tables use exact required headers.
4. No `Risk` column in 2a/2b.
5. No red/yellow/blue indicator emoji in findings sections.
6. Section 4 contains ASCII diagrams with directional flow.
7. Checklist section uses one item per line.
8. **Instruction count in report matches instruction count in extracted facts.**
9. **Error count in Section 6 matches error count in extracted facts.**
10. **No "omitted for brevity" or similar truncation phrases anywhere.**
11. Core sections are not filled with repeated placeholder-only text.
12. If placeholder text appears, it must correspond to truly missing (empty array) extracted data.
13. Did I generate all 9 sections? (If no, regenerate the missing sections before outputting).
14. Command transcript summary is present.
15. Explicit declaration is present: `No shortcut report generator was used.`

## Forbidden Pattern Gate

Stop and regenerate if ANY condition is true:
1. Repeated `Not extracted - verify manually.` appears across core sections while the corresponding JSON array is non-empty.
2. Large placeholder blocks replace required tables where data is present.
3. Any instruction from extracted facts is missing from Section 2.
4. Any phrase like "omitted for brevity" or "remaining instructions follow same pattern" appears.
5. Section 6 says "Not extracted" but `errors[]` in extracted facts is non-empty.


## Mandatory Preflight Commit (Required Before Section 1)

Before writing a single word of the report, output this exact block:

PREFLIGHT COMMIT:
- Instructions found: [exact number from facts/index.json]
- Errors found: [exact number from errors[]]
- Data structs found: [exact number]
- I will write exactly [N] instruction subsections (2.1 through 2.N).
- If any subsection is missing, the report is a failure.

Do not begin Section 1 until this block is printed.


ANTI-LAZY REMINDER: "Context: Unknown" and "Not extracted" are only permitted 
when the JSON array is genuinely empty. If you write these for a non-empty array, 
stop and rewrite that section immediately before continuing.

This gate is fail-closed.
