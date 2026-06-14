# Zenon Protocol Recon Report - DETAILED

Generated from rust-recon outputs at 2026-04-20T04:26:24.501Z.

Hard rule: every claim below is derived from .rust-recon/scope.json, .rust-recon/facts.json, or .rust-recon/summary.json.

## 1. Protocol Overview

Inferred protocol summary: Based on instruction names, account schemas, and extracted token flow artifacts, Zenon appears to implement a bonding-curve token market with market initialization, curve trading (buy/sell), fee withdrawal, and curve-completion operations controlled by authority roles.

| Program Name | Program ID | Role |
|---|---|---|
| zenon | SLAPUqHm76SGThDr4JUyRDVsGBmxwGkxicWwknkgH5c | Bonding-curve market and token trading program |

Extraction summary:
- Instructions in facts.json: 10
- Unique instruction names: 10
- Context structs referenced by instructions: 8
- Account context structs extracted: 8
- Account data structs extracted: 2
- Explicit CPI calls extracted: 1
- Error codes extracted: 13
- Precomputed security flags: 7
- PDA map entries in summary: 14

External dependency signals (from wrapper types and CPI metadata):
- Program<Token> appears in multiple instruction account sets.
- Program<System> appears in initialization and transfer-related contexts.
- Program<AssociatedToken> appears in ATA and trading contexts.
- Explicit CPI: init_token -> token::mint_to

## 2. Instruction Surface

### 2.1 - `initialize_market`
> Context: `InitializeMarket` | Signers: 1 (payer) | Accounts: 4 | Flags: 0

#### 2.1a Parameters
| Param | Type | Overflow |
|---|---|---|
| version | u16 | No |
| market_data | MarketParams | No |

#### 2.1b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| market | Account<Market> | No | No | No | account (init, payer = payer, space = size_of::< Market > () + 8, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump) |
| payer | Signer | Yes | Yes | No | account (mut) |
| system_program | Program<System> | No | No | No | - |
| rent | Sysvar <  Rent > | No | No | No | - |

#### 2.1c Constraints (verbatim extraction)
```text
market [Account<Market>]
  account (init, payer = payer, space = size_of::< Market > () + 8, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

payer [Signer]
  account (mut)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

rent [Sysvar <  Rent >]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.1d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.1e Arithmetic Analysis
[WARNING] No arithmetic nodes extracted but numeric parameters exist; verify checked add/sub/mul/div in function body.

#### 2.1f Audit Notes
- [INFO] No precomputed flags mapped to this instruction.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (payer).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.2 - `update_market`
> Context: `UpdateMarket` | Signers: 1 (authority) | Accounts: 4 | Flags: 0

#### 2.2a Parameters
| Param | Type | Overflow |
|---|---|---|
| version | u16 | No |
| market_data | MarketParams | No |

#### 2.2b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| market | Account<Market> | Yes | No | No | account (mut, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump) |
| authority | Signer | Yes | Yes | No | account (mut, constraint = market.authority == authority.key ()) |
| system_program | Program<System> | No | No | No | - |
| rent | Sysvar <  Rent > | No | No | No | - |

#### 2.2c Constraints (verbatim extraction)
```text
market [Account<Market>]
  account (mut, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

authority [Signer]
  account (mut, constraint = market.authority == authority.key ())
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

rent [Sysvar <  Rent >]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.2d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.2e Arithmetic Analysis
[WARNING] No arithmetic nodes extracted but numeric parameters exist; verify checked add/sub/mul/div in function body.

#### 2.2f Audit Notes
- [INFO] No precomputed flags mapped to this instruction.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (authority).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.3 - `process_completed_curve`
> Context: `ProcessCompletedCurve` | Signers: 1 (admin) | Accounts: 10 | Flags: 1

#### 2.3a Parameters
| Param | Type | Overflow |
|---|---|---|
| _market_version | u16 | No |

#### 2.3b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| bonding_curve | Account<BondingCurve> | Yes | No | No | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) |
| admin_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = admin ,) |
| bonding_curve_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve ,) |
| market | Account<Market> | No | No | No | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) |
| escape_fee_treasury | AccountInfo | Yes | No | Yes | account (mut, constraint = market.escape_fee_treasury == escape_fee_treasury.key ()) |
| admin | Signer | Yes | Yes | No | account (mut, constraint = market.authority == admin.key () ,) |
| mint | Account<Mint> | No | No | No | - |
| token_program | Program<Token> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| rent | Sysvar <  Rent > | No | No | No | - |

