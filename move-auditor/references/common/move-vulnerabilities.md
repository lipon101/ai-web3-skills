# Common Move Vulnerabilities

This document details Move language vulnerabilities that apply across **all** Move-based blockchains (Sui, Aptos, and others). For platform-specific vulnerabilities, see the Sui and Aptos resource files.

---

## M1. Improper Resource Abilities (CRITICAL)

### Description
Move's ability system (`copy`, `drop`, `key`, `store`) controls struct behavior at the compiler level. Incorrect abilities on asset/value types can lead to duplication or permanent loss of funds.

### Detection
```bash
# Find structs with asset-like names and copy/drop abilities
rg "public struct.*(Coin|Token|Asset|Balance|Vault|Share).*has.*(copy|drop)" sources/
# Find all structs with copy+drop on same type
rg "public struct.*has.*(copy.*drop|drop.*copy)" sources/
```

### Vulnerable Code
```move
// CRITICAL: Coin can be duplicated (copy)
public struct Coin has key, store, copy {
    value: u64,
}

// CRITICAL: Coin can be silently dropped/lost (drop)
public struct Coin has key, store, drop {
    value: u64,
}

// CRITICAL: Both copy and drop
public struct Token has key, store, copy, drop {
    amount: u64,
}
```

### Attack Scenarios
1. **Copy attack**: Attacker creates a coin, copies it, spends both copies — doubles their money
2. **Drop attack**: User receives coins, but they are accidentally dropped instead of being stored — permanent fund loss
3. **Both**: Unlimited money creation and silent destruction

### Secure Code
```move
// GOOD: Asset without copy or drop — must be explicitly handled
public struct Coin has key, store {
    value: u64,
}

// For burning, create explicit function
public entry fun burn(coin: Coin, _ctx: &mut TxContext) {
    let Coin { id, value: _ } = coin;
    object::delete(id);
}
```

---

## M2. Missing Access Control (CRITICAL)

### Description
Public or entry functions without proper authorization checks (capability, signer validation) allow anyone to execute privileged operations.

### Detection
```bash
# Find public/entry functions without capability or signer parameters
rg "public entry fun|public fun" sources/ | grep -v "Cap\b\|signer\|_ctx\|TxContext"
```

### Vulnerable Code
```move
// BAD: Anyone can call this privileged function
public entry fun set_fee_rate(
    config: &mut Config,
    new_rate: u64,
    _ctx: &mut TxContext
) {
    config.fee_rate = new_rate;
}

// BAD: Anyone can mint
public entry fun mint(
    treasury: &mut Treasury,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    transfer::public_transfer(
        treasury::withdraw(treasury, amount),
        recipient
    );
}
```

### Secure Code
```move
// GOOD: Requires admin capability
public entry fun set_fee_rate(
    _: &AdminCap,       // Capability gate
    config: &mut Config,
    new_rate: u64,
    _ctx: &mut TxContext
) {
    assert!(new_rate <= 10000, EInvalidRate);
    config.fee_rate = new_rate;
}

// GOOD: Requires minter capability
public entry fun mint(
    _: &MinterCap,      // Capability gate
    treasury: &mut Treasury,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(!treasury.paused, EPaused);
    assert!(amount <= treasury.max_mint, EExceedsLimit);
    transfer::public_transfer(
        treasury::withdraw(treasury, amount),
        recipient
    );
}
```

---

## M3. Witness Pattern Abuse (CRITICAL)

### Description
The Witness pattern is used to prove type ownership. If a witness can be created outside the module's `init` function, or has wrong abilities, attackers can forge proofs to mint tokens or create unauthorized types.

### Detection
```bash
# Find witness types
rg "Witness|witness" sources/
rg "public struct.*has drop" sources/
```

### Vulnerable Code
```move
// BAD: Witness creatable outside module init
public struct Witness has drop {}

public entry fun create_token(_: Witness, ...) {
    // Anyone can create Witness {} and call this
}

// BAD: Witness has store ability (can be saved and reused)
public struct Witness has drop, store {}

// BAD: Witness has copy ability (can be duplicated)
public struct Witness has drop, copy {}
```

### Secure Code
```move
// GOOD: One-Time Witness (OTW)
// Name must match module name in UPPERCASE, only has drop
public struct MY_TOKEN has drop {}

// GOOD: Only available during module initialization
fun init(otw: MY_TOKEN, ctx: &mut TxContext) {
    // OTW is consumed here, cannot be recreated
    coin::create_currency(otw, ...);
}
```

---

## M4. Capability Leakage (HIGH)

### Description
Capabilities (AdminCap, MintRef, BurnRef, etc.) that are transferred to unauthorized parties or can be claimed without authorization.

### Detection
```bash
# Find capability creation and transfer
rg "transfer.*Cap" sources/
rg "public_transfer.*Cap" sources/
rg "AdminCap|MintCap|OwnerCap|MintRef|BurnRef" sources/
```

### Vulnerable Code
```move
// BAD: Anyone can claim admin capability
public entry fun claim_admin(recipient: address, ctx: &mut TxContext) {
    transfer::public_transfer(
        AdminCap { id: object::new(ctx) },
        recipient
    );
}

// BAD: Capability transferable without authorization
public entry fun transfer_cap(cap: AdminCap, new_owner: address) {
    transfer::public_transfer(cap, new_owner);
}
```

