# Solana Sysvars and Clock Audit (v0.4.2)

> **Loads when**: any `Clock::get`, `Sysvar<'info, Clock>`, `sysvar::clock::id()`, `recent_blockhashes`, or `instructions` sysvar reference in scope.
> **Primary vectors**: V117 (oracle staleness), V125 (slot-monotonicity assumptions).
> **Coordinates with**: [`anchor-account-validation.md`](anchor-account-validation.md).

## What this surface is

Solana exposes runtime state through **sysvars** — read-only accounts at fixed addresses that report slot, timestamp, epoch, rent parameters, recent blockhashes, and the currently-executing instruction list. Programs that read sysvars are exposed to:

1. **Wrong-sysvar-account substitution**: caller passes an attacker-controlled `AccountInfo` claiming to be the Clock sysvar; the program reads stale or crafted bytes.
2. **Unsound time assumptions**: validator clocks can drift, slot timestamps can decrease (the runtime only guarantees `unix_timestamp` is non-decreasing within a slot, not across reorgs).
3. **`recent_blockhashes` for randomness**: predictable + manipulable; attacker validators can influence which blockhash lands in a given slot.
4. **Instruction-introspection misuse**: the `instructions` sysvar enables top-of-block / sandwich detection but is often used incorrectly.

## When to load this skill

Trigger on **any** of:

- `solana_program::clock::Clock::get()` (Anchor-style modern API).
- `Sysvar<'info, Clock>` field in `#[derive(Accounts)]`.
- `sysvar::clock::id()` or `sysvar::recent_blockhashes::id()` constant.
- `solana_program::sysvar::instructions::load_current_index_checked`.
- `unix_timestamp`, `slot`, `epoch_start_timestamp`, `leader_schedule_epoch`, `epoch` field accesses.
- Hash construction using `Clock` or `recent_blockhashes` data as input.

## Step-by-step audit procedure

### 1. Audit sysvar-address pinning

For each sysvar account passed via instruction accounts, confirm the address is pinned:

```rust
// SAFE — Anchor's typed Sysvar handle:
pub clock: Sysvar<'info, Clock>,

// SAFE — explicit address constraint:
#[account(address = sysvar::clock::ID)]
pub clock: AccountInfo<'info>,

// VULNERABLE — no constraint on the account:
pub clock: AccountInfo<'info>,
```

If the sysvar is passed as unconstrained `AccountInfo`, the attacker can pass any account — and the program will deserialize attacker bytes as `Clock`. Finding: V4 + clock-substitution HIGH.

`Clock::get()` (the syscall API) is always safe — it reads from runtime memory, not from an account. Prefer this over the account-based sysvar handle when possible.

### 2. Audit time-monotonicity assumptions

The Solana runtime guarantees:

