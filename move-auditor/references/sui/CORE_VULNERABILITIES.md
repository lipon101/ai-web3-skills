#  Core Move Vulnerabilities

This document details core Move language vulnerabilities that apply across all Move-based blockchains.

---

## 1. Improper Resource Abilities

### Description
Move's ability system (`copy`, `drop`, `key`, `store`) controls how structs behave. Incorrect abilities on asset types can lead to duplication or loss of funds.

### Severity
CRITICAL

### Detection Pattern

```bash
# Find structs representing assets/value
rg "public struct.*Coin|public struct.*Token|public struct.*Asset" sources/
rg "has.*(copy|drop)" sources/
```

### Vulnerable Code

```move
// BAD: Coin can be duplicated
public struct Coin has key, store, copy {
    value: u64,
}

// BAD: Coin can be silently dropped (lost)
public struct Coin has key, store, drop {
    value: u64,
}

// BAD: Both issues combined
public struct Token has key, store, copy, drop {
    amount: u64,
}
```

### Attack Scenario

1. **Copy Attack**: User creates a coin, copies it, and spends both copies
2. **Drop Attack**: User receives payment, but coins are accidentally dropped, losing value

### Secure Code

```move
// GOOD: Asset without copy or drop - must be explicitly handled
public struct Coin has key, store {
    value: u64,
}

// For burning, create explicit function
public entry fun burn(coin: Coin, _ctx: &mut TxContext) {
    let Coin { value: _ } = coin;
    // Coin is consumed, value is burned
}
```

### Testing

```move
#[test]
#[expected_failure]
fun test_cannot_copy_coin() {
    let coin = Coin { value: 100 };
    let copy = coin; // This should fail to compile if copy is not allowed
}
```

---

## 2. Missing Access Control

### Description
Public or entry functions without proper authorization checks allow unauthorized operations.

### Severity
CRITICAL

### Detection Pattern

```bash
# Find entry and public functions
rg "public entry fun|public fun" sources/

# Check for capability/signer parameters
rg "public entry fun.*\(" sources/ | grep -v "Cap\|signer"
```

### Vulnerable Code

```move
module vulnerable::admin {
    public struct AdminCap has key { id: UID }
    public struct Config has key {
        id: UID,
        fee_rate: u64,
        paused: bool,
    }

    // BAD: Anyone can change fee rate
    public entry fun set_fee_rate(
        config: &mut Config,
        new_rate: u64,
        _ctx: &mut TxContext
    ) {
        config.fee_rate = new_rate;
    }

    // BAD: Anyone can pause the contract
    public entry fun emergency_pause(
        config: &mut Config,
        _ctx: &mut TxContext
    ) {
        config.paused = true;
    }

    // BAD: Anyone can mint tokens
    public entry fun mint(
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(
            Coin { id: object::new(ctx), value: amount },
            recipient
        );
    }
}
```

### Attack Scenario

1. Attacker identifies unprotected `set_fee_rate` function
2. Attacker sets fee rate to 0
3. Attacker uses protocol without fees
4. Protocol loses all fee revenue

### Secure Code

```move
module secure::admin {
    public struct AdminCap has key { id: UID }
    public struct Config has key {
        id: UID,
        fee_rate: u64,
        paused: bool,
    }

    // GOOD: Requires admin capability
    public entry fun set_fee_rate(
        _: &AdminCap,  // Capability check
        config: &mut Config,
        new_rate: u64,
        _ctx: &mut TxContext
    ) {
        assert!(new_rate <= 10000, EInvalidRate); // Max 100%
        config.fee_rate = new_rate;
    }

    // GOOD: Requires admin capability
    public entry fun emergency_pause(
        _: &AdminCap,
        config: &mut Config,
        _ctx: &mut TxContext
    ) {
        config.paused = true;
    }

    // GOOD: Requires minter capability
    public entry fun mint(
        _: &MinterCap,
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
}
```

### Testing

