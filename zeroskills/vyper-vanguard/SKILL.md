---
name: vyper-vanguard
description: Review Vyper contracts for high-signal language-semantics and protocol-accounting bugs: raw_call/raw_return forwarding, factory and blueprint traps, nonreentrancy observation windows, module/interface drift, byte/convert edge cases, unsafe arithmetic, iterative invariant drift, dust/share bugs, zero-amount state mutation, and multicall sequencing. Use when reviewing Vyper source, Vyper interfaces, JSON ABIs imported into Vyper, or Vyper deployment/build artifacts.
---

Analyze Vyper contracts for bugs that come from Vyper-specific semantics or from protocol accounting patterns that Vyper code often uses.

Assume a modern Vyper compiler unless the repo proves otherwise. Do not center the review on historical compiler CVEs. Still record the compiler version, EVM version, and build flags because old pinned versions can sharpen a finding, but only report version-dependent bugs when there is also a concrete exploit path.

Only report issues that can cause wrong value, wrong authority, locked funds, broken initialization, state drift, corrupted accounting, invalid child deployment, or trusted code consuming false data.

## Applicability gates

Proceed if any are present:

- `.vy`, `.vyi`, or Vyper build/deployment artifacts
- JSON ABI imported into Vyper
- scripts/configs using Vyper, Boa/Titanoboa, Ape, Brownie, or Vyper compiler output
- Vyper-specific primitives such as `raw_call`, `@raw_return`, `send`, `create_from_blueprint`, `raw_create`, `convert`, `slice`, `concat`, `extract32`, `unsafe_*`, `sqrt`, modules, or interfaces

Otherwise do not force findings.

## High-signal probes

### 1) Raw calls, raw returns, and proxy-like forwarding

Check `raw_call` sites for semantic mismatches:

- `revert_on_failure=False` where `success` is ignored, trusted too early, or separated from return-data validation
- `max_outsize` too small, zero, or not checked before decoding/trusting returndata
- user-controlled target, calldata, value, gas, or delegate/static mode
- accounting that assumes ETH/value moved when the actual call mode cannot move it
- return bytes used for auth, price, amount, recipient, routing, or settlement

For `@raw_return`, treat the function as proxy-like even if the contract does not call itself a proxy. Look for mixed ABI/raw return paths, raw bytes returned to callers expecting ABI-encoded data, user-controlled delegatecall targets, and storage mutation through forwarded calldata.

Do not report `raw_call` or `@raw_return` presence alone. Report only when a caller-controlled path can make the contract trust the wrong target, wrong return bytes, wrong success state, or wrong storage context.

### 2) Factories, blueprints, and child identity

Review `create_from_blueprint`, `raw_create`, `create_copy_of`, `create_minimal_proxy_to`, `salt`, `raw_args`, and `code_offset`.

Look for:

- user-controlled blueprint/initcode/target/salt/value without allowlist or codehash check
- created address trusted before deployment success, runtime code identity, and initialization are verified
- `revert_on_failure=False` where zero address or failed creation is treated as a real child
- blueprint contracts callable directly when constructor/initcode has side effects
- child contracts inheriting unsafe assumptions from stale modules, interfaces, or compiler settings

Report only if the wrong child, wrong code, wrong initializer, or wrong address can affect funds, permissions, accounting, or future protocol actions.

### 3) Reentrancy and observation windows

For modern Vyper, assume a global lock when nonreentrancy is enabled, but remember that `#pragma nonreentrancy on` is file-scoped and `@reentrant` can opt functions or getters back out. Treat public getters as relevant when other contracts, keepers, or oracles consume them.

Trace each external interaction:

- What storage/accounting is incomplete at the call?
- Can a callback, default function, token hook, proxy path, or second public function observe or mutate that incomplete state?
- Can read-only observation change pricing, oracle values, settlement, liquidation, or keeper behavior?
- Are imported module functions or exported functions outside the assumed lock policy?

Only report if there is a meaningful callback/read path and a broken invariant. Do not report generic “external call before state update.”

Historical note: if the compiler is old and uses keyed `@nonreentrant("key")`, check shared-key lock allocation and fallback/default-function protection. Keep this as a branch, not the main review.

### 4) Modules, interfaces, and ABI drift

Review Vyper modules as stateful components, not just libraries.

Look for:

- module state used without the expected `initializes`/dependency initialization path
- `uses:` deferring initialization to another module, but the root contract initializes dependencies in the wrong order
- `exports:` exposing external module functions that bypass top-level access control, accounting hooks, or nonreentrancy assumptions
- imported files lacking the pragma/settings/security posture assumed by the caller

Review `.vyi`, inline interfaces, and JSON ABIs:

- mutability mismatch: `view`/`pure` declared for a target that can mutate or revert under `STATICCALL`
- dynamic return bounds too small or trusted without length/domain checks
- `default_return_value` hiding missing ERC20 return values in paths where failure should be explicit
- default-argument interfaces where the target does not actually implement every implied selector
- `skip_contract_check` on addresses that can be EOAs, destroyed contracts, or undeployed CREATE2 addresses

Report only if the mismatch feeds value, authority, accounting, routing, or initialization.

### 5) Bytes, conversion, and side-effect semantics

Investigate `slice`, `concat`, `extract32`, ABI decode, `Bytes[N]` equality, and dynamic external returns when caller-controlled bytes influence signatures, identifiers, routing, storage keys, or return-data trust.

For `convert`, do not assume it is unsafe. Look for protocol-level misunderstandings:

- bytes/address conversions where right-padding vs left-padding rotation changes the significant bytes
- bytes-to-signed-int sign extension changing comparison or amount logic
- decimal-to-integer truncation or signed division rounding toward zero
- signed/unsigned boundaries where the caller can force a revert or bypass a branch
- narrowed types used in share counts, loop bounds, indexes, fees, or packed flags

Avoid side-effectful expressions inside builtins, operators, logs, augmented assignments, and creation args. Split expressions into temporaries when a read and a mutation touch the same storage, memory, dynamic array, or external state.

Report only if the semantic mismatch changes a security decision or numeric invariant.

### 6) Math, solvers, shares, and sequencing

Spend serious effort here. This is often higher-signal than compiler CVE matching.

Check iterative solvers: Newton, binary search, fixed-point loops, pool invariant solvers, interest/rate updates.

Report when:

- no iteration cap, no convergence threshold, or no validated input domain
- convergence can land on the wrong branch/root and feed pricing or shares
- truncation causes a product/division term to collapse to zero in small-balance regimes
- paired operations round in attacker-favorable directions across repeated cycles
- dust deposits, empty-pool initialization, or first-depositor paths mint disproportionate shares
- zero-amount calls mutate timestamps, reward checkpoints, cached rates, claim state, events, or cooldowns
- cached derived state is not invalidated with the primary state: total supply, rates, normalizers, invariant `D`, reserves, debt indexes
- `multicall` or arbitrary sequencing combines individually harmless functions into state drift

Check `unsafe_add`, `unsafe_sub`, `unsafe_mul`, `unsafe_div`, `pow_mod256`, and hand-written `A - B * C` formulas. Report only with operand provenance and a value-impacting path.
