# Aptos-Specific Vulnerabilities

This document details vulnerabilities specific to the Aptos blockchain and its Move implementation.

---

## A1. Signer Validation Bypass

### Description
Missing or improper signer validation allows unauthorized access to account resources and privileged operations.

### Severity
CRITICAL

### Detection Pattern

```bash
# Find signer usage
rg "signer|signer::address_of" sources/
rg "public entry fun.*signer" sources/

# Find missing signer checks
rg "borrow_global_mut.*address" sources/
```

### Vulnerable Code

```move
module vulnerable::wallet {
    struct Wallet has key {
        balance: u64,
    }

    // BAD: No signer validation - anyone can withdraw from any wallet
    public entry fun withdraw(
        account: &signer,
        amount: u64,
        recipient: address
    ) acquires Wallet {
        let addr = signer::address_of(account);
        let wallet = borrow_global_mut<Wallet>(addr);

        // But addr could be anyone - no validation that account owns this wallet!
        wallet.balance = wallet.balance - amount;

        let recipient_wallet = borrow_global_mut<Wallet>(recipient);
        recipient_wallet.balance = recipient_wallet.balance + amount;
    }

    // BAD: Admin function without proper authorization
    public entry fun set_admin(
        admin: &signer,
        config: &mut Config
    ) {
        // No check if admin is actually authorized!
        config.admin = signer::address_of(admin);
    }
}
```

### Attack Scenario

1. Attacker calls `withdraw` with their own signer
2. Function doesn't validate that signer owns the wallet being modified
3. Attacker drains funds from any wallet

### Secure Code

```move
module secure::wallet {
    struct Wallet has key {
        balance: u64,
    }

    struct AdminCapability has key, store {}

    // GOOD: Proper signer validation
    public entry fun withdraw(
        account: &signer,
        amount: u64
    ) acquires Wallet {
        let addr = signer::address_of(account);
        assert!(exists<Wallet>(addr), EWalletNotFound);

        let wallet = borrow_global_mut<Wallet>(addr);
        assert!(wallet.balance >= amount, EInsufficientBalance);

        wallet.balance = wallet.balance - amount;
    }

    // GOOD: Transfer between own wallets
    public entry fun transfer(
        from: &signer,
        to: address,
        amount: u64
    ) acquires Wallet {
        let from_addr = signer::address_of(from);

        let from_wallet = borrow_global_mut<Wallet>(from_addr);
        assert!(from_wallet.balance >= amount, EInsufficientBalance);

        let to_wallet = borrow_global_mut<Wallet>(to);
        from_wallet.balance = from_wallet.balance - amount;
        to_wallet.balance = to_wallet.balance + amount;
    }

    // GOOD: Admin authorization via capability
    public entry fun set_admin(
        admin: &signer,
        config: &mut Config
    ) acquires AdminCapability {
        let admin_addr = signer::address_of(admin);
        assert!(
            exists<AdminCapability>(admin_addr),
            ENotAuthorized
        );
        config.admin = admin_addr;
    }
}
```

---

## A2. Account Resource Abuse

### Description
Aptos allows storing resources under any account. Improper access control can allow unauthorized resource manipulation.

### Severity
HIGH

### Detection Pattern

```bash
# Find move_to operations
rg "move_to|move_from" sources/
rg "borrow_global" sources/
```

### Vulnerable Code

```move
module vulnerable::game {
    struct PlayerData has key {
        score: u64,
        items: vector<Item>,
    }

    // BAD: Anyone can initialize player data for any address
    public entry fun init_player(
        account: &signer,
        target: address  // Could be anyone
    ) {
        move_to<PlayerData>(account, PlayerData {
            score: 0,
            items: vector::empty(),
        });
    }

    // BAD: Resource stored under wrong account
    struct GameConfig has key {
        admin: address,
        paused: bool,
    }

    public entry fun init_config(admin: &signer) {
        // Config should be under module address, not admin
        move_to<GameConfig>(admin, GameConfig {
            admin: signer::address_of(admin),
            paused: false,
        });
    }
}
```

### Secure Code

