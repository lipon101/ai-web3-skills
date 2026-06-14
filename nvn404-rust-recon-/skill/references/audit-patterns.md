## Audit Patterns (v3, Recon Notes)

This file defines mechanical checks for Section 2f and Section 3a.

Use concise recon notes with prefixes from section-specs:
- `[fact]`
- `[check]`
- `[gap]`

Do not use severity icons.

## Section 2f - Recon Notes (Mechanical Rules)

For each instruction, evaluate the checks below and emit only applicable bullets.

### Close Target Cross-Check (required)

For every account with `close_target != null`:
1. Confirm `attributes` includes `close = <target>`.
2. Verify instruction behavior actually performs closure.
3. If `close_target` exists but behavior does not close, emit:

`[gap] close_target declared for <account> but closure behavior is not evident; verify parser output and source logic.`

### Conditional Recon Notes

Emit a note when condition is true:

1. `attributes` contains `init_if_needed`
  - `[check] init_if_needed present on <account>; verify all state fields are reinitialized on re-entry.`

2. `unchecked == true`
  - `[gap] <account> uses <wrapper_type>; verify owner/type/address constraints in macro or body.`

3. `uses_remaining_accounts == true`
  - `[gap] remaining_accounts is used; verify account filtering and program-owner checks before CPI/state writes.`

4. `body_checks[]` is empty and (`mut` account exists or CPI exists)
  - `[check] no extracted body checks; confirm invariants are fully enforced by account constraints or explicit guards.`

5. Param has `overflow_risk: true` and matching arithmetic is `unchecked`
  - `[gap] unchecked arithmetic path for numeric input <param>; verify checked/saturating math on this state transition.`

6. CPI target appears non-standard for protocol flow
  - `[check] CPI to <program>; confirm target address is fixed/validated and not caller-controlled.`

7. Mutable account relies on `has_one` but instruction has no signer on controlling role
  - `[check] mutation trust chain depends on has_one mapping; verify mapped authority field is immutable after initialization.`

8. `init` payer is not an obvious signer in instruction context
  - `[check] init payer differs from expected signer; verify payer cannot be redirected by user input.`

## Section 3a - Field-Level Analysis Rules

Every struct in `data_structs[]` must include a full field table.

If extraction is incomplete, write exactly:
- `Not extracted - verify manually.`

### Tagging Rules (apply all matches)

1. Field name `bump` -> `[STORED_BUMP]`
2. Name contains `admin|owner|authority|signer|key` -> `[AUTHORITY]`
3. Numeric field (`u64|u128|i64`) with name containing `amount|balance|total|reserve|reward|fee|shares|stake|deposit` -> `[NUMERIC]`
4. Time-like field (`i64|u64`) with `timestamp|slot|epoch` in name -> `[TIMESTAMP]`
5. Bool field with `paused|frozen|active|enabled` in name -> `[PAUSE_FLAG]`
6. `Pubkey` field not clearly immutable seed component -> `[PUBKEY]`
7. Name contains `debt|accrued|pending|claimable` -> `[ACCOUNTING]`

### Post-Table Required Lines

After each struct table include:
1. `Used by instructions:` list relevant instructions.
2. `Re-init safety:` `PASS` or `FAIL` with one concrete sentence.
3. `Authority chain:` who can mutate and through which instructions.

