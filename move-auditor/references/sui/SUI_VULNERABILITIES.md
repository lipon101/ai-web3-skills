# Sui-Specific Vulnerabilities

This document details vulnerabilities specific to the Sui blockchain and its unique features.

---

## S1. Object Ownership Bypass

### Description
Sui's object model allows flexible ownership, but improper access control can allow unauthorized object manipulation or transfer.

### Severity
CRITICAL

### Detection Pattern

```bash
# Find object definitions and transfers
rg "public struct.*has key" sources/
rg "sui::transfer::public_transfer|transfer::transfer" sources/
rg "sui::object::new" sources/
```

### Vulnerable Code

```move
module vulnerable::vault {
    public struct Vault has key {
        id: UID,
        balance: Balance<CoinType>,
        owner: address,
    }

    // BAD: Anyone can transfer any vault
    public entry fun transfer_vault(
        vault: Vault,
        new_owner: address,
        _ctx: &mut TxContext
    ) {
        transfer::public_transfer(vault, new_owner);
    }

    // BAD: Owner check in wrong place
    public entry fun withdraw(
        vault: &mut Vault,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        // No check if caller is owner!
        balance::withdraw(&mut vault.balance, amount)
    }
}
```

### Attack Scenario

1. Attacker identifies `transfer_vault` function
2. Attacker calls function with victim's vault object
3. Vault is transferred to attacker
4. Attacker drains all funds

### Secure Code

```move
module secure::vault {
    public struct Vault has key {
        id: UID,
        balance: Balance<CoinType>,
    }

    public struct VaultOwnerCap has key { id: UID, vault_id: ID }

    // GOOD: Only owner with capability can transfer
    public entry fun transfer_vault(
        _: &VaultOwnerCap,
        vault: Vault,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(vault, new_owner);
    }

    // GOOD: Capability-based access control
    public entry fun withdraw(
        _: &VaultOwnerCap,
        vault: &mut Vault,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        balance::withdraw(&mut vault.balance, amount)
    }

    // Initialize with capability pattern
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let vault = Vault {
            id: object::new(ctx),
            balance: balance::zero(),
        };
        let vault_id = object::id(&vault);

        transfer::public_transfer(vault, sender);
        transfer::public_transfer(
            VaultOwnerCap { id: object::new(ctx), vault_id },
            sender
        );
    }
}
```

---

## S2. Shared Object Manipulation

### Description
Shared objects in Sui can be accessed concurrently, leading to race conditions and unexpected state changes.

### Severity
CRITICAL

### Detection Pattern

```bash
# Find shared objects
rg "public_share_object|shared_object" sources/
rg "sui::transfer::share_object" sources/
```

### Vulnerable Code

```move
module vulnerable::marketplace {
    public struct Listing has key {
        id: UID,
        price: u64,
        seller: address,
        item: Option<Item>,
    }

    // BAD: Race condition on shared listing
    public entry fun buy(
        listing: &mut Listing,
        payment: Coin<SUI>,
        buyer: address,
        ctx: &mut TxContext
    ) {
        let price = listing.price;
        assert!(coin::value(&payment) >= price, EInsufficientPayment);

        // Race condition: Multiple buyers could reach here simultaneously
        let item = option::extract(&mut listing.item);

        // Payment and transfer happen after item extraction
        // But another transaction might have already taken the item

        transfer::public_transfer(item, buyer);
        transfer::public_transfer(payment, listing.seller);
    }
}
```

### Attack Scenario

1. Item listed for 100 SUI
2. Buyer A starts transaction, passes price check
3. Buyer B starts transaction, passes price check
4. Both transactions extract the item
5. One gets item, one gets nothing but still pays

### Secure Code