```move
module secure::game {
    struct PlayerData has key {
        score: u64,
        items: vector<Item>,
    }

    struct GameConfig has key {
        admin: address,
        paused: bool,
    }

    // GOOD: Player initializes their own data
    public entry fun init_player(account: &signer) {
        let addr = signer::address_of(account);
        assert!(!exists<PlayerData>(addr), EAlreadyInitialized);

        move_to<PlayerData>(account, PlayerData {
            score: 0,
            items: vector::empty(),
        });
    }

    // GOOD: Config under signer's address, validated
    public entry fun init_config(admin: &signer) {
        let addr = signer::address_of(admin);
        assert!(!exists<GameConfig>(addr), EAlreadyInitialized);

        move_to<GameConfig>(admin, GameConfig {
            admin: addr,
            paused: false,
        });
    }

    // GOOD: Only admin can modify config
    public entry fun set_paused(
        admin: &signer,
        paused: bool
    ) acquires GameConfig {
        let addr = signer::address_of(admin);
        let config = borrow_global_mut<GameConfig>(addr);

        assert!(config.admin == addr, ENotAuthorized);
        config.paused = paused;
    }
}
```

---

## A3. Event Handle Manipulation

### Description
Missing or forged events that affect off-chain monitoring and indexing.

### Severity
MEDIUM

### Detection Pattern

```bash
# Find event usage
rg "event::emit|emit_event" sources/
rg "EventHandle" sources/
```

### Vulnerable Code

```move
module vulnerable::token {
    struct TransferEvent has drop, store {
        from: address,
        to: address,
        amount: u64,
    }

    // BAD: No event for critical transfer
    public entry fun transfer(
        from: &signer,
        to: address,
        amount: u64
    ) acquires Balance {
        let from_addr = signer::address_of(from);

        let from_balance = borrow_global_mut<Balance>(from_addr);
        let to_balance = borrow_global_mut<Balance>(to);

        from_balance.value = from_balance.value - amount;
        to_balance.value = to_balance.value + amount;

        // No event emitted!
    }

    // BAD: Incorrect event data
    public entry fun transfer_with_event(
        from: &signer,
        to: address,
        amount: u64
    ) acquires Balance, EventStore {
        // ... transfer logic ...

        let event_store = borrow_global_mut<EventStore>(
            @vulnerable::token
        );
        event::emit_event(&mut event_store.transfer_events, TransferEvent {
            from: to,      // WRONG: swapped
            to: from_addr, // WRONG: swapped
            amount: 0,     // WRONG: hidden amount
        });
    }
}
```

### Secure Code

```move
module secure::token {
    use aptos_std::event::{Self, EventHandle};

    struct TransferEvent has drop, store {
        from: address,
        to: address,
        amount: u64,
        timestamp: u64,
    }

    struct EventStore has key {
        transfer_events: EventHandle<TransferEvent>,
    }

    // GOOD: Emit correct event for all transfers
    public entry fun transfer(
        from: &signer,
        to: address,
        amount: u64
    ) acquires Balance, EventStore {
        let from_addr = signer::address_of(from);

        let from_balance = borrow_global_mut<Balance>(from_addr);
        let to_balance = borrow_global_mut<Balance>(to);

        assert!(from_balance.value >= amount, EInsufficientBalance);

        from_balance.value = from_balance.value - amount;
        to_balance.value = to_balance.value + amount;

        // Emit correct event
        let event_store = borrow_global_mut<EventStore>(@secure::token);
        event::emit_event(&mut event_store.transfer_events, TransferEvent {
            from: from_addr,
            to: to,
            amount: amount,
            timestamp: timestamp::now_seconds(),
        });
    }
}
```

---

## A4. Coin/FungibleAsset Vulnerabilities

### Description
Improper handling of Aptos Coin and FungibleAsset types leading to loss of funds or unauthorized minting.

### Severity
HIGH

### Detection Pattern

```bash
# Find coin operations
rg "coin::|aptos_framework::coin" sources/
rg "fungible_asset::" sources/
rg "mint|burn|withdraw|deposit" sources/
```

### Vulnerable Code

```move
module vulnerable::token {
    use aptos_framework::coin::{Self, Coin};

    // BAD: Unchecked mint
    public entry fun mint_tokens(
        account: &signer,
        amount: u64,
        recipient: address
    ) acquires MintCapabilityStore {
        let minter = signer::address_of(account);
        let cap_store = borrow_global<MintCapabilityStore>(minter);

        // No amount limit check!
        let coins = coin::mint(amount, &cap_store.mint_cap);

        coin::deposit(recipient, coins);
    }

    // BAD: Withdraw from wrong account
    public entry fun withdraw_to(
        account: &signer,
        from: address,  // Not validated against account
        amount: u64
    ): Coin<TOKEN> {
        let _ = signer::address_of(account); // Unused!
        coin::withdraw<TOKEN>(from, amount)
    }
}
```