#### 2.3c Constraints (verbatim extraction)
```text
bonding_curve [Account<BondingCurve>]
  account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ())
  has_one: []
  close_target: null

admin_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = admin ,)
  has_one: []
  close_target: null

bonding_curve_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve ,)
  has_one: []
  close_target: null

market [Account<Market>]
  account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

escape_fee_treasury [AccountInfo UNCHECKED]
  account (mut, constraint = market.escape_fee_treasury == escape_fee_treasury.key ())
  has_one: []
  close_target: null

admin [Signer]
  account (mut, constraint = market.authority == admin.key () ,)
  has_one: []
  close_target: null

mint [Account<Mint>]
  (no constraints)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

rent [Sysvar <  Rent >]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.3d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.3e Arithmetic Analysis
| Op | Style | Expression | Risk |
|---|---|---|---|
| sub | checked | bonding_curve.real_token_reserves.checked_sub (market.tokens_fee_amount) | Extractor marked this arithmetic path as checked. |
| sub | checked | bonding_curve.real_sol_reserves.checked_sub (escape_fee_sol_amount) | Extractor marked this arithmetic path as checked. |

#### 2.3f Audit Notes
- [HIGH] escape_fee_treasury is unchecked in process_completed_curve. Constraint coverage: account (mut, constraint = market.escape_fee_treasury == escape_fee_treasury.key ()). Attack path: if an attacker can influence the referenced pubkey source, value transfer or metadata handling may be redirected.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (admin).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.4 - `withdraw_tokens_fee`
> Context: `WithdrawTokensFee` | Signers: 1 (admin) | Accounts: 9 | Flags: 0

#### 2.4a Parameters
| Param | Type | Overflow |
|---|---|---|
| tokens_amount | u64 | Yes |
| market_version | u16 | No |

#### 2.4b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| bonding_curve | Account<BondingCurve> | Yes | No | No | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) |
| market | Account<Market> | No | No | No | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) |
| treasury_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = market.tokens_fee_treasury ,) |
| bonding_curve_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve) |
| admin | Signer | Yes | Yes | No | account (mut, constraint = market.authority == admin.key () ,) |
| mint | Account<Mint> | No | No | No | - |
| token_program | Program<Token> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| rent | Sysvar <  Rent > | No | No | No | - |

#### 2.4c Constraints (verbatim extraction)
```text
bonding_curve [Account<BondingCurve>]
  account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ())
  has_one: []
  close_target: null

market [Account<Market>]
  account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

treasury_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = market.tokens_fee_treasury ,)
  has_one: []
  close_target: null

bonding_curve_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve)
  has_one: []
  close_target: null

admin [Signer]
  account (mut, constraint = market.authority == admin.key () ,)
  has_one: []
  close_target: null

mint [Account<Mint>]
  (no constraints)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

rent [Sysvar <  Rent >]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.4d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.4e Arithmetic Analysis
[WARNING] No arithmetic nodes extracted but numeric parameters exist; verify checked add/sub/mul/div in function body.

#### 2.4f Audit Notes
- [INFO] No precomputed flags mapped to this instruction.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (admin).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.5 - `init_token`
> Context: `InitializeAndMint` | Signers: 1 (payer) | Accounts: 11 | Flags: 1

#### 2.5a Parameters
| Param | Type | Overflow |
|---|---|---|
| params | InitTokenParams | No |

#### 2.5b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| mint | Account<Mint> | No | No | No | account (init, payer = payer, mint::decimals = params.decimals, mint::authority = payer ,) |
| bonding_curve | Account<BondingCurve> | No | No | No | account (init, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, payer = payer, space = size_of::< BondingCurve > () + 8 ,) |
| market | Account<Market> | No | No | No | - |
| payer | Signer | Yes | Yes | No | account (mut) |
| bonding_curve_ata | Account<TokenAccount> | No | No | No | account (init, payer = payer, associated_token::mint = mint, associated_token::authority = bonding_curve ,) |
| metadata | UncheckedAccount | Yes | No | Yes | account (mut) |
| token_program | Program<Token> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| associated_token_program | Program<AssociatedToken> | No | No | No | - |
| rent | Sysvar <  Rent > | No | No | No | - |
| token_metadata_program | Program<Metaplex> | No | No | No | - |

