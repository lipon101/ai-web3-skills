## CPI Rules (v3, Recon Flow)

This file defines Section 5 behavior for explicit and implicit CPI coverage.

## 5b - CPI Call Map

Show instruction-to-program CPI relationships using readable tables or ASCII flow blocks.

Recommended tabular shape:

```text
Instruction        | Target Program    | Method                          | Signer Seeds
-------------------|-------------------|----------------------------------|-------------
initialize_pool    | System Program    | create_account                  | none
stake              | Token Program     | token::transfer                 | none
withdraw_fees      | Token Program     | token::transfer_checked         | pool PDA
```

For each entry, add a short note only when needed:
1. Target program is externally configured.
2. Signer seeds derive from mutable state.
3. Account routing includes remaining accounts.

## CPI Extraction Limitation (Required Note When Applicable)

If `cpi_calls[]` appears empty or incomplete, do not assume no CPIs.

Known blind spots include:
1. Conditional branches (`if`, `match`)
2. Loop-driven calls
3. Helper-function indirection

When token movement is evident but explicit CPI extraction is missing, name likely operations explicitly:
- `token::transfer`
- `token::transfer_checked`
- `token_2022::transfer_checked`

Avoid vague terms like `implicit SPL`.

Use this limitation note template:

```text
Known limitation: extractor reported N explicit CPI calls, but token flow paths suggest
additional transfer operations in conditional or helper code paths.

Manual verification:
- Search for token::transfer and transfer_checked variants
- Confirm signer seeds do not use attacker-controlled mutable fields
- Confirm CPI target program addresses are validated
```

## 5c - Token-2022 Handling

If Token-2022 appears in CPI targets or account program fields:
1. Record extension-sensitive behavior relevant to accounting.
2. Confirm transfer method compatibility (`transfer_checked` variants).
3. Verify received amount assumptions when transfer fees may apply.