### Attack Scenario

1. Attacker calls `mint_tokens` with large amount
2. No limit check, unlimited tokens minted
3. Attacker drains liquidity pools

### Secure Code

```move
module secure::token {
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, MintRef, BurnRef};

    struct MintLimits has key {
        daily_limit: u64,
        minted_today: u64,
        last_reset: u64,
    }

    // GOOD: Rate-limited minting
    public entry fun mint_tokens(
        account: &signer,
        amount: u64,
        recipient: address
    ) acquires MintCapabilityStore, MintLimits {
        let minter = signer::address_of(account);
        assert!(exists<MintCapabilityStore>(minter), ENotAuthorized);

        // Check rate limits
        let limits = borrow_global_mut<MintLimits>(@secure::token);
        let now = timestamp::now_seconds();

        if (now - limits.last_reset >= 86400) {
            limits.minted_today = 0;
            limits.last_reset = now;
        };

        assert!(
            limits.minted_today + amount <= limits.daily_limit,
            EExceedsLimit
        );
        limits.minted_today = limits.minted_today + amount;

        let cap_store = borrow_global<MintCapabilityStore>(minter);
        let coins = coin::mint(amount, &cap_store.mint_cap);

        coin::deposit(recipient, coins);
    }

    // GOOD: Only withdraw from own account
    public entry fun withdraw(
        account: &signer,
        amount: u64
    ): Coin<TOKEN> {
        let addr = signer::address_of(account);
        coin::withdraw<TOKEN>(addr, amount)
    }

    // GOOD: FungibleAsset pattern (Aptos standard)
    public entry fun mint_fa(
        account: &signer,
        ref: &MintRef,
        amount: u64,
        recipient: address
    ) {
        assert!(amount <= MAX_MINT_AMOUNT, EExceedsLimit);

        let fa = fungible_asset::mint(ref, amount);
        fungible_asset::deposit(recipient, fa);
    }
}
```

---

## A5. Table and Smart Vector Issues

### Description
Improper use of Aptos Table and SmartVector leading to DoS or state manipulation.

### Severity
MEDIUM

### Detection Pattern

```bash
# Find table usage
rg "table::|aptos_std::table" sources/
rg "smart_vector::" sources/
```

### Vulnerable Code

```move
module vulnerable::registry {
    use aptos_std::table::{Self, Table};

    struct Registry has key {
        entries: Table<address, Entry>,
    }

    // BAD: No size limit - can grow unbounded
    public entry fun add_entry(
        account: &signer,
        registry: &mut Registry
    ) {
        let addr = signer::address_of(account);
        table::add(&mut registry.entries, addr, Entry {
            data: vector::empty(),
        });
    }

    // BAD: Table can be spammed, causing DoS
    public entry fun iterate_all(
        registry: &Registry
    ) {
        // Iteration becomes slow with many entries
        let len = table::length(&registry.entries);
        // ... slow iteration
    }
}
```

### Secure Code

```move
module secure::registry {
    use aptos_std::table::{Self, Table};
    use aptos_std::smart_vector::{Self, SmartVector};

    const MAX_ENTRIES: u64 = 10000;

    struct Registry has key {
        entries: Table<address, Entry>,
        entry_count: u64,
    }

    // GOOD: Size-limited registry
    public entry fun add_entry(
        account: &signer,
        registry: &mut Registry
    ) acquires Registry {
        let addr = signer::address_of(account);

        assert!(
            registry.entry_count < MAX_ENTRIES,
            ERegistryFull
        );

        assert!(
            !table::contains(&registry.entries, addr),
            EAlreadyExists
        );

        table::add(&mut registry.entries, addr, Entry {
            data: vector::empty(),
        });

        registry.entry_count = registry.entry_count + 1;
    }

    // GOOD: Use SmartVector for bounded collections
    struct BoundedRegistry has key {
        entries: SmartVector<address, Entry>,
    }

    public entry fun add_bounded(
        account: &signer,
        registry: &mut BoundedRegistry
    ) {
        let addr = signer::address_of(account);

        smart_vector::push_back(
            &mut registry.entries,
            addr,
            Entry { data: vector::empty() }
        );
    }
}
```

---

## A6. Multi-Signature and Auth Key Issues

### Description
Improper handling of Aptos authentication keys and multi-signature schemes.

### Severity
MEDIUM

### Detection Pattern

```bash
# Find multisig patterns
rg "multisig|MultiSig" sources/
rg "authentication_key" sources/
```