#### 2.5c Constraints (verbatim extraction)
```text
mint [Account<Mint>]
  account (init, payer = payer, mint::decimals = params.decimals, mint::authority = payer ,)
  has_one: []
  close_target: null

bonding_curve [Account<BondingCurve>]
  account (init, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, payer = payer, space = size_of::< BondingCurve > () + 8 ,)
  has_one: []
  close_target: null

market [Account<Market>]
  (no constraints)
  has_one: []
  close_target: null

payer [Signer]
  account (mut)
  has_one: []
  close_target: null

bonding_curve_ata [Account<TokenAccount>]
  account (init, payer = payer, associated_token::mint = mint, associated_token::authority = bonding_curve ,)
  has_one: []
  close_target: null

metadata [UncheckedAccount UNCHECKED]
  account (mut)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

associated_token_program [Program<AssociatedToken>]
  (no constraints)
  has_one: []
  close_target: null

rent [Sysvar <  Rent >]
  (no constraints)
  has_one: []
  close_target: null

token_metadata_program [Program<Metaplex>]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.5d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.5e Arithmetic Analysis
| Op | Style | Expression | Risk |
|---|---|---|---|
| add | checked | params.token_offset.checked_add (initial_mint) | Extractor marked this arithmetic path as checked. |

#### 2.5f Audit Notes
- [HIGH] metadata is unchecked in init_token. Constraint coverage: account (mut). Attack path: if an attacker can influence the referenced pubkey source, value transfer or metadata handling may be redirected.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (payer).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.6 - `init_ata`
> Context: `InitAta` | Signers: 1 (payer) | Accounts: 7 | Flags: 1

#### 2.6a Parameters
No parameters.

#### 2.6b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| payer | Signer | Yes | Yes | No | account (mut) |
| authority | AccountInfo | No | No | Yes | - |
| payer_ata | Account<TokenAccount> | No | No | No | account (init, payer = payer, associated_token::mint = mint, associated_token::authority = authority ,) |
| token_program | Program<Token> | No | No | No | - |
| mint | Account<Mint> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| associated_token_program | Program<AssociatedToken> | No | No | No | - |

#### 2.6c Constraints (verbatim extraction)
```text
payer [Signer]
  account (mut)
  has_one: []
  close_target: null

authority [AccountInfo UNCHECKED]
  (no constraints)
  has_one: []
  close_target: null

payer_ata [Account<TokenAccount>]
  account (init, payer = payer, associated_token::mint = mint, associated_token::authority = authority ,)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

mint [Account<Mint>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

associated_token_program [Program<AssociatedToken>]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.6d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.6e Arithmetic Analysis
No arithmetic operations extracted for this instruction.

#### 2.6f Audit Notes
- [HIGH] authority is unchecked in init_ata. Constraint coverage: -. Attack path: if an attacker can influence the referenced pubkey source, value transfer or metadata handling may be redirected.
- [POSITIVE] Signer gating present (payer).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.7 - `buy_tokens`
> Context: `BuyTokens` | Signers: 1 (buyer) | Accounts: 10 | Flags: 2

#### 2.7a Parameters
| Param | Type | Overflow |
|---|---|---|
| sol_amount | u64 | Yes |
| min_token_amount | u64 | Yes |
| _market_version | u16 | No |

#### 2.7b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| bonding_curve | Account<BondingCurve> | Yes | No | No | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) |
| bonding_curve_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve ,) |
| buyer | Signer | Yes | Yes | No | account (mut) |
| buyer_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = buyer ,) |
| market | Account<Market> | No | No | No | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) |
| trading_fee_treasury | AccountInfo | Yes | No | Yes | account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ()) |
| mint | Account<Mint> | No | No | No | - |
| token_program | Program<Token> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| associated_token_program | Program<AssociatedToken> | No | No | No | - |