```move
#[test_only]
module secure::admin_tests {
    use secure::admin;

    #[test]
    #[expected_failure(abort_code = admin::ENotAuthorized)]
    fun test_unauthorized_fee_change() {
        // Create config but no capability
        let config = admin::create_test_config();
        admin::set_fee_rate(&mut config, 500); // Should fail
    }

    #[test]
    fun test_authorized_fee_change() {
        let (cap, config) = admin::create_test_setup();
        admin::set_fee_rate(&cap, &mut config, 500);
        assert!(config.fee_rate == 500, 0);
    }
}
```

---

## 3. Witness Pattern Abuse

### Description
Witness pattern used incorrectly, allowing unauthorized type creation or token minting.

### Severity
CRITICAL

### Detection Pattern

```bash
# Find witness-related patterns
rg "Witness|witness" sources/
rg "public struct.*has drop" sources/
rg "ensure!|assert!.*witness" sources/
```

### Vulnerable Code

```move
module vulnerable::token {
    // BAD: Witness can be created anywhere
    public struct Witness has drop {}

    public fun create_collection(_: Witness, ctx: &mut TxContext) {
        // Create collection
    }

    public entry fun create_token(
        _: Witness,
        name: String,
        ctx: &mut TxContext
    ) {
        // Anyone can create this witness and call the function
        let witness = Witness {};
        create_collection(witness, ctx);
    }
}

// BAD: Witness with wrong abilities
module vulnerable::token2 {
    // Witness should only have drop
    public struct Witness has drop, store, copy {}

    public fun mint(_: Witness, amount: u64, ctx: &mut TxContext): Coin {
        Coin { id: object::new(ctx), value: amount }
    }
}
```

### Attack Scenario

1. Attacker sees Witness type with `drop` only but can be created publicly
2. Attacker creates Witness instance
3. Attacker calls mint function with forged witness
4. Attacker mints unlimited tokens

### Secure Code

```move
module secure::token {
    // GOOD: One-time witness (OTW) - can only be created at module init
    public struct WITNESS has drop {}

    // Only called once during module publish
    fun init(witness: WITNESS, ctx: &mut TxContext) {
        // Create collection with witness
        create_collection(witness, ctx);
    }

    // GOOD: Witness is passed as parameter, not creatable by users
    public fun mint(
        _: &mut WITNESS,  // Cannot be created by users
        amount: u64,
        ctx: &mut TxContext
    ): Coin {
        Coin { id: object::new(ctx), value: amount }
    }

    // Alternative: Use Publisher capability from Sui framework
    public fun mint_with_publisher(
        _: &Publisher,
        amount: u64,
        ctx: &mut TxContext
    ): Coin {
        // Publisher proves module ownership
        Coin { id: object::new(ctx), value: amount }
    }
}
```

### Testing

```move
#[test_only]
module secure::token_tests {
    use secure::token;

    #[test]
    #[expected_failure]
    fun test_cannot_create_witness() {
        // This should fail to compile - cannot create WITNESS outside module
        let witness = token::WITNESS {};
    }
}
```

---

## 4. Capability Leakage

### Description
Capabilities (admin, minter, etc.) transferred to unauthorized parties.

### Severity
HIGH

### Detection Pattern

```bash
# Find capability transfers
rg "transfer.*Cap" sources/
rg "public_transfer.*Cap" sources/

# Find capability creation
rg "AdminCap|MinterCap|OwnerCap" sources/
```

### Vulnerable Code

```move
module vulnerable::caps {
    public struct AdminCap has key { id: UID }

    // BAD: Anyone can claim admin capability
    public entry fun claim_admin_cap(
        recipient: address,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(
            AdminCap { id: object::new(ctx) },
            recipient
        );
    }

    // BAD: Capability can be redirected by any holder
    public entry fun transfer_admin_cap(
        cap: AdminCap,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(cap, new_owner);
    }
}
```

### Attack Scenario

1. Attacker calls `claim_admin_cap` with their address
2. Attacker now has admin privileges
3. Attacker drains protocol funds or modifies critical parameters

### Secure Code

