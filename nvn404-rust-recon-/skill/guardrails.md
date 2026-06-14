# Execution Guardrails

These guardrails are STRICT constraints for any AI agent or LLM generating the `recon.md` report from extracted facts output by the rust-recon tool.

<critical_directives>
1. YOU ARE FORBIDDEN FROM WRITING PYTHON, BASH, OR NODE SCRIPTS TO PARSE JSON.
2. YOU MUST USE YOUR NATIVE FILE-READING TOOLS.
3. YOU MUST OUTPUT THE REPORT DIRECTLY USING NATIVE REASONING.
</critical_directives>

Before report synthesis, output this exact line:
"I am beginning a native reasoning pass over facts.json. I will not use temporary scripts. I will ensure zero data loss."

## HARD CONSTRAINTS (Non-negotiable)

### 1. Complete Extracted Facts Consumption (ZERO DATA LOSS)
- Split facts are the PRIMARY data source for Sections 2-9:
  - `.rust-recon/global_facts.json`
  - `.rust-recon/facts/index.json`
  - Every per-instruction file listed in the index
- Fallback compatibility source: `.rust-recon/facts.json`.
- You MUST read and process EVERY instruction object from extracted facts.
- You MUST read and process EVERY field within each instruction: `params[]`, `accounts[]`, `body_checks[]`, `arithmetic[]`, `execution_steps[]`, `state_mutations[]`, `sol_flows[]`, `token_flows[]`, `set_authority_calls[]`, `events_emitted[]`, `cpi_calls[]`, `error_codes_referenced[]`, `uses_remaining_accounts`.
- You MUST read and process `data_structs[]`, `errors[]`, and `flags[]` at the program level.
- NEVER skip, summarize, or abbreviate any instruction or field that exists in extracted facts.

### 2. NEVER Omit Instructions
- If extracted facts contain N instructions, the report MUST contain exactly N instruction subsections in Section 2.
- Phrases like "omitted for brevity", "remaining instructions follow same pattern", or "see source" are FORBIDDEN.
- Every single instruction gets full 2a-2f treatment. No exceptions.

### 3. No Temporary Files
- Do NOT create any intermediate files whatsoever.
- **Banned file patterns:**
  - `*_dump` (e.g., `ix_dump`, `program_dump`)
  - `*_brief` (e.g., `ix_brief`)
  - `*_extract`
  - `content.txt`
  - Any `.txt`, `.json`, or `.md` file except the final `recon.md`
- If you need to shape data, do it in-memory. Do not write scratch files to disk.

### 4. No Script-Based Generation
- Do not use Python, shell templating, or custom scripts to generate any part of the report.
- Use only direct reasoning over the extracted JSON files.

### 5. Direct Report Output
- Read extracted facts → Extract ALL data → Write complete `recon.md`.
- Report must be fully detailed (9 sections, ALL instructions, 2a-2f subsections, ASCII diagrams, checklists).

---

## ZERO-LOSS Rules

These rules exist because detail loss is the #1 failure mode:

1. If `params[]` has entries → every param MUST appear in the 2a table. Writing "Not extracted" when params exist is a CRITICAL failure.
2. If `accounts[]` has entries → every account MUST appear in the 2b table with all columns filled from the JSON fields.
3. If `execution_steps[]` has entries → every step MUST appear in 2c. Writing "Not extracted" when steps exist is a CRITICAL failure.
4. If `state_mutations[]` has entries → every mutation MUST appear in 2d.
5. If `arithmetic[]` has entries → every operation MUST appear in 2e.
6. If `errors[]` has entries → every error MUST appear in Section 6 with code, name, message, and cross-referenced instructions.
7. If `flags[]` has entries → every flag MUST appear in Section 7.
8. If `data_structs[]` has entries → every struct with all fields MUST appear in Section 3.

`Not extracted - verify manually.` is ONLY permitted when the corresponding JSON array is genuinely empty or the field is absent.

---

## Quality Requirements
- Zero loss of detail from extracted facts.
- All instructions with full subsections (2a-2f).
- Readable, clean formatting without jumbling or truncation.
- All ASCII diagrams intact and properly formatted according to schema.
- Architecture checklists complete and correct.
- Audit patterns and CPI rules applied correctly.
- format the lines properly . dont add next line on the same line of the previous line for checklists and etc .

## Fallback
- If extraction fails or extracted facts cannot be read, STOP. Do not output a partial report. Ask the human operator for direction.