- `slot` is monotonically increasing across slots (cannot decrease).
- `unix_timestamp` is **non-decreasing** but the runtime allows it to stay equal across consecutive slots, and after a reorg, the value can effectively rewind (the chain's view of timestamp goes back to before the reorg point).
- `epoch` increases monotonically (epochs don't roll back).
- `leader_schedule_epoch` may be > current `epoch` (it's the epoch the leader schedule is computed for).

Common bugs:

| Pattern | Bug |
|---------|-----|
| `if Clock::get()?.unix_timestamp > stored.expiry { ... }` | OK if stored.expiry was set with current timestamp; FALSE if attacker can make stored.expiry = future via state corruption |
| `if Clock::get()?.unix_timestamp - stored.last_tick > INTERVAL { ... }` | Underflow if `last_tick > unix_timestamp` after reorg; V81 panic in debug, wrapping silent in release |
| `if stored.slot < Clock::get()?.slot { ... }` | Correct for slot (monotonic), suspect if `stored.slot` is signed (`i64`) |
| `Clock::get()?.unix_timestamp.try_into::<u32>()?` | Will fail in year 2106; not a current finding but a long-term audit note |
| `assert!(Clock::get()?.unix_timestamp > 0)` | Useless — the runtime guarantees timestamp > 0 by genesis |

Findings: V125 candidates for any code that subtracts timestamps without an underflow guard or that conflates `slot` (monotonic) with `unix_timestamp` (non-decreasing but not strictly increasing).

### 3. Audit `recent_blockhashes` as randomness source

If the program reads `recent_blockhashes` and uses the bytes as randomness (lottery, draw, raffle, ordering):

| Risk | Severity |
|------|----------|
| Predictable: any client can query the recent blockhashes pre-tx | HIGH (deterministic randomness) |
| Manipulable: validators leading consecutive slots can choose blockhashes | HIGH (validator-set-controlled) |
| Combined with attacker-controlled retry: attacker submits tx only when blockhash favorable | HIGH |

Fix patterns: use VRF (verifiable random function) outputs from oracles, or commit-reveal schemes. Vanilla blockhash randomness is broken-by-design.

Finding: V120-class (oracle/randomness manipulation), HIGH unless the use case is non-financial.

### 4. Audit `instructions` sysvar usage

The `Instructions` sysvar (`Sysvar1nstructions1111111111111111111111111`) exposes the currently-executing transaction's instruction list. Programs use it to:

- Detect whether the current instruction is the first or last in the transaction.
- Read sibling instructions' data (e.g. verify a paired Token-Transfer happened).
- Enforce "this instruction can only be called with X as a sibling".

Common bugs:

| Pattern | Bug |
|---------|-----|
| `load_current_index_checked(&instructions_sysvar)?` then assume index==0 means top of transaction | Suspect — caller can wrap with a no-op, putting your instruction at index 1 instead |
| Verifying a sibling Transfer by reading the next instruction without checking the program ID | V4 (any program's data accepted as Token's) |
| Verifying paired instructions but not the *amount* or *destination* fields | Authorization without semantic equivalence |
| Using sibling-introspection in a CPI'd sub-program | Sub-program sees parent's instruction-sysvar layout — sibling assumptions don't survive nesting |

Findings: HIGH for missing program-id check on sibling instruction; MEDIUM for missing field-content check on a verified-program sibling.

### 5. Audit `epoch_start_timestamp` and `epoch_schedule`

If the program uses epoch boundaries for vesting / unlocks:

- `epoch_start_timestamp` is set at the start of each epoch (~2-3 days on mainnet); programs that compute "time since epoch N" use this.
- `EpochSchedule` (separate sysvar) gives the schedule of slot counts per epoch. On `localhost` / `devnet`, this is shorter (~32 slots).
- Programs that assume mainnet epoch length break on devnet.

Findings: rare, but list as Stage 4 review when the program logic spans multiple epochs.

### 6. Audit reorg-window sensitivity

After a reorg (any chain reorganization), the runtime's view of recent slots can shift. Confirmed slots (slots > ~32 ago) are immune; recent slots may rewind. Programs that:

- Make decisions based on `slot == X` for X within 32 of current `slot` → reorg-sensitive.
- Store `slot` values and compare to current `slot` later — fine if the stored slot is old enough.
- Mint or burn based on `recent_blockhashes` — see step 3.

Findings: usually MEDIUM unless the action is irreversible (e.g. minting tokens that can be sold off-chain).

## What counts as a finding

| Finding shape | Vector | Severity floor |
|---------------|--------|----------------|
| Sysvar account unconstrained (no `address` or typed `Sysvar`) | V4 | HIGH |
| Subtract-then-compare on `unix_timestamp` without underflow guard | V81 | MEDIUM |
| `recent_blockhashes` used as randomness with financial impact | V120 | HIGH |
| Sibling-instruction introspection without program-id check | V4 | HIGH |
| Sibling-instruction introspection without field-content check | new | MEDIUM |
| `Clock` field treated as strictly-increasing (vs non-decreasing) | V125 | MEDIUM |

## What does NOT count (SC-2 / known design)

- `Clock::get()` syscall use without account-validation concerns — the syscall doesn't take an account.
- Reorg sensitivity on slots > 32 ago — those are finalized.
- `unix_timestamp` comparisons on a `> 5 minute` window — small drift doesn't matter at coarse granularity.
- `recent_blockhashes` used as a unique transaction nonce (deduplication), not as randomness — that's the intended use.

## Comparator citations

| Claim | Comparator |
|-------|------------|
| "Clock sysvar address pinned by runtime" | `solana-program/src/sysvar/clock.rs` (the `pub const ID:` constant) |
| "Anchor's `Sysvar<'info, Clock>` validates address" | `anchor-lang/src/accounts/sysvar.rs:Sysvar::try_accounts` |
| "Solana guarantees `slot` monotonic, `unix_timestamp` non-decreasing" | `solana-program/src/clock.rs` doc-comments |
| "`load_current_index_checked` returns the current instruction's index" | `solana-program/src/sysvar/instructions.rs` |

## Common false-positive shapes

- `Clock::get()?.unix_timestamp` used purely for logging (not enforcement) — not a finding.
- Sysvar accounts in old codebases passed without typed wrapper but with manual `if account.key() != &sysvar::clock::ID` check — the check replaces the wrapper.
- "Randomness" derived from `slot` for non-financial purposes (e.g. UI rendering seed) — not a finding.