#### 2.7c Constraints (verbatim extraction)
```text
bonding_curve [Account<BondingCurve>]
  account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ())
  has_one: []
  close_target: null

bonding_curve_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve ,)
  has_one: []
  close_target: null

buyer [Signer]
  account (mut)
  has_one: []
  close_target: null

buyer_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = buyer ,)
  has_one: []
  close_target: null

market [Account<Market>]
  account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

trading_fee_treasury [AccountInfo UNCHECKED]
  account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ())
  has_one: []
  close_target: null

mint [Account<Mint>]
  (no constraints)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

associated_token_program [Program<AssociatedToken>]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.7d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.7e Arithmetic Analysis
| Op | Style | Expression | Risk |
|---|---|---|---|
| sub | checked | bonding_curve.real_token_reserves.checked_sub (token_amount) | Extractor marked this arithmetic path as checked. |
| add | checked | bonding_curve.real_sol_reserves.checked_add (new_sol_amount) | Extractor marked this arithmetic path as checked. |
| sub | checked | bonding_curve.virtual_token_reserves.checked_sub (token_amount) | Extractor marked this arithmetic path as checked. |
| add | checked | bonding_curve.virtual_sol_reserves.checked_add (new_sol_amount) | Extractor marked this arithmetic path as checked. |
| sub | checked | token_supply - bonding_curve.real_token_reserves | Unchecked subtraction can underflow and break reserve or pricing invariants. |

#### 2.7f Audit Notes
- [HIGH] trading_fee_treasury is unchecked in buy_tokens. Constraint coverage: account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ()). Attack path: if an attacker can influence the referenced pubkey source, value transfer or metadata handling may be redirected.
- [MEDIUM] Unchecked arithmetic expression in buy_tokens: token_supply - bonding_curve.real_token_reserves. Attack path: reserve or pricing invariants can drift if bounds are violated before this operation.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (buyer).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.8 - `sell_tokens`
> Context: `Sell` | Signers: 1 (seller) | Accounts: 10 | Flags: 1

#### 2.8a Parameters
| Param | Type | Overflow |
|---|---|---|
| token_amount | u64 | Yes |
| min_sol_amount | u64 | Yes |
| market_version | u16 | No |

#### 2.8b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| bonding_curve | Account<BondingCurve> | Yes | No | No | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) |
| bonding_curve_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve) |
| seller | Signer | Yes | Yes | No | account (mut) |
| seller_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = seller ,) |
| market | Account<Market> | No | No | No | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) |
| trading_fee_treasury | AccountInfo | Yes | No | Yes | account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ()) |
| mint | Account<Mint> | No | No | No | - |
| token_program | Program<Token> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| associated_token_program | Program<AssociatedToken> | No | No | No | - |

#### 2.8c Constraints (verbatim extraction)
```text
bonding_curve [Account<BondingCurve>]
  account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ())
  has_one: []
  close_target: null

bonding_curve_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve)
  has_one: []
  close_target: null

seller [Signer]
  account (mut)
  has_one: []
  close_target: null

seller_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = seller ,)
  has_one: []
  close_target: null

market [Account<Market>]
  account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

trading_fee_treasury [AccountInfo UNCHECKED]
  account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ())
  has_one: []
  close_target: null

mint [Account<Mint>]
  (no constraints)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

associated_token_program [Program<AssociatedToken>]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.8d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.8e Arithmetic Analysis
[WARNING] No arithmetic nodes extracted but numeric parameters exist; verify checked add/sub/mul/div in function body.

#### 2.8f Audit Notes
- [HIGH] trading_fee_treasury is unchecked in sell_tokens. Constraint coverage: account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ()). Attack path: if an attacker can influence the referenced pubkey source, value transfer or metadata handling may be redirected.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (seller).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.9 - `sell`
> Context: `Sell` | Signers: 1 (seller) | Accounts: 10 | Flags: 1

#### 2.9a Parameters
| Param | Type | Overflow |
|---|---|---|
| token_amount | u64 | Yes |
| min_sol_amount | u64 | Yes |
| _market_version | u16 | No |

#### 2.9b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| bonding_curve | Account<BondingCurve> | Yes | No | No | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) |
| bonding_curve_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve) |
| seller | Signer | Yes | Yes | No | account (mut) |
| seller_ata | Account<TokenAccount> | Yes | No | No | account (mut, associated_token::mint = mint, associated_token::authority = seller ,) |
| market | Account<Market> | No | No | No | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) |
| trading_fee_treasury | AccountInfo | Yes | No | Yes | account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ()) |
| mint | Account<Mint> | No | No | No | - |
| token_program | Program<Token> | No | No | No | - |
| system_program | Program<System> | No | No | No | - |
| associated_token_program | Program<AssociatedToken> | No | No | No | - |

