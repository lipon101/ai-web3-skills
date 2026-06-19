# Move Language Reference

This document provides a comprehensive reference for the Move programming language as used in smart contract development on Sui and Aptos.

---

## 1. Module System

Move code is organized into **modules** — the fundamental unit of code organization, similar to contracts in Solidity.

```move
module package_name::module_name {
    // Structs, functions, constants live here
}
```

### Module Rules

- Each module is defined in its own `.move` file
- Module name must match the file name
- A **package** (Move.toml + sources/) contains multiple modules
- Modules can import other modules with `use`

```move
module my_package::coin {
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;

    public struct MYCOIN has drop {} // One-time witness

    fun init(witness: MYCOIN, ctx: &mut TxContext) {
        let (treasury_cap, coin_metadata) = coin::create_currency(
            witness,
            6,           // decimals
            b"MYC",      // symbol
            b"MyCoin",   // name
            b"A test coin",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(coin_metadata);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
    }
}
```

---

## 2. Ability System

Move uses **abilities** to control struct behavior. Four abilities exist:

| Ability | Keyword | Effect |
|---------|---------|--------|
| Copy | `copy` | Values can be duplicated |
| Drop | `drop` | Values can be implicitly discarded |
| Key | `key` | Values can be stored globally (as a key) |
| Store | `store` | Values can be stored inside other structs or in global storage |

### Ability Declaration

```move
// Asset type: no copy, no drop — must be explicitly handled
public struct Coin has key, store {
    id: UID,
    value: u64,
}

// Witness type: only drop — created once, consumed immediately
public struct WITNESS has drop {}

// Capability: key only — stored as a global object
public struct AdminCap has key {
    id: UID,
}

// Data type: all abilities — freely copy and discard
public struct Config has copy, drop, store {
    fee_rate: u64,
    paused: bool,
}
```

### Ability Implications for Security

| Pattern | Risk | Severity |
|---------|------|----------|
| Asset with `copy` | Funds can be duplicated | CRITICAL |
| Asset with `drop` | Funds can be silently lost | CRITICAL |
| Witness with `store` | Can be stored and reused | HIGH |
| Witness with `copy` | Can be duplicated | HIGH |
| Capability with `store` | Can be stored in other objects | Review needed |

### Phantom Types

The `phantom` keyword declares type parameters that don't affect the struct's abilities:

```move
// phantom T is only used as a type marker, not stored
public struct Coin<phantom T> has key, store {
    id: UID,
    value: u64,
}

// Without phantom, T would need to satisfy store ability
// With phantom, Coin<Sui> and Coin<USDC> are different types
// but T doesn't need any abilities
```

---

## 3. Resource Model

Move's resource model is its defining feature: **resources cannot be copied or dropped**. This is enforced at the compiler level.

### Struct Unpacking

```move
// Resources must be explicitly destructured
public entry fun burn(coin: Coin<T>) {
    let Coin { id, value: _ } = coin;
    object::delete(id);
}
```

### Transfer Patterns

```move
// Sui: object transfer
transfer::public_transfer(obj, recipient);
transfer::public_share_object(obj);
transfer::freeze_object(obj);

// Aptos: move_to signer-based storage
move_to<T>(signer, resource);
```

---

## 4. Functions and Visibility

### Visibility Levels

```move
// Private — only callable within this module
fun helper() { }

// Public — callable from any module
public fun get_value(): u64 { }

// Public entry — callable from transactions AND modules
public entry fun user_action(ctx: &mut TxContext) { }

// Entry only — callable from transactions, NOT from modules
entry fun transaction_only(account: &signer) { }

// Sui: package-visible
public(package) fun internal() { }

// Aptos: friend-visible
public(friend) fun for_friends() { }
```

### Function Parameters

```move
// Sui entry functions use TxContext
public entry fun create_object(ctx: &mut TxContext) { }

// Sui functions receive objects as parameters
public entry fun modify(obj: &mut MyObject, value: u64) { }

// Aptos entry functions use &signer
public entry fun create_resource(account: &signer) { }

// Aptos acquires annotation for global storage access
public fun get_data(addr: address): &MyData acquires MyData {
    borrow_global<MyData>(addr)
}
```

---

## 5. Global Storage Operations

### Aptos Global Storage

```move
// Store a resource under an account
move_to<T>(account, resource);

// Check if a resource exists
exists<T>(address);

// Read a resource (immutable)
borrow_global<T>(address): &T

// Read a resource (mutable)
borrow_global_mut<T>(address): &mut T

// Remove a resource
move_from<T>(address): T
```

### Sui Object Storage