```move
module secure::caps {
    public struct AdminCap has key { id: UID }
    public struct CapState has key {
        id: UID,
        admin: address,
    }

    // GOOD: Only at module init, admin cap goes to publisher
    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(
            AdminCap { id: object::new(ctx) },
            tx_context::sender(ctx)
        );
    }

    // GOOD: Require existing admin to transfer
    public entry fun transfer_admin_cap(
        _: &AdminCap,  // Must already have admin cap
        cap: AdminCap,
        new_admin: address,
        _ctx: &mut TxContext
    ) {
        transfer::public_transfer(cap, new_admin);
    }

    // GOOD: Multi-sig or timelock for sensitive operations
    public entry fun transfer_admin_with_delay(
        _: &AdminCap,
        _: &Timelock,
        cap: AdminCap,
        new_admin: address,
        _ctx: &mut TxContext
    ) {
        transfer::public_transfer(cap, new_admin);
    }
}
```

---

## 5. Improper Global Storage Access

### Description
Unchecked `borrow_global`, `borrow_global_mut`, or missing `acquires` leading to runtime errors or unexpected behavior.

### Severity
HIGH

### Detection Pattern

```bash
# Find global storage operations
rg "borrow_global|move_to|move_from|exists" sources/
rg "acquires" sources/
```

### Vulnerable Code

```move
module vulnerable::storage {
    public struct Balance has key { value: u64 }

    // BAD: No check if balance exists
    public entry fun withdraw(account: &mut signer, amount: u64): Balance {
        let addr = signer::address_of(account);
        // Will abort if Balance doesn't exist
        let balance = borrow_global_mut<Balance>(addr);
        assert!(balance.value >= amount, EInsufficientBalance);
        balance.value = balance.value - amount;
        Balance { value: amount }
    }

    // BAD: Race condition potential
    public entry fun transfer(from: &mut signer, to: address, amount: u64) {
        let addr = signer::address_of(from);
        let balance = borrow_global_mut<Balance>(addr);

        // Between this and the next borrow_global_mut, state could change
        // in concurrent transactions

        let dest = borrow_global_mut<Balance>(to);
        balance.value = balance.value - amount;
        dest.value = dest.value + amount;
    }
}
```

### Secure Code

```move
module secure::storage {
    public struct Balance has key { value: u64 }

    // GOOD: Check existence first
    public entry fun withdraw(account: &mut signer, amount: u64): Balance {
        let addr = signer::address_of(account);
        assert!(exists<Balance>(addr), EBalanceNotFound);

        let balance = borrow_global_mut<Balance>(addr);
        assert!(balance.value >= amount, EInsufficientBalance);
        balance.value = balance.value - amount;

        Balance { value: amount }
    }

    // GOOD: Atomic transfer with proper checks
    public entry fun transfer(from: &mut signer, to: address, amount: u64) acquires Balance {
        let addr = signer::address_of(from);

        // Check both exist
        assert!(exists<Balance>(addr), EBalanceNotFound);
        assert!(exists<Balance>(to), EDestNotFound);

        // Atomic borrow and modify
        let (src_balance, dest_balance) = (
            borrow_global_mut<Balance>(addr),
            borrow_global_mut<Balance>(to)
        );

        assert!(src_balance.value >= amount, EInsufficientBalance);

        src_balance.value = src_balance.value - amount;
        dest_balance.value = dest_balance.value + amount;
    }

    // GOOD: Initialize balance if not exists
    public entry fun deposit(account: &mut signer, balance: Balance) acquires Balance {
        let addr = signer::address_of(account);

        if (!exists<Balance>(addr)) {
            move_to(account, Balance { value: 0 });
        };

        let global = borrow_global_mut<Balance>(addr);
        let Balance { value } = balance;
        global.value = global.value + value;
    }
}
```

---

## 6. Arithmetic Issues

### Description
Overflow/underflow in calculations, especially in financial operations.

### Severity
MEDIUM

### Detection Pattern

```bash
# Find arithmetic operations
rg "\+|\-|\*" sources/
rg "checked_|saturating_" sources/
```