```move
module secure::marketplace {
    public struct Listing has key {
        id: UID,
        price: u64,
        seller: address,
        item: Option<Item>,
        sold: bool,  // GOOD: Track sale status
    }

    public entry fun buy(
        listing: &mut Listing,
        payment: Coin<SUI>,
        buyer: address,
        ctx: &mut TxContext
    ) {
        assert!(!listing.sold, EAlreadySold);
        assert!(option::is_some(&listing.item), EAlreadySold);

        let price = listing.price;
        assert!(coin::value(&payment) >= price, EInsufficientPayment);

        // GOOD: Mark as sold before extraction
        listing.sold = true;

        let item = option::extract(&mut listing.item);

        transfer::public_transfer(item, buyer);
        transfer::public_transfer(payment, listing.seller);
    }

    // BETTER: Use Kiosk for atomic trades
    // See S3 for Kiosk pattern
}
```

---

## S3. Kiosk Exploitation

### Description
Sui Kiosk provides a secure trading mechanism, but improper implementation can bypass its protections.

### Severity
HIGH

### Detection Pattern

```bash
# Find kiosk usage
rg "sui::kiosk" sources/
rg "kiosk::purchase|kiosk::list" sources/
```

### Vulnerable Code

```move
module vulnerable::kiosk_trade {
    use sui::kiosk::{Self, Kiosk};

    // BAD: Missing purchase validation
    public entry fun purchase_from_kiosk(
        kiosk: &mut Kiosk,
        item_id: ID,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // No check if item is actually listed for this price
        let item = kiosk::purchase(kiosk, item_id, payment);
        transfer::public_transfer(item, tx_context::sender(ctx));
    }

    // BAD: Bypassing kiosk entirely
    public entry fun direct_transfer(
        item: Item,
        recipient: address,
        _ctx: &mut TxContext
    ) {
        // Item should only be transferred through kiosk
        transfer::public_transfer(item, recipient);
    }
}
```

### Secure Code

```move
module secure::kiosk_trade {
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};

    public struct Item has key, store { id: UID, rarity: u8 }
    public struct ItemPolicy has key { id: UID }

    // GOOD: Proper kiosk purchase with policy
    public entry fun purchase_from_kiosk(
        kiosk: &mut Kiosk,
        item_id: ID,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let (item, receipt) = kiosk::purchase(kiosk, item_id, payment);

        // Validate purchase through policy
        let policy = object::borrow_global<ItemPolicy>(
            tx_context::sender(ctx)
        );
        validate_purchase(policy, &item);

        kiosk::finalize_purchase(kiosk, receipt, sui::kiosk::prove_purchase());
        transfer::public_transfer(item, tx_context::sender(ctx));
    }

    // GOOD: Item can only be placed in kiosk
    fun init(ctx: &mut TxContext) {
        let (kiosk, kiosk_owner_cap) = kiosk::new(ctx);
        let policy = ItemPolicy { id: object::new(ctx) };

        transfer::public_transfer(kiosk, tx_context::sender(ctx));
        transfer::public_transfer(kiosk_owner_cap, tx_context::sender(ctx));
        transfer::share_object(policy);
    }
}
```

---

## S4. PTB (Programmable Transaction Block) Composition Attacks

### Description
PTBs allow composing multiple operations, which can be exploited to create unintended transaction flows.

### Severity
HIGH

### Detection Pattern

```bash
# Find functions that could be composed maliciously
rg "public entry fun" sources/
rg "public fun.*returns" sources/
```

### Vulnerable Code

```move
module vulnerable::lending {
    public struct Position has key {
        id: UID,
        collateral: Coin<SUI>,
        borrowed: Balance<USDC>,
    }

    // BAD: Separate functions can be composed maliciously
    public entry fun deposit_collateral(
        position: &mut Position,
        collateral: Coin<SUI>
    ) {
        position.collateral = coin::into_balance(collateral);
    }

    public entry fun borrow(
        position: &mut Position,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<USDC> {
        // In PTB, can borrow immediately after deposit
        // without waiting for price confirmation
        let max_borrow = coin::value(&position.collateral) / 2;
        assert!(amount <= max_borrow, EOverBorrow);

        balance::withdraw(&mut position.borrowed, amount)
    }

    public entry fun withdraw_collateral(
        position: &mut Position,
        ctx: &mut TxContext
    ): Coin<SUI> {
        // In PTB, can withdraw right after borrow
        let collateral = position.collateral;
        position.collateral = coin::zero();
        coin::from_balance(collateral, ctx)
    }
}
```