#### 2.9c Constraints (verbatim extraction)
```text
bonding_curve [Account<BondingCurve>]
  account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ())
  has_one: []
  close_target: null

bonding_curve_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = bonding_curve)
  has_one: []
  close_target: null

seller [Signer]
  account (mut)
  has_one: []
  close_target: null

seller_ata [Account<TokenAccount>]
  account (mut, associated_token::mint = mint, associated_token::authority = seller ,)
  has_one: []
  close_target: null

market [Account<Market>]
  account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

trading_fee_treasury [AccountInfo UNCHECKED]
  account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ())
  has_one: []
  close_target: null

mint [Account<Mint>]
  (no constraints)
  has_one: []
  close_target: null

token_program [Program<Token>]
  (no constraints)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

associated_token_program [Program<AssociatedToken>]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.9d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.9e Arithmetic Analysis
| Op | Style | Expression | Risk |
|---|---|---|---|
| add | checked | bonding_curve.real_token_reserves.checked_add (new_token_amount) | Extractor marked this arithmetic path as checked. |
| sub | checked | bonding_curve.real_sol_reserves.checked_sub (sol_amount) | Extractor marked this arithmetic path as checked. |
| add | checked | bonding_curve.virtual_token_reserves.checked_add (new_token_amount) | Extractor marked this arithmetic path as checked. |
| sub | checked | bonding_curve.virtual_sol_reserves.checked_sub (sol_amount) | Extractor marked this arithmetic path as checked. |

#### 2.9f Audit Notes
- [HIGH] trading_fee_treasury is unchecked in sell. Constraint coverage: account (mut, constraint = market.trading_fee_treasury == trading_fee_treasury.key ()). Attack path: if an attacker can influence the referenced pubkey source, value transfer or metadata handling may be redirected.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (seller).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

### 2.10 - `init_market`
> Context: `InitializeMarket` | Signers: 1 (payer) | Accounts: 4 | Flags: 0

#### 2.10a Parameters
| Param | Type | Overflow |
|---|---|---|
| version | u16 | No |
| market_data | MarketParams | No |

#### 2.10b Accounts
| Account | Type | Mut | Signer | Unchecked | Constraint Summary |
|---|---|---|---|---|---|
| market | Account<Market> | No | No | No | account (init, payer = payer, space = size_of::< Market > () + 8, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump) |
| payer | Signer | Yes | Yes | No | account (mut) |
| system_program | Program<System> | No | No | No | - |
| rent | Sysvar <  Rent > | No | No | No | - |

#### 2.10c Constraints (verbatim extraction)
```text
market [Account<Market>]
  account (init, payer = payer, space = size_of::< Market > () + 8, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump)
  has_one: []
  close_target: null

payer [Signer]
  account (mut)
  has_one: []
  close_target: null

system_program [Program<System>]
  (no constraints)
  has_one: []
  close_target: null

rent [Sysvar <  Rent >]
  (no constraints)
  has_one: []
  close_target: null