### Vulnerable Code

```move
module vulnerable::multisig {
    struct Wallet has key {
        owners: vector<address>,
        threshold: u64,
        pending_tx: vector<PendingTx>,
    }

    // BAD: Threshold can be changed without proper validation
    public entry fun change_threshold(
        signer: &signer,
        wallet: &mut Wallet,
        new_threshold: u64
    ) {
        // No validation that signer is an owner!
        wallet.threshold = new_threshold;
    }

    // BAD: Replay attack possible
    public entry fun execute_tx(
        wallet: &mut Wallet,
        tx_hash: vector<u8>,
        signatures: vector<Signature>
    ) {
        // No nonce/check to prevent replay
        assert!(
            verify_signatures(wallet, tx_hash, signatures),
            EInvalidSignatures
        );
        execute(wallet, tx_hash);
    }
}
```

### Secure Code

```move
module secure::multisig {
    struct Wallet has key {
        owners: vector<address>,
        threshold: u64,
        nonce: u64,  // GOOD: Replay protection
        pending_tx: Table<u64, PendingTx>,
    }

    // GOOD: Only owners can change threshold
    public entry fun change_threshold(
        signer: &signer,
        wallet_addr: address,
        new_threshold: u64
    ) acquires Wallet {
        let signer_addr = signer::address_of(signer);
        let wallet = borrow_global_mut<Wallet>(wallet_addr);

        // Verify signer is an owner
        assert!(is_owner(wallet, signer_addr), ENotOwner);

        // Validate new threshold
        assert!(new_threshold > 0, EInvalidThreshold);
        assert!(
            new_threshold <= vector::length(&wallet.owners),
            EThresholdTooHigh
        );

        wallet.threshold = new_threshold;
    }

    // GOOD: Nonce-based replay protection
    public entry fun execute_tx(
        wallet_addr: address,
        tx: PendingTx,
        signatures: vector<Signature>
    ) acquires Wallet {
        let wallet = borrow_global_mut<Wallet>(wallet_addr);

        // Include nonce in hash
        let tx_hash = hash_tx(wallet.nonce, &tx);

        assert!(
            verify_signatures(&wallet.owners, wallet.threshold, tx_hash, signatures),
            EInvalidSignatures
        );

        // Increment nonce
        wallet.nonce = wallet.nonce + 1;

        execute(&mut wallet, tx);
    }

    fun is_owner(wallet: &Wallet, addr: address): bool {
        let i = 0;
        let len = vector::length(&wallet.owners);
        while (i < len) {
            if (*vector::borrow(&wallet.owners, i) == addr) {
                return true
            };
            i = i + 1;
        };
        false
    }
}
```

---

## Aptos Security Best Practices

### 1. Signer Validation Pattern

```move
// Always validate signer for privileged operations
public entry fun privileged_op(signer: &signer) {
    let addr = signer::address_of(signer);
    assert!(is_authorized(addr), ENotAuthorized);
    // ... operation
}
```

### 2. Resource Storage Pattern

```move
// Store resources under appropriate addresses
// - User data: under user's address
// - Global config: under module/deployer address
struct GlobalConfig has key { ... }

// Initialize under deployer
fun init_module(admin: &signer) {
    move_to<GlobalConfig>(admin, GlobalConfig { ... });
}
```

### 3. Event Emission Pattern

```move
// Emit events for all state changes
struct TransferEvent has drop, store { ... }

public entry fun transfer(...) acquires EventStore {
    // ... state change ...

    event::emit_event(&mut event_store.events, TransferEvent {
        // accurate data
    });
}
```

### 4. Coin/FA Pattern

```move
// Use FungibleAsset for new tokens
// Use rate limiting for minting
// Always validate withdraw addresses
```

### 5. Testing Pattern

```move
#[test(admin = @0x1, user = @0x2)]
fun test_access_control(admin: signer, user: signer) {
    // Test admin can access
    privileged_op(&admin);

    // Test user cannot access
    assert!(fails_with(ENotAuthorized, || {
        privileged_op(&user);
    }), 0);
}
```

---

## Summary Checklist

| Check | Description |
|-------|-------------|
| Signer Validation | All privileged ops verify signer |
| Resource Storage | Resources under correct addresses |
| Events | All state changes emit events |
| Coin/FA Operations | Rate-limited, authorized minting |
| Table/Vector | Bounded sizes, DoS protection |
| Multi-sig | Nonce-based replay protection |