### Attack Scenario via PTB:

1. `deposit_collateral(1000 SUI)`
2. `borrow(500 USDC)` (based on 1000 SUI collateral)
3. `withdraw_collateral()` (no collateral left!)
4. Protocol left with bad debt

### Secure Code

```move
module secure::lending {
    public struct Position has key {
        id: UID,
        collateral: Balance<SUI>,
        borrowed: Balance<USDC>,
        last_action_epoch: u64,
    }

    // GOOD: Check health ratio before any withdrawal
    public entry fun withdraw_collateral(
        position: &mut Position,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let collateral_value = balance::value(&position.collateral);
        let borrowed_value = balance::value(&position.borrowed);

        assert!(collateral_value >= amount, EInsufficientCollateral);

        // Calculate health factor after withdrawal
        let new_collateral = collateral_value - amount;
        let health_factor = (new_collateral * 100) / borrowed_value;

        assert!(health_factor >= 150, EUnhealthyPosition); // 150% minimum

        balance::withdraw(&mut position.collateral, amount)
    }

    // GOOD: Use flash loan pattern for atomic operations
    public entry fun flash_loan(
        position: &mut Position,
        amount: u64,
        callback: &mut receiver::FlashLoanReceiver,
        ctx: &mut TxContext
    ) {
        let loan = balance::withdraw(&mut position.borrowed, amount);
        let loan_value = balance::value(&loan);

        // Callback must repay within same transaction
        receiver::receive(callback, loan, ctx);

        // Verify repayment
        assert!(
            balance::value(&position.borrowed) >= loan_value,
            EFlashLoanNotRepaid
        );
    }
}
```

---

## S5. Dynamic Field Abuse

### Description
Dynamic fields in Sui allow attaching data to objects, but improper access control can lead to unauthorized modifications.

### Severity
HIGH

### Detection Pattern

```bash
# Find dynamic field usage
rg "sui::dynamic_field|dynamic_object_field" sources/
rg "add|remove|borrow" sources/ | grep "dynamic"
```

### Vulnerable Code

```move
module vulnerable::metadata {
    use sui::dynamic_field;

    public struct NFT has key, store { id: UID }
    public struct Metadata has store { rarity: u8, power: u64 }

    // BAD: Anyone can modify metadata
    public entry fun set_rarity(
        nft: &mut NFT,
        rarity: u8,
        _ctx: &mut TxContext
    ) {
        dynamic_field::add(&mut nft.id, b"rarity", rarity);
    }

    // BAD: No validation on metadata
    public entry fun update_power(
        nft: &mut NFT,
        power: u64
    ) {
        if (dynamic_field::exists_(&nft.id, b"power")) {
            dynamic_field::remove(&mut nft.id, b"power");
        };
        dynamic_field::add(&mut nft.id, b"power", power);
    }
}
```

### Secure Code

```move
module secure::metadata {
    use sui::dynamic_field;

    public struct NFT has key, store { id: UID }
    public struct Metadata has store { rarity: u8, power: u64 }
    public struct AdminCap has key { id: UID }

    // GOOD: Only admin can modify metadata
    public entry fun set_rarity(
        _: &AdminCap,
        nft: &mut NFT,
        rarity: u8,
        _ctx: &mut TxContext
    ) {
        assert!(rarity <= 5, EInvalidRarity);

        if (dynamic_field::exists_(&nft.id, b"metadata")) {
            dynamic_field::remove<Metadata>(&mut nft.id);
        };
        dynamic_field::add(&mut nft.id, b"metadata", Metadata {
            rarity,
            power: calculate_power(rarity),
        });
    }

    // GOOD: Power derived from rarity, not settable
    fun calculate_power(rarity: u8): u64 {
        (rarity as u64) * 100
    }
}
```

---