```

#### 2.10d Body Checks
[WARNING] No require checks extracted. Verify authorization, bounds, and invariant checks in source body.

#### 2.10e Arithmetic Analysis
[WARNING] No arithmetic nodes extracted but numeric parameters exist; verify checked add/sub/mul/div in function body.

#### 2.10f Audit Notes
- [INFO] No precomputed flags mapped to this instruction.
- [POSITIVE] PDA seed constraints are present in this instruction, reducing account substitution risk for seeded accounts.
- [POSITIVE] Signer gating present (payer).
- [WARNING] Missing extracted require checks; perform manual verification for logic-level authorization and slippage/bounds invariants.

## 3. Account and PDA Catalogue

### 3a Account Structs

#### BondingCurve
| Field | Type | Tag | Notes |
|---|---|---|---|
| virtual_token_reserves | u64 | [NUMERIC ⚠ overflow] | Numeric state; review checked arithmetic around updates. |
| virtual_sol_reserves | u64 | [NUMERIC ⚠ overflow] | Numeric state; review checked arithmetic around updates. |
| real_token_reserves | u64 | [NUMERIC ⚠ overflow] | Numeric state; review checked arithmetic around updates. |
| real_sol_reserves | u64 | [NUMERIC ⚠ overflow] | Numeric state; review checked arithmetic around updates. |
| token_supply | u64 | - | Standard field. |
| completed | bool | - | Standard field. |
| tokens_fee_cooldown_timestamp | i64 | [NUMERIC ⚠ overflow], [TIMESTAMP ⚠ manipulation] | Timestamp logic is manipulable by slot time drift; verify cooldown and ordering checks. |
| market | Pubkey | - | Pubkey linkage; verify ownership and trusted source. |

#### Market
| Field | Type | Tag | Notes |
|---|---|---|---|
| version | u16 | - | Standard field. |
| authority | Pubkey | [AUTHORITY], [PUBKEY ⚠ validation] | Authority-bearing field; validate all update paths. |
| initial_mint | u64 | - | Standard field. |
| escape_amount | u64 | [NUMERIC ⚠ overflow] | Numeric state; review checked arithmetic around updates. |
| escape_fee_bps | u16 | - | Standard field. |
| escape_fee_treasury | Pubkey | - | Pubkey linkage; verify ownership and trusted source. |
| trading_fee_bps | u16 | - | Standard field. |
| trading_fee_treasury | Pubkey | - | Pubkey linkage; verify ownership and trusted source. |
| tokens_fee_amount | u64 | [NUMERIC ⚠ overflow] | Numeric state; review checked arithmetic around updates. |
| tokens_fee_treasury | Pubkey | - | Pubkey linkage; verify ownership and trusted source. |

### 3b PDA Catalogue

| PDA Name | Seeds / Constraint Snippet | Derived In |
|---|---|---|
| market | account (init, payer = payer, space = size_of::< Market > () + 8, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump) | initialize_market |
| market | account (mut, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump) | update_market |
| bonding_curve | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) | process_completed_curve |
| market | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) | process_completed_curve |
| bonding_curve | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) | withdraw_tokens_fee |
| market | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) | withdraw_tokens_fee |
| bonding_curve | account (init, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, payer = payer, space = size_of::< BondingCurve > () + 8 ,) | init_token |
| bonding_curve | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) | buy_tokens |
| market | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) | buy_tokens |
| bonding_curve | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) | sell_tokens |
| market | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) | sell_tokens |
| bonding_curve | account (mut, seeds = [b"bonding_curve".as_ref (), mint.key ().as_ref ()], bump, constraint = bonding_curve.market == market.key ()) | sell |
| market | account (seeds = [b"market".as_ref (), market_version.to_le_bytes ().as_ref ()], bump) | sell |
| market | account (init, payer = payer, space = size_of::< Market > () + 8, seeds = [b"market".as_ref (), version.to_le_bytes ().as_ref ()], bump) | init_market |

PDA security analysis:
- Market PDAs consistently use market + version seed patterns.
- Bonding curve PDAs consistently use bonding_curve + mint seed patterns.
- Verify bump persistence and canonical derivation checks in source for all mutating paths.

## 4. Authority and Trust Model

### 4a Authority Graph (ASCII)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                            ZENON TRUST BOUNDARY                             │
└──────────────────────────────────────────────────────────────────────────────┘

                    EXTERNAL ACTORS                         PROGRAM STATE
           ┌─────────────────────────────┐         ┌──────────────────────────┐
           │ payer (signer)              │         │ market PDA               │
           │ ├─ initialize_market        │────────►│ seeds=["market",version]│
           │ ├─ init_market              │         │ authority, fee treasuries│
           │ ├─ init_token               │         └────────────┬─────────────┘
           │ └─ init_ata                 │                      │
           └─────────────────────────────┘                      │ constraint:
                                                                │ bonding_curve.market == market.key
           ┌─────────────────────────────┐                      ▼
           │ authority/admin (signer)    │         ┌──────────────────────────┐
           │ ├─ update_market            │────────►│ bonding_curve PDA         │
           │ ├─ process_completed_curve  │         │ seeds=["bonding_curve",  │
           │ └─ withdraw_tokens_fee      │         │        mint.key]          │
           └─────────────────────────────┘         │ reserves, completed flag  │
                                                   └────────────┬─────────────┘
           ┌─────────────────────────────┐                      │
           │ buyer (signer)              │──────────────────────┤ buy_tokens
           │ seller (signer)             │──────────────────────┤ sell_tokens / sell
           └─────────────────────────────┘                      ▼
                                                   ┌──────────────────────────┐
                                                   │ token accounts (ATA set) │
                                                   │ bonding_curve_ata        │
                                                   │ buyer/seller/admin ATAs  │
                                                   └──────────────────────────┘

Unchecked trust edges (manual verification required):
  process_completed_curve.escape_fee_treasury
  init_token.metadata
  init_ata.authority
  buy_tokens/sell_tokens/sell.trading_fee_treasury
```

### 4b Instruction Flow Diagram (ASCII)

```text
┌─────────────────────── Phase 1: Bootstrap ───────────────────────┐
│ initialize_market / init_market                                   │
│            │                                                      │
│            ├──────────────► update_market                         │
│            │                                                      │
│            └──────────────► init_token ───────► init_ata         │
└────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────── Phase 2: Trading Loop ─────────────────────┐
│ buy_tokens ───────────────────────────────► reserves update        │
│    ▲                                                  │            │
│    │                                                  ▼            │
│ sell_tokens / sell ◄──────────────────────────── reserve release  │
└────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────── Phase 3: Completion ───────────────────────┐
│ process_completed_curve ───────────────► final distribution path   │
│ withdraw_tokens_fee      ─────────────► treasury withdrawal path   │
└────────────────────────────────────────────────────────────────────┘
```

### 4c Account Dependency Diagram (ASCII)