### Secure Code
```move
// GOOD: Only at init, goes to publisher
fun init(ctx: &mut TxContext) {
    transfer::public_transfer(
        AdminCap { id: object::new(ctx) },
        tx_context::sender(ctx)
    );
}

// GOOD: Require existing admin to transfer
public entry fun transfer_admin(
    _: &AdminCap,    // Must already own admin cap
    cap: AdminCap,
    new_admin: address,
    _ctx: &mut TxContext
) {
    transfer::public_transfer(cap, new_admin);
}
```

---

## M5. Global Storage Errors (HIGH)

### Description
Unchecked `borrow_global`, missing `exists` checks, or incorrect `acquires` annotations causing runtime aborts or unexpected behavior.

### Detection
```bash
rg "borrow_global|borrow_global_mut" sources/
rg "move_to|move_from" sources/
rg "acquires" sources/
```

### Vulnerable Code
```move
// BAD: No existence check before borrow
public fun get_balance(addr: address): &mut u64 {
    borrow_global_mut<Balance>(addr)  // Aborts if not exists
}

// BAD: Double move_to without exists check
public entry fun init(account: &signer) {
    move_to<Config>(account, Config { ... });  // Aborts on second call
}
```

### Secure Code
```move
// GOOD: Check existence first
public fun get_balance(addr: address): &mut u64 {
    assert!(exists<Balance>(addr), ENotInitialized);
    borrow_global_mut<Balance>(addr)
}

// GOOD: Idempotent initialization
public entry fun init(account: &signer) {
    if (!exists<Config>(signer::address_of(account))) {
        move_to<Config>(account, Config { ... });
    };
}
```

---

## M6. Arithmetic Issues (MEDIUM)

### Description
Overflow/underflow in calculations. Move uses wrapping arithmetic in release mode — overflow does not revert but wraps around silently.

### Detection
```bash
# Find arithmetic in financial contexts
rg "balance.*\+|balance.*\-|amount.*\*|value.*\/" sources/
```

### Vulnerable Code
```move
// BAD: No overflow check
let new_balance = balance + deposit;  // Wraps on overflow!

// BAD: No underflow check
let remaining = balance - withdrawal;  // Wraps if withdrawal > balance!
```

### Secure Code
```move
// GOOD: Explicit overflow check
assert!(balance <= MAX_U64 - deposit, EOverflow);
let new_balance = balance + deposit;

// GOOD: Explicit underflow check
assert!(balance >= withdrawal, EInsufficientBalance);
let remaining = balance - withdrawal;
```

---

## M7. Type Confusion / Generic Misuse (HIGH)

### Description
Improper generic constraints allowing unauthorized types to be used where only specific types should be allowed.

### Detection
```bash
rg "<T>" sources/
rg "phantom" sources/
rg "public fun.*<T" sources/
```

### Vulnerable Code
```move
// BAD: No constraints on T — can store capabilities
public struct Box<T> has key {
    id: UID,
    value: T,
}

public entry fun store_anything<T>(value: T, ctx: &mut TxContext) {
    transfer::public_transfer(
        Box { id: object::new(ctx), value },
        tx_context::sender(ctx)
    );
}
```

### Secure Code
```move
// GOOD: Proper constraints
public struct Box<T: store> has key {
    id: UID,
    value: T,
}

// GOOD: Restrict to specific traits
public entry fun store_value<T: store + drop>(value: T, ctx: &mut TxContext) {
    transfer::public_transfer(
        Box { id: object::new(ctx), value },
        tx_context::sender(ctx)
    );
}
```

---

## M8. Missing Event Emission (LOW)

### Description
Critical state changes (transfers, mints, burns, config updates) without event emission, preventing off-chain monitoring and auditing.

### Detection
```bash
rg "sui::event|aptos_std::event|event::emit" sources/
```

### Vulnerable Code
```move
// BAD: Critical transfer with no event
public entry fun transfer(
    _: &AdminCap,
    treasury: &mut Treasury,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    transfer::public_transfer(
        treasury::withdraw(treasury, amount),
        recipient
    );
    // No event emitted!
}
```

### Secure Code
```move
public struct TransferEvent has drop, copy {
    amount: u64,
    recipient: address,
}

public entry fun transfer(
    _: &AdminCap,
    treasury: &mut Treasury,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    event::emit(TransferEvent { amount, recipient });
    transfer::public_transfer(
        treasury::withdraw(treasury, amount),
        recipient
    );
}
```

---

## Vulnerability Classification Summary

| ID | Category | Severity | CV equivalent |
|----|----------|----------|---------------|
| M1 | Improper Abilities | CRITICAL | Integer Overflow, Access Control |
| M2 | Missing Access Control | CRITICAL | Missing Authorization |
| M3 | Witness Pattern Abuse | CRITICAL | Authentication Bypass |
| M4 | Capability Leakage | HIGH | Privilege Escalation |
| M5 | Global Storage Errors | HIGH | Unchecked Return Value |
| M6 | Arithmetic Issues | MEDIUM | Integer Overflow/Underflow |
| M7 | Type Confusion | HIGH | Type Confusion |
| M8 | Missing Events | LOW | Missing Logging |

---

## Safe Patterns Checklist

| Pattern | Check |
|---------|-------|
| Asset struct abilities | No `copy`, no `drop` on asset types |
| Access control | All privileged functions gated by capability or signer check |
| Witness types | Only `drop` ability, only creatable in `init` |
| Capability transfer | Require existing authorization |
| Global storage | `exists` check before `borrow_global` |
| Arithmetic | Explicit bounds checking before operations |
| Generic types | Proper ability constraints |
| Events | Emit for all critical state changes |