```move
// Create a new object
let obj = MyObject { id: object::new(ctx), field: value };

// Transfer to an address (owned)
transfer::public_transfer(obj, recipient);

// Share with everyone
transfer::public_share_object(obj);

// Freeze (immutable)
transfer::freeze_object(obj);

// Dynamic fields
dynamic_field::add(&mut parent.id, name, value);
dynamic_field::borrow(&parent.id, name): &T
dynamic_field::remove(&mut parent.id, name): T
```

---

## 6. Generics

Move supports generics with ability constraints:

```move
// Generic with ability constraint
public fun swap<T: key + store>(a: T, b: T): (T, T) {
    (b, a)
}

// Phantom type parameter
public struct Coin<phantom T> has key, store {
    id: UID,
    value: u64,
}

// Generic struct with store constraint
public struct Box<T: store> has key {
    id: UID,
    contents: T,
}
```

### Generic Type Safety

```move
// DANGEROUS: No constraints — can store anything
public struct UnsafeBox<T> has key {
    id: UID,
    value: T,
}

// SAFE: Proper constraints
public struct SafeBox<T: store> has key {
    id: UID,
    value: T,
}
```

---

## 7. Control Flow

```move
// If-else
if (condition) {
    // branch
} else {
    // branch
};

// While loop
let i = 0;
while (i < 10) {
    i = i + 1;
};

// Loop with break
let sum = 0;
loop {
    if (sum > 100) { break };
    sum = sum + 1;
};

// Match (Move 2024 edition)
match (value) {
    0 => handle_zero(),
    _ => handle_other(),
};
```

---

## 8. Constants and Error Codes

```move
// Constants
const MAX_SUPPLY: u64 = 1_000_000_000;
const DECIMALS: u8 = 9;

// Error constants (used with assert!)
const ENotAuthorized: u64 = 0;
const EInsufficientBalance: u64 = 1;
const EOverflow: u64 = 2;

// Usage
assert!(balance >= amount, EInsufficientBalance);
```

---

## 9. Common Patterns

### Capability Pattern (Sui)

```move
public struct AdminCap has key { id: UID }
public struct Config has key { id: UID, fee_rate: u64 }

public entry fun set_fee(
    _: &AdminCap,        // Must own capability
    config: &mut Config,
    new_rate: u64,
    _ctx: &mut TxContext
) {
    config.fee_rate = new_rate;
}
```

### Signer Validation Pattern (Aptos)

```move
public entry fun admin_action(admin: &signer) acquires Config {
    let addr = signer::address_of(admin);
    let config = borrow_global<Config>(@module_addr);
    assert!(addr == config.admin, ENotAuthorized);
    // ... privileged operation
}
```

### Witness / One-Time Witness Pattern

```move
// OTW: struct name matches module name (uppercase), only has drop
public struct MY_MODULE has drop {}

fun init(otw: MY_MODULE, ctx: &mut TxContext) {
    // OTW can only be created by the Move VM at module publish
    // This ensures init runs exactly once
}
```

### Publisher Pattern (Sui)

```move
fun init(otw: MY_MODULE, ctx: &mut TxContext) {
    // Publisher proves module ownership
    let publisher = publisher::claim(otw, ctx);
    transfer::public_share_object(publisher);
}
```

---

## 10. Testing

```move
#[test_only]
module my_package::my_module_tests {
    use my_package::my_module;

    #[test]
    fun test_basic() {
        // Test code here
    }

    #[test]
    #[expected_failure(abort_code = my_module::ENotAuthorized)]
    fun test_unauthorized() {
        // Should fail with specific error code
    }

    #[test(account = @0x1)]
    fun test_with_signer(account: &signer) {
        // Test with signer
    }
}
```

---

## 11. Primitive Types

| Type | Description | Range |
|------|-------------|-------|
| `bool` | Boolean | `true` / `false` |
| `u8` | 8-bit unsigned | 0 — 255 |
| `u16` | 16-bit unsigned | 0 — 65,535 |
| `u32` | 32-bit unsigned | 0 — 4,294,967,295 |
| `u64` | 64-bit unsigned | 0 — 18,446,744,073,709,551,615 |
| `u128` | 128-bit unsigned | 0 — 2^128-1 |
| `u256` | 256-bit unsigned | 0 — 2^256-1 |
| `address` | Account address | 32 bytes (Sui/Aptos) |
| `vector<T>` | Dynamic array | Variable length |
| `String` | UTF-8 string | Variable length |
| `Option<T>` | Optional value | `some(val)` / `none()` |

### Arithmetic Behavior

- All unsigned types wrap on overflow in release mode
- In debug/test mode, overflow causes abort
- Always use `assert!` for bounds checking in production code
- Move **does not** have built-in checked arithmetic like Solidity's `SafeMath`

```move
// Safe: explicit check
assert!(a <= MAX - b, EOverflow);
let result = a + b;

// Unsafe: wraps silently in release
let result = a + b; // May overflow!
```