```text
                                ┌──────────────────────────────┐
                                │            mint              │
                                └──────────────┬───────────────┘
                                               │ seed input
                                               ▼
┌──────────────────────────────┐    constraint: bonding_curve.market == market.key
│ market PDA                   │◄───────────────────────────────────────────────────┐
│ seeds=["market",version]    │                                                    │
│ fields: authority, fees,...  │                                                    │
└──────────────┬───────────────┘                                                    │
               │                                                                    │
               │ referenced by                                                      │
               ▼                                                                    │
┌──────────────────────────────┐                                                    │
│ bonding_curve PDA            │────────────────────────────────────────────────────┘
│ seeds=["bonding_curve",mint]│
│ reserves, completed, cooldown│
└──────────────┬───────────────┘
               │ associated_token::authority = bonding_curve
               ▼
┌──────────────────────────────┐
│ bonding_curve_ata            │
│ reserve token store          │
└──────────────┬───────────────┘
               │ token flow
   ┌───────────┴───────────┐
   ▼                       ▼
┌───────────────┐   ┌────────────────────┐
│ buyer_ata     │   │ seller_ata/admin_ata│
│ inbound tokens│   │ outbound/fee paths  │
└───────────────┘   └────────────────────┘
```

### 4d Trust Assumption Table

| Role | Controls | Assumed Honest | Privilege Escalation Path | Risk |
|---|---|---|---|---|
| payer | market init, mint init, ATA init | Yes | If payer key is compromised during setup, initial authority and treasury setup can be malicious | High |
| authority/admin | market updates, curve completion, fee withdrawal | Yes | Unauthorized changes to treasury or fee params if authority path is weak | High |
| buyer/seller | trading entrypoints | No | Malicious account substitution attempts against unchecked accounts | Medium |
| protocol account constraints | PDA seed validation and account matching | Yes | Constraint omissions in body logic can bypass intended invariant checks | Medium |

## 5. Token and CPI Flows

### 5a Token Account Flow Table

| Account Name | Mint | Authority | Balance Role | Instructions | Flow |
|---|---|---|---|---|---|
| bonding_curve_ata | mint account | bonding_curve PDA | Curve reserve token account | process_completed_curve, withdraw_tokens_fee, buy_tokens, sell_tokens, sell, init_token | Token inventory source/sink for trading and completion |
| buyer_ata / seller_ata | mint account | buyer/seller signer | User inventory account | buy_tokens, sell_tokens, sell | Receives bought tokens or sends sold tokens |
| admin_ata / treasury_ata | mint account | admin/treasury owner | Fee and post-completion collection | process_completed_curve, withdraw_tokens_fee | Fee extraction and treasury movement |
| payer_ata | mint account | authority (unchecked in context) | ATA initialization path | init_ata | Account creation/setup path |

### 5b CPI Call Map (ASCII)

```text
init_token
  -> token::mint_to (top-level)
Implicit token movements likely occur in buy/sell/fee instructions through token accounts and ATA constraints.
```

### 5c Token-2022 Compatibility

No explicit Token-2022 program identifiers were extracted. Current extraction indicates SPL Token program paths.
Manual check required: verify behavior if Token-2022 mints with transfer-fee hooks are introduced, since fee-on-transfer can break reserve accounting assumptions.

## 6. Error Code Registry

| Code | Name | Message | Instructions That Reference It |
|---|---|---|---|
| BondingCurveCompleted | BondingCurveCompleted | Bonding curve is completed | Not linked by extractor |
| NotEnoughTokenReserves | NotEnoughTokenReserves | Not enough token reserves | Not linked by extractor |
| TokenAmountZero | TokenAmountZero | Token amount is zero | Not linked by extractor |
| ExceededMaxSolAmount | ExceededMaxSolAmount | Exceeded max sol amount | Not linked by extractor |
| MinSolAmountNotMet | MinSolAmountNotMet | Min sol amount not met | Not linked by extractor |
| MinTokenAmountNotMet | MinTokenAmountNotMet | Min token amount not met | Not linked by extractor |
| TransferError | TransferError | Error transferring tokens | Not linked by extractor |
| FeeBpsTooHigh | FeeBpsTooHigh | Fee bps too high | Not linked by extractor |
| TokensBpsTooHigh | TokensBpsTooHigh | Treasury tokens bps too high | Not linked by extractor |
| EscapeAmountTooHigh | EscapeAmountTooHigh | Escape amount too high | Not linked by extractor |
| EscapeAmountZero | EscapeAmountZero | Escape amount is zero | Not linked by extractor |
| BondingCurveNotCompleted | BondingCurveNotCompleted | Bonding curve is not completed | Not linked by extractor |
| TokensFeeCooldown | TokensFeeCooldown | Tokens fee cooldown | Not linked by extractor |

Observation: error enums are extracted, but instruction-level linkage is mostly absent in current output; verify exact require error usage from source manually.

## 7. Attack Surface Summary