### Vulnerable Code

```move
module vulnerable::math {
    // BAD: Unchecked arithmetic
    public entry fun add_balance(
        balance: &mut Balance,
        amount: u64
    ) {
        balance.value = balance.value + amount; // Can overflow
    }

    // BAD: Subtraction without check
    public entry fun subtract(
        balance: &mut Balance,
        amount: u64
    ) {
        balance.value = balance.value - amount; // Can underflow
    }
}
```

### Secure Code

```move
module secure::math {
    // GOOD: Use checked arithmetic
    public entry fun add_balance(
        balance: &mut Balance,
        amount: u64
    ) {
        let new_value = balance.value + amount;
        assert!(new_value >= balance.value, EOverflow); // Overflow check
        balance.value = new_value;
    }

    // GOOD: Explicit bounds checking
    public entry fun subtract(
        balance: &mut Balance,
        amount: u64
    ) {
        assert!(balance.value >= amount, EUnderflow);
        balance.value = balance.value - amount;
    }

    // GOOD: Use safe math library
    public entry fun safe_add(
        balance: &mut Balance,
        amount: u64
    ) {
        balance.value = safe_math::add(balance.value, amount);
    }
}
```

---

## 7. Type Confusion

### Description
Improper use of generics or type casting leading to type confusion vulnerabilities.

### Severity
HIGH

### Detection Pattern

```bash
# Find generic usage
rg "T:|phantom|drop.*T" sources/
```

### Vulnerable Code

```move
module vulnerable::generics {
    // BAD: Improper generic constraints
    public struct Box<T> has key, store {
        value: T,
    }

    // Can store any type, including capabilities
    public entry fun store<T>(value: T, ctx: &mut TxContext) {
        transfer::public_transfer(
            Box { value },
            tx_context::sender(ctx)
        );
    }
}
```

### Secure Code

```move
module secure::generics {
    // GOOD: Proper constraints on generic types
    public struct Box<T: store> has key {
        id: UID,
        value: T,
    }

    // GOOD: Restrict what can be stored
    public entry fun store<T: store + drop>(
        value: T,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(
            Box { id: object::new(ctx), value },
            tx_context::sender(ctx)
        );
    }

    // GOOD: Use phantom for type markers without storing
    public struct Coin<phantom T> has key, store {
        id: UID,
        value: u64,
    }
}
```

---

## 8. Event Emission Issues

### Description
Missing, incorrect, or misleading event emissions that affect off-chain monitoring and auditing.

### Severity
LOW

### Detection Pattern

```bash
# Find event emissions
rg "sui::event|aptos::event|emit_event" sources/
```

### Vulnerable Code

```move
module vulnerable::events {
    // BAD: No events emitted for critical operations
    public entry fun transfer(
        _: &AdminCap,
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // Critical transfer with no event
        transfer::public_transfer(
            treasury::withdraw(treasury, amount),
            recipient
        );
    }
}
```

### Secure Code

```move
module secure::events {
    use sui::event;

    public struct TransferEvent has drop, copy {
        from: address,
        to: address,
        amount: u64,
        timestamp: u64,
    }

    // GOOD: Emit events for all critical operations
    public entry fun transfer(
        _: &AdminCap,
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        event::emit(TransferEvent {
            from: sender,
            to: recipient,
            amount,
            timestamp: tx_context::timestamp(ctx),
        });

        transfer::public_transfer(
            treasury::withdraw(treasury, amount),
            recipient
        );
    }
}
```

---

## Summary Checklist

| Category | Check |
|----------|-------|
| Resource Abilities | Assets lack `copy` and `drop` |
| Access Control | All sensitive functions require capability |
| Witness Pattern | Witness types have only `drop` |
| Capability Leakage | Capabilities require existing auth to transfer |
| Global Storage | Check `exists` before `borrow_global` |
| Arithmetic | Use checked arithmetic for financial ops |
| Type Safety | Proper generic constraints |
| Events | Emit events for critical operations |
