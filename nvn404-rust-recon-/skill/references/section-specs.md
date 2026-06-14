# Section Specs (v3.1, Zero-Loss Recon)

This file defines the exact report contract.

If this file conflicts with another reference, follow `skill/core.md`.

## Global Rules

1. Use only extracted facts from `.rust-recon/*.json`.
2. No custom section names beyond the 1-9 contract.
3. `Not extracted - verify manually.` is ONLY permitted when the corresponding JSON array is genuinely empty or absent.
4. NEVER write `Not extracted` when data exists. This is a CRITICAL failure.
5. Use neutral recon language.
6. Do not use red/yellow/blue indicator emoji.
7. In Section 2 tables, never use `Risk` or `Severity` columns.
8. Use ASCII-only diagrams in Section 4.
9. NEVER omit instructions. Every instruction in facts.json gets full 2a-2f.
10. NEVER write "omitted for brevity" or similar truncation.


## Report Modes

### Detailed (default)
- Full Section 2a-2f per instruction.
- Complete Section 3 through Section 9.

### Condensed (only on explicit user request)
- Section 2 as a single summary table plus short notes.
- Sections 3-9 still required.

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

---

## 1. Protocol Overview

Sources:
- `.rust-recon/scope.json`
- `.rust-recon/facts.json`
- `.rust-recon/summary.json`

Required content:
1. One inferred purpose paragraph labeled as inference.
2. Program inventory table:

| Program Name | Program ID | Role |
|---|---|---|

3. Exact counts summary:
   - instructions
   - context structs
   - data structs
   - CPI calls
   - error codes
   - parser flags
4. External dependency list inferred from account wrappers and CPI targets.

---

## 2. Instruction Surface

Source: `facts.json` → `instructions[]` array.
EVERY object in `instructions[]` MUST produce a full 2.N subsection with 2a-2f.
If facts.json has 14 instructions, Section 2 has exactly 14 subsections. NO EXCEPTIONS.

Detailed mode: every instruction must include 2a through 2f in order.

### Instruction Header (required)

```text
---
### 2.N - instruction_name
Context: ContextStructName | Signers: N | Accounts: N | Flags: N
---
```

### 2a - Parameter Table

Source: `instructions[N].params[]` — each entry has `name`, `type`, `overflow_risk`.
Every param in the array MUST appear as a row. If params[] is empty, write `No parameters.`

If parameters exist, use exactly this header:

| Param | Type | Notes |
|---|---|---|

Notes guidance:
- Numeric scalar (`u64`, `i64`, `u128`): `numeric input`
- Boolean: `boolean switch`
- Pubkey: `address input`
- Struct/enum: `structured payload`
- Bytes/vector/string: `variable-size input`

If none:
- `No parameters.`

### 2b - Account Table

Source: `instructions[N].accounts[]` — each entry has `name`, `wrapper_type`, `inner_type`, `is_mut`, `is_signer`, `unchecked`, `has_one[]`, `close_target`, `constraints[]`, `attributes`.
Every account in the array MUST appear as a row. Map fields as follows:
- `Account` ← `name`
- `Type` ← `wrapper_type` (+ `inner_type` if present, e.g. `Account<MissionxState>`)
- `Mut` ← `Yes` if `is_mut` is true
- `Signer` ← `Yes` if `is_signer` is true
- `Unchecked` ← `Yes` if `unchecked` is true
- `Constraint Summary` ← derive from `constraints[]`, `has_one[]`, `close_target`

Use exactly this header:

| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|:---:|:---:|:---:|---|

Rules:
1. `Type`: strip lifetimes and keep readable wrapper.
2. `Mut`: `Yes` if mutable, otherwise `No`.
3. `Signer`: `Yes` if signer wrapper or signer flag, otherwise `No`.
4. `Unchecked`: `Yes` for `AccountInfo` or `UncheckedAccount`, otherwise `No`.
5. `Constraint Summary`: short, key-only summary (seeds, has_one, address, init).

### 2c. Execution Flow

Source: `execution_steps[]` from facts.json — ordered list of extracted AST nodes.
Every step is traceable to a specific statement in the function body.

Format each step as:
  `N. [KIND] expression → assigned_to (if any)`

Kinds:
  [LET]    — variable binding
  [ASSIGN] — field mutation  
  [CPI]    — cross-program invocation
  [SOL]    — direct lamport transfer
  [AUTH]   — set_authority call
  [CHECK]  — require! check
  [EMIT]   — event emission
  [IF]     — conditional branch

If execution_steps[] is empty:
> Execution order not extracted. Verify manually in source.

RULE: Never infer or fill steps that are not in execution_steps[].
If a step is NOT_EXTRACTED, write it as:
> Step N: NOT_EXTRACTED — verify in source

### 2d. Data Mutations

Source: `state_mutations[]`, `sol_flows[]`, `token_flows[]`, `set_authority_calls[]`
Only list mutations that appear in these arrays.
Never infer mutations from account names or instruction semantics.