| # | Location | Finding | Severity | Source | Exploit Path |
|---|---|---|---|---|---|
| 1 | process_completed_curve::escape_fee_treasury | Unchecked account escape_fee_treasury | HIGH | UncheckedAccount — zero Anchor validation. | If account key source can be attacker-controlled, escape_fee_treasury can redirect value flow or metadata operations. |
| 2 | init_token::metadata | Unchecked account metadata | HIGH | UncheckedAccount — zero Anchor validation. | If account key source can be attacker-controlled, metadata can redirect value flow or metadata operations. |
| 3 | init_ata::authority | Unchecked account authority | HIGH | UncheckedAccount — zero Anchor validation. | If account key source can be attacker-controlled, authority can redirect value flow or metadata operations. |
| 4 | buy_tokens::trading_fee_treasury | Unchecked account trading_fee_treasury | HIGH | UncheckedAccount — zero Anchor validation. | If account key source can be attacker-controlled, trading_fee_treasury can redirect value flow or metadata operations. |
| 5 | buy_tokens | Unchecked arithmetic: token_supply - bonding_curve.real_token_reserves | MEDIUM | Raw sub operation on numeric field. | Underflow/overflow path can destabilize bonding-curve reserve invariants and pricing checks. |
| 6 | sell_tokens::trading_fee_treasury | Unchecked account trading_fee_treasury | HIGH | UncheckedAccount — zero Anchor validation. | If account key source can be attacker-controlled, trading_fee_treasury can redirect value flow or metadata operations. |
| 7 | sell::trading_fee_treasury | Unchecked account trading_fee_treasury | HIGH | UncheckedAccount — zero Anchor validation. | If account key source can be attacker-controlled, trading_fee_treasury can redirect value flow or metadata operations. |

## 8. Manual Verification Checklist

CRITICAL SECURITY VERIFICATIONS
--------------------------------
[ ] initialize_market: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] update_market: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] process_completed_curve: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] withdraw_tokens_fee: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] init_token: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] init_ata: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] buy_tokens: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] sell_tokens: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] sell: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] init_market: No extracted require checks. Validate authorization, slippage/bounds checks, and state transition invariants in body.
[ ] process_completed_curve.escape_fee_treasury: Unchecked account wrapper. Confirm owner/type/executable validation and immutable trusted key source.
[ ] init_token.metadata: Unchecked account wrapper. Confirm owner/type/executable validation and immutable trusted key source.
[ ] init_ata.authority: Unchecked account wrapper. Confirm owner/type/executable validation and immutable trusted key source.
[ ] buy_tokens.trading_fee_treasury: Unchecked account wrapper. Confirm owner/type/executable validation and immutable trusted key source.
[ ] sell_tokens.trading_fee_treasury: Unchecked account wrapper. Confirm owner/type/executable validation and immutable trusted key source.
[ ] sell.trading_fee_treasury: Unchecked account wrapper. Confirm owner/type/executable validation and immutable trusted key source.
[ ] buy_tokens: Unchecked arithmetic (token_supply - bonding_curve.real_token_reserves). Confirm precondition bounds and checked math alternative.

ADDITIONAL AUDIT ITEMS
----------------------
[ ] BondingCurve.virtual_token_reserves: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.
[ ] BondingCurve.virtual_sol_reserves: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.
[ ] BondingCurve.real_token_reserves: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.
[ ] BondingCurve.real_sol_reserves: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.
[ ] BondingCurve.tokens_fee_cooldown_timestamp: Timestamp field present. Validate cooldown/expiry against slot manipulation edge cases.
[ ] BondingCurve.tokens_fee_cooldown_timestamp: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.
[ ] Market.authority: Authority field. Confirm no unauthorized mutation path exists.
[ ] Market.escape_amount: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.
[ ] Market.tokens_fee_amount: Numeric reserve/accounting field. Confirm checked arithmetic for every mutation path.

## 9. Recon Metadata

| Metric | Value |
|---|---|
| Program | zenon |
| Program ID | SLAPUqHm76SGThDr4JUyRDVsGBmxwGkxicWwknkgH5c |
| Scope generated_at | 2026-04-20T04:20:40.007916+00:00 |
| Report generated_at | 2026-04-20T04:26:24.501Z |
| Instructions analyzed | 10 |
| Unique instruction names | 10 |
| Unique context structs | 8 |
| Total account touches (sum over instructions) | 79 |
| Account context structs extracted | 8 |
| Account data structs extracted | 2 |
| PDA map entries | 14 |
| Explicit CPI calls | 1 |
| Error codes extracted | 13 |
| Flags extracted | 7 |
| summary.call_surface entries | 10 |
| summary.authority_map entries | 10 |

| Report line count | 1038 |