## S6. Transfer Policy Bypass

### Description
Sui's transfer policies enforce rules on asset transfers, but improper implementation can allow bypassing these rules.

### Severity
HIGH

### Detection Pattern

```bash
# Find transfer policy usage
rg "sui::transfer_policy|TransferPolicy" sources/
rg "TransferRequest|prove" sources/
```

### Vulnerable Code

```move
module vulnerable::regulated_coin {
    public struct REGULATED_COIN has drop {}
    public struct RegulatedCoin has key, store { id: UID, value: u64 }
    public struct TransferPolicy has key { id: UID }

    // BAD: No transfer policy enforcement
    public entry fun transfer(
        coin: RegulatedCoin,
        recipient: address,
        _ctx: &mut TxContext
    ) {
        // Bypasses any transfer rules
        transfer::public_transfer(coin, recipient);
    }

    // BAD: Policy check is optional
    public entry fun checked_transfer(
        coin: RegulatedCoin,
        recipient: address,
        policy: Option<&TransferPolicy>,
        ctx: &mut TxContext
    ) {
        if (option::is_some(policy)) {
            // Policy check optional
            validate_transfer(option::borrow(policy), &coin);
        };
        transfer::public_transfer(coin, recipient);
    }
}
```

### Secure Code

```move
module secure::regulated_coin {
    use sui::transfer_policy::{Self, TransferPolicy, TransferRequest};

    public struct REGULATED_COIN has drop {}
    public struct RegulatedCoin has key, store { id: UID, value: u64 }

    // GOOD: Enforce transfer policy
    public entry fun transfer(
        coin: RegulatedCoin,
        recipient: address,
        policy: &TransferPolicy<REGULATED_COIN>,
        ctx: &mut TxContext
    ) {
        let (coin, request) = transfer_policy::request(coin, policy, ctx);

        // Enforce KYC/AML rules
        assert!(is_kyc_approved(recipient), ENotKYC);
        assert!(!is_sanctioned(recipient), ESanctioned);

        transfer_policy::approve(policy, request);
        transfer::public_transfer(coin, recipient);
    }

    // GOOD: Use kiosk for compliant transfers
    public entry fun kiosk_transfer(
        kiosk: &mut Kiosk,
        coin: RegulatedCoin,
        policy: &TransferPolicy<REGULATED_COIN>,
        ctx: &mut TxContext
    ) {
        let (coin, request) = transfer_policy::request(coin, policy, ctx);
        transfer_policy::confirm_request(policy, request);

        kiosk::deposit(kiosk, coin);
    }
}
```

---

## Sui Security Best Practices

### 1. Object Model Patterns

```move
// Pattern: Capability-based ownership
public struct OwnedItem has key { id: UID }
public struct OwnerCap has key { id: UID, item_id: ID }

// Pattern: Shared state with mutex-like access
public struct SharedState has key { id: UID, locked: bool }
public struct LockCap has key { id: UID }
```

### 2. Transfer Patterns

```move
// Always check ownership before transfer
public entry fun transfer_item(
    _: &OwnerCap,
    item: Item,
    recipient: address
) { ... }

// Use kiosk for marketplace operations
kiosk::list(kiosk, item_id, price);
```

### 3. Concurrency Safety

```move
// Use status flags for shared objects
public struct Listing has key {
    sold: bool,
    cancelled: bool,
}

// Check status before operations
assert!(!listing.sold && !listing.cancelled, EInvalidState);
```

### 4. PTB Safety

```move
// Always verify final state
public entry fun final_health_check(position: &Position) {
    let health = calculate_health(position);
    assert!(health >= MIN_HEALTH, EUnhealthyPosition);
}
```

---

## Summary Checklist

| Check | Description |
|-------|-------------|
| Object Ownership | Capability required for transfers |
| Shared Objects | Status flags for concurrent access |
| Kiosk | All trades through kiosk |
| PTB Safety | State verified at end of operations |
| Dynamic Fields | Access-controlled modifications |
| Transfer Policy | Required for regulated assets |