Format:

**State Changes:**
| Account | Field | Operation | Value Expression |
|---|---|---|---|
(from state_mutations[])

**SOL Flows:**
| From | To | Amount | Method |
|---|---|---|---|
(from sol_flows[])

**Token Flows:**
| From | To | Amount | Method |
|---|---|---|---|
(from token_flows[])

**Authority Changes:**
| Account | Authority Type | New Authority | Note |
|---|---|---|---|
(from set_authority_calls[])

If any array is empty:
> [ArrayName] not extracted — verify in source.

RULE: Every row must come from facts.json. Zero inference permitted.

### 2e - Arithmetic Analysis

If arithmetic exists, use exactly this header:

| Op | Style | Expression | Impact |
|---|---|---|---|

Rules:
1. `Style`: `checked`, `unchecked`, `wrapping`, or `saturating`.
2. `Expression`: concise expression, keep meaningful operands.
3. `Impact`: concrete state impact if operation fails or wraps.

If none and numeric params exist:
- `No extracted arithmetic. verify checked arithmetic in source.`

If none and no numeric path:
- `No arithmetic operations.`

### 2f - Recon Notes (Condensed)

Use at most 4 bullets per instruction.
Use one of these prefixes only:
- `[fact]`
- `[check]`
- `[gap]`

Rules:
1. Notes must be instruction-specific.
2. Avoid generic text.
3. Do not use severity grading icons.

---

## 3. Account and PDA Catalogue

### 3a - Account Structs

For each `data_structs[]` entry:

| Field | Type | Tag | Notes |
|---|---|---|---|

Tag set:
- `[STORED_BUMP]`
- `[AUTHORITY]`
- `[NUMERIC]`
- `[TIMESTAMP]`
- `[PAUSE_FLAG]`
- `[PUBKEY]`
- `[ACCOUNTING]`

After each struct include:
1. `Used by instructions:`
2. `Re-init safety:`
3. `Authority chain:`

### 3b - PDA Catalogue

| PDA Name | Seeds (verbatim) | Bump Storage Field | Derived In |
|---|---|---|---|

Then add concise PDA integrity notes.

---

## 4. Authority and Trust Model

ASCII diagrams only. No Mermaid.

### 4a - Authority Graph
Requirements:
1. At least 3 boxed nodes.
2. At least 4 directional edges.
3. At least 2 hierarchy levels.

### 4b - Instruction Flow
Requirements:
1. Setup, execution, completion phases.
2. Directional phase transitions.
3. At least one loop or repeat path where applicable.

### 4c - Account Dependency Diagram
Requirements:
1. Seed source nodes.
2. PDA derivation nodes.
3. Constraint links (`has_one`, address equality, authority links).

### 4d - Trust Assumption Table

| Role | Controls | Assumed Honest | Escalation Path | Observation |
|---|---|---|---|---|

---

## 5. Token and CPI Flows

### 5a - Token Account Flow Table

| Account Name | Mint | Authority | Balance Role | Instructions | Flow |
|---|---|---|---|---|---|

### 5b - CPI Call Map

List explicit CPI calls and likely implicit token operations when extraction is incomplete.

If CPIs appear incomplete, add a concise limitation note with required manual checks.

### 5c - Token-2022 Compatibility

If Token-2022 indicators appear, note extension-sensitive checks:
- transfer method compatibility
- fee-on-transfer accounting implications

---

## 6. Error Code Registry

Source: `facts.json` → `errors[]` — each entry has `code` and `msg`.
Every error in the array MUST appear as a row. Cross-reference with `instructions[N].error_codes_referenced[]`.
If errors[] has 24 entries, this table MUST have 24 rows.

| Code | Name | Message | Referenced By |
|---|---|---|---|

Then add a short coverage comment:
- missing coverage areas
- inconsistent error mapping

---

## 7. Recon Signals Summary

Derive rows from `flags[]`, `body_checks[]`, `accounts[]`, and `arithmetic[]`.

Use this exact table:

| # | Location | Signal | Evidence | Required Check | Source |
|---|---|---|---|---|---|

Rules:
1. Do not include a severity column.
2. Keep rows concise and factual.
3. Merge duplicate signals by location + signal.
4. If no signals, state `No recon signals extracted.`

---

## 8. Manual Verification Checklist

One checklist item per line.
Use grouped sections in this exact order:
1. Missing body checks
2. Unchecked account wrappers
3. Arithmetic validation
4. Struct field and state assumptions
5. CPI target and signer seed checks

Checklist format:

```text
[ ] instruction_name: specific manual verification task
```

---

## 9. Recon Metadata

Provide deterministic counts only:
- instructions analyzed
- context structs modeled
- account structs catalogued
- PDA entries
- CPI calls traced
- error codes indexed
- checklist items generated

Do not estimate. No approximations.
