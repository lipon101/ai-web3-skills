# Cryptography & Secrets Management Agent (`infra` mode — Angle 5)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

> **Calibration**: Crypto misuse breaks the ENTIRE security model. An arithmetic overflow loses precision; a crypto bug makes the system's foundational guarantees void. The modal crypto bug in DLT infrastructure is **nonce/k reuse** (ECDSA k-reuse → private key recovery from two signatures; AES-GCM nonce reuse → ciphertext forgery). The second-most-common is **missing constant-time comparison** on secrets — timing leaks the value byte-by-byte. The most insidious is **weak RNG** — the system works perfectly in testing but all generated keys are predictable (Android `SecureRandom` unseeded → Bitcoin wallets drained, 2013).
>
> Three damage classes: **(1) Private key extraction** — nonce reuse, weak RNG, side-channel leakage → attacker recovers signing key → can forge any transaction. **(2) Asset loss via forgery** — missing curve-point validation, signature malleability, BLS rogue-key attack → attacker forges valid signature on theft transaction. **(3) Silent security degradation** — non-constant-time comparison, missing zeroisation, weak hash → system appears secure but is trivially breakable.
>
> Tool coverage is WEAKER for crypto than for arithmetic. `cargo audit` catches known-vulnerable dependency versions. `dudect`/`ctgrind` detect timing leaks but require per-function harnesses. Most crypto findings are pattern-grep + context-triage — the LLM's advantage is knowing WHICH patterns to grep and what the CORRECT replacement is per framework.

**Primary verification approach**: most crypto findings are not mechanically verifiable in a single step — they require manual review + targeted tests + side-channel analysis tools (`dudect`, `ctgrind`). Vectors in **Group E** (`dlt-infra-attack-vectors.md`) are your catalogue.

**NOT your domain**: ZK circuit constraint soundness (Group J). If the target has ZK circuit definitions (Halo2, arkworks constraint systems, Bellman circuits), the ZK Circuit Soundness angle (Angle 9) handles circuit-internal constraint completeness. You handle the Rust code around the circuit — RNG, zeroisation, constant-time, nonce management — but not whether the circuit's polynomial constraints fully enforce the intended relationship.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical checks:

### Step 1: `cargo audit` pre-filter

```bash
cargo audit
# Or: cargo deny check advisories
```

Flag every advisory with keywords: `crypto`, `signature`, `RNG`, `hash`, `timing`, `zeroize`, `constant-time`, `nonce`, `side-channel`. These name the exact vulnerable crate + version delta — the highest-ROI 5 minutes in crypto auditing.

### Step 2: High-signal grep patterns

These are deterministic to detect — the LLM's job is to trace impact per context, not find sites:

```bash
# RNG in key-gen / security context
rg 'thread_rng|rand::random' --type rust -l

# Weak hash functions
rg -i 'md5|Md5|sha1|Sha1|SHA-1' --type rust -l

# Non-constant-time comparison on secret material
rg '== .*\[u8' --type rust -l

# Curve point deserialization without validation
rg 'decompress|from_bytes|from_compressed|from_uncompressed' --type rust -l

# Missing zeroisation
rg 'struct.*Key|struct.*Secret|struct.*Seed|struct.*Mnemonic' --type rust -l

# Hand-rolled crypto (high-value grep)
rg -i 'fn\s+(sign|verify|encrypt|decrypt|hash|derive_key)' --type rust -l

# BLS aggregation without PoP
rg 'aggregate_verify|fast_aggregate_verify' --type rust -l

# Merkle proof verification
rg 'verify_proof|verify_inclusion|verify_membership|merkle_proof' --type rust -l
```

### Step 3: Dependency version check

```bash
cargo tree | grep -E 'ed25519|secp256k1|bls|blst|aes-gcm|chacha|hmac|sha2|sha3|blake|argon2|subtle|zeroize|ring'
```

Outdated crypto crate versions are the cheapest crypto finding — verify each against the latest RUSTSEC-advisory-free version.

---

## Phase 2: Crypto surface inventory

Enumerate the crypto surface:

- **Key generation sites**: every `OsRng`, `thread_rng()`, `SeedableRng::from_seed`, or `Keypair::generate()` call. Is the RNG correct for the target platform (WASM? no_std? BPF?)?
- **Signing functions**: `sign()`, `sign_digest()`, `sign_prehash()` — what nonce source? RFC 6979 deterministic or fresh CSPRNG?
- **Verification functions**: `verify()`, `verify_strict()`, `verify_slice()` — constant-time? Early-return paths?
- **Curve-point deserialization sites**: every `decompress` / `from_bytes` / `from_compressed` of a public key or point from network/external input.
- **Secret-holding types**: every `struct` containing `[u8; 32]`, `Vec<u8>`, or `String` for keys, seeds, mnemonics, shared secrets.
- **Hash function uses**: every hash call where the hash is used for a security property (commitment, MAC, signature, collision-resistance).
- **Merkle proof verification**: every `verify_proof` / `verify_inclusion` — uses a known library (`ics23`, `rs_merkle`) or hand-rolled?
- **BLS aggregation**: every `aggregate` / `aggregate_verify` / `fast_aggregate_verify`. Is PoP verified per key before aggregation?

---

## Phase 3: Per-class checks

### CHECK 1 — Weak/predictable RNG (E01)

**Signal**: `rand::thread_rng()`, `rand::random()`, `StdRng::from_seed([0u8; 32])`, or any seedable PRNG used for key generation or nonce generation.

**Procedure**:
1. **Grep `thread_rng` in key-gen/nonce contexts.** `thread_rng()` is a CSPRNG (`ChaCha12Rng`) — safe on most platforms. But in WASM (`wasm32-unknown-unknown`), `thread_rng()` falls back to a seeded PRNG from `wasm-bindgen` → potentially predictable.
2. **Grep `OsRng`.** This is explicitly the OS CSPRNG and is the safest choice for key generation. Verify it's used for: signing key generation, encryption key generation, and nonce generation (when not deterministic per RFC 6979).
3. **Check seeding sources.** Any `from_seed` / `seed_from_u64` / `from_rng` with a constant or predictable seed → flag. Common antipattern: `StdRng::seed_from_u64(crate::STATE.load(Ordering::Relaxed))` — using on-chain state as RNG seed is predictable.
4. **no_std targets**: `OsRng` may be unavailable. Check what the platform uses as fallback. If the fallback is a deterministic PRNG with a constant seed → flag.
5. **Framework RNG wrappers**: Cosmos SDK provides `sdk.GenerateKey()` (safe). Substrate provides `sp_core::sr25519::Pair::generate()` (safe). Hand-rolled `rand::random::<[u8; 32]>` → flag.
6. **CosmWasm specific**: contracts can't access `OsRng` because WASM has no OS entropy. Any contract generating keys from WASM randomness → flag at High.

**Golden signature**: predict the next "random" value from known state, or demonstrate that the RNG produces identical output on two runs. Tier-3-unit.

**Severity triage**: `thread_rng()` on standard Linux/Mac → Informational (it IS a CSPRNG). `thread_rng()` on WASM/no_std → High. Constant-seed PRNG for key-gen → Critical.

**Source**: Android `SecureRandom` unseeded (2013) — Bitcoin wallets drained [model-knowledge].

---

### CHECK 2 — Non-constant-time comparison (E02)

**Signal**: `secret_a == secret_b` on `[u8; 32]`, `password == stored_hash`, `hmac.verify(input).is_ok()`, or any comparison of secret material with early-exit semantics.

**Procedure**:
1. **Grep for direct comparison of `[u8]` / `Vec<u8>`** with `==` where one operand is secret material (key, password hash, MAC tag, shared secret).
2. For each: verify the comparison uses `subtle::ConstantTimeEq::ct_eq` or the framework's constant-time equivalent.
3. **HMAC verification**: `hmac.verify(input).is_ok()` may use `memcmp` internally. Check whether the HMAC crate guarantees constant-time verification. The safe pattern: `hmac.verify_slice(tag, input)` which compares in constant time.
4. **Password verification**: `argon2::verify_encoded(password, hash)` is constant-time by design. `password == stored_hash` is not (memcmp early-exits).
5. **Framework equivalents**: `ed25519-dalek::VerifyingKey::verify_strict()` is constant-time. `ring::constant_time::verify_slices_are_equal(a, b)` returns `Result`.

**Golden signature**: measure timing difference between matching and non-matching inputs. If variance > noise threshold → leak. `dudect` is the standard tool. Tier-2-prop.

**Source**: Lucky13 (TLS MAC timing) [model-knowledge]; Minerva (ECDSA nonce bias from timing) [model-knowledge].

---

### CHECK 3 — Missing zeroisation (E03)

**Signal**: key material, mnemonic phrases, shared secrets stored in plain `[u8; N]`, `Vec<u8>`, or `String` without `Zeroize`/`ZeroizeOnDrop`.

**Procedure**:
1. **Enumerate every secret-holding type.** Every `[u8; 32]` that holds a private key, seed, or shared secret. Every `Vec<u8>` that temporarily holds decrypted data. Every `String` that holds a mnemonic phrase.
2. For each: does the type derive `Zeroize` or `ZeroizeOnDrop`? Does it wrap the bytes in `Zeroizing<[u8; N]>`?
3. **Mnemonic phrase copies**: `String::from_utf8(mnemonic_bytes)` creates a new allocation — the original bytes remain in memory. Zeroize both the original buffer AND the String.
4. **Stack vs heap**: `[u8; 32]` on the stack is NOT guaranteed zeroed when the frame exits. Rust does not zero stack memory on drop. Use `Zeroize` explicitly.
5. **Framework equivalents**: Cosmos SDK `sdk.PrivKey` zeroes on GC (Go, not Rust). Substrate `sp_core::sr25519::Pair` zeroes on `Drop` — verify the `Drop` impl, don't assume.
6. **Solana BPF specific**: `zeroize` crate may not compile to BPF or may be a no-op. Check whether BPF-secret-holding programs have an alternative (overwriting with random bytes before returning).

**Golden signature**: MIRI or valgrind showing secret bytes persist in memory after the secret-holding variable goes out of scope. Tier-3-unit.

**Source**: Heartbleed (memory disclosure) [model-knowledge]; various blockchain client key handling audits [model-knowledge].

---

### CHECK 4 — Weak hash for security purpose (E04)

**Signal**: MD5 or SHA-1 used for commitment, MAC, hash-to-curve, Merkle tree root, collision-resistance, or any purpose where collision resistance is assumed.

**Procedure**:
1. **Grep for `Md5`, `Sha1`, `SHA-1`, `sha1`, `md5`** in non-comment, non-test code.
2. For each use: is the hash used for a security purpose? Collision resistance, commitment, MAC? → flag. Non-security (content-addressing, hash table distribution, dedup)? → not a finding.
3. **SHA-1 in practice**: broken for collision resistance since SHAttered (2017, ~$110k compute). Safe for HMAC-SHA1 (still collision-resistant in the HMAC construction) and PBKDF2-HMAC-SHA1. Unsafe for digital signatures, certificates, and Merkle trees. DISTINGUISH the use case.
4. **MD5**: broken for ALL security purposes since 2008 (rogue CA attack). Any MD5 use in security code → flag at High.
5. **Ethereum specific**: Keccak256 is NOT SHA3-256. The Ethereum-specific Keccak256 variant differs from the standardized SHA3. Verify the correct crate — `sha3` crate with `Keccak256` mode, or `tiny-keccak`. Using NIST SHA3-256 where Keccak256 is expected → cross-chain state root mismatch.

**Golden signature**: cite the known collision attack on the hash function and demonstrate the security property it breaks. Tier-4-derivation.

**Source**: SHAttered (2017) — SHA-1 collision [model-knowledge]; MD5 rogue CA (2008) [model-knowledge].

---

### CHECK 5 — Nonce/k reuse (E05)

**Signal**: ECDSA/EdDSA/Schnorr signing functions; AES-GCM encryption; any construction where the spec says "value must be unique per call."

**Procedure**:
1. For **ECDSA**: grep `sign` / `sign_digest` / `sign_prehash`. Trace the nonce k source — is it RFC 6979 deterministic (HMAC_DRBG with private key + message hash) or a fresh CSPRNG call per signature? If the CSPRNG is seeded from a known source → k predictable.
2. If deterministic (RFC 6979): safe. The same message with the same key always produces the same k (cryptographically fine). Verify the RFC 6979 implementation is correct — some implementations deviate.
3. For **AES-GCM**: grep `encrypt` / `Gcm::new`. Nonce must be unique per (key, nonce) pair across the PROTOCOL LIFETIME, not just per-session. A counter that resets on restart → reuse on next run.
4. For **Ed25519**: the nonce is deterministic per spec (`SHA-512(private_key) || message`). Verify `ed25519-dalek` or equivalent canonical implementation is used, not a hand-rolled signer.
5. For **sr25519** (Substrate): deterministic nonce derived from key + message (same principle as RFC 6979). Verify the `schnorrkel` crate is used, not hand-rolled.
6. **Proptest verification**: sign the same message 10,000 times; check for duplicate (r, s) pairs. Duplicate with same message = deterministic (safe). Duplicate r-value across DIFFERENT messages = k-reuse (Critical).

**Golden signature**: two signatures with the same r-value and different messages → private key recoverable via simple algebra: `k = (z1 - z2) / (s1 - s2) mod n`, then `d = (s1*k - z1) / r mod n`. Tier-1-fuzz.

**Source**: Android `SecureRandom` → Bitcoin wallet k-reuse (2013) [model-knowledge]; Sony PS3 ECDSA firmware key recovery (2010) [model-knowledge].

---

### CHECK 6 — Missing curve-point validation (E06 extended)

**Signal**: any `decompress`, `from_bytes`, `from_compressed`, `deserialize`, or `decode` of a public key or curve point from network/external input.

**Procedure — three checks, all required per point**:

| # | Check | What it prevents | Per-curve method |
|---|-------|-----------------|------------------|
| 1 | **On-curve** | Invalid-curve attack — attacker sends point not on curve; scalar multiplication leaks private key bits | `decompress().is_some()` (decompress checks curve equation), or `is_on_curve()` |
| 2 | **Subgroup membership** | Small-subgroup attack — low-order point makes `DH(sk, low_order_point)` brute-forceable | Ed25519: `is_torsion_free()`; BLS12-381: `is_in_correct_subgroup_assuming_on_curve()`; curve25519: `is_principal()` |
| 3 | **Not identity** | Identity-element bypass — `DH(sk, identity) = identity` → attacker knows shared secret | `!point.is_identity()` or `!point.is_small_order()` |

**Curve-by-curve reference**:

| Curve | On-curve check | Subgroup check | Identity check | Notes |
|-------|---------------|----------------|----------------|-------|
| **Ed25519 / curve25519** | `decompress().is_some()` | `is_torsion_free()` (covers all three) or `is_small_order()` (cheaper, misses identity) | `!is_identity()` | Cofactor 8. `verify_strict()` does all three; `verify()` multiplies by cofactor (safe for DH, NOT safe for all uses). |
| **secp256k1** | `decompress().is_some()` | N/A (cofactor 1) | `!is_identity()` | Cofactor 1 → no small-subgroup. On-curve check still required for invalid-curve defense. |
| **BLS12-381** | `from_bytes` returns `CtOption` — `is_some()` confirms valid encoding | `is_in_correct_subgroup_assuming_on_curve()` | `!is_identity()` | `G1Projective`/`G2Projective` are on-curve by construction; subgroup check needed for deserialized public keys. |

**Special case**: when a point is a constant in the source code (genesis validator key, hardcoded trusted key), on-curve + subgroup checks are still required — a typo in the constant produces an invalid key that passes no runtime check.

**Golden signature**: craft a small-order point, pass it to the verification function, demonstrate it produces a valid signature. Tier-1-e2e.

**Source**: ed25519-dalek without `is_torsion_free()` [model-knowledge]; BLS rogue-key without subgroup check [model-knowledge]; Monero key-image small-subgroup [model-knowledge].

---

### CHECK 7 — Side-channel via early-exit verification (E08 extended)

**Signal**: any `verify` / `is_valid` / `check_signature` function for a cryptographic primitive that returns `bool` (or `Result`) and has early-return paths for distinct failure modes.

**Procedure**:
1. **Grep `return false` / `return Err(...)` mid-verification** in crypto verification functions. Each is a potential timing leak — it signals a DIFFERENT check failure at a DIFFERENT point in execution.
2. **For ECDSA**: verification should check r in range, s in range, compute u1, u2, double-scalar-mult — all in constant time — then return the combined result. Early-return on "r out of range" → attacker knows r was the problem. Early-return on "s out of range" → attacker knows s was the problem. Binary search across byte positions → extract valid (r, s) for forged message.
3. **For Ed25519**: `verify_strict()` performs ALL checks before returning. `verify()` does too. A hand-rolled verifier with early-return on "R decompress failed" leaks that the R point was invalid.
4. **For HMAC**: `verify_slice()` is constant-time. `verify(input) == stored_tag` is NOT (memcmp on the comparison, not the HMAC computation).
5. **Nonce-bit-length leak (ECDSA scalar-mult)**: before dudect, inspect the signing inner loop — does iteration count or branch structure depend on the nonce's leading zeros (variable-length double-and-add, early-terminating loop)? Fixed-window / constant-time ladder is safe; a length-dependent loop leaks the nonce bit-length, and a lattice recovers the long-term key from a few hundred–few thousand signatures (Minerva ~500–2,100; TPM-FAIL). Pure-language no-asm implementations are prone to this (python-ecdsa CVE-2024-23342, WONTFIX).
6. **Run `dudect`** on the verification function: two input classes — valid signature vs edge-case invalid (out-of-range r, wrong signer, tampered message); for the C10 leak, distinguish short-nonce vs full-length-nonce signing. If t-test > threshold → confirmed timing leak. Only required in Thorough mode; in Core, manual enumeration of early-return / variable-length paths is sufficient.

**Golden signature**: `dudect` shows statistically significant timing difference between valid and edge-case invalid inputs. Tier-2-prop.

**Source**: Minerva (ECDSA nonce bias from timing, 2019) [model-knowledge]; TPM-FAIL (TPM firmware ECDSA timing, 2019) [model-knowledge].

---

### CHECK 8 — Signature malleability (V27 extended)

**Signal**: ECDSA signature verification that accepts (r, s) where s is in the upper half of the curve order.

**Procedure**:
1. **The attack**: ECDSA signature (r, s) is malleable to (r, n−s) — same signer, same message, different valid signature. In systems where the signature is part of the txid (pre-SegWit Bitcoin) → txid mutation, downstream systems lose track of the transaction. In cross-chain relay → relay sees different txid than source chain, double-processes or drops.
2. **Low-S rule**: enforce `s <= n/2` (the lower half of the curve order). If s > n/2, replace with n−s before verification or reject the signature.
2a. **DER canonicalisation**: a verifier that accepts non-canonical DER (over-long length octets, trailing bytes, leading-zero padding on r/s) admits a second valid encoding of the same signature → malleable even when low-S holds. Require the decoder reject non-canonical DER; `k256`/`secp256k1` decode strictly, hand-rolled or permissive DER parsers do not. python-ecdsa < 0.13.3 accepted non-DER signatures (CVE-2019-14859).
3. **Framework compliance**:
   - `libsecp256k1` with `SECP256K1_ECDSA_SIGN` → normalizes S to lower half by default. Safe.
   - `k256` crate → `VerifyingKey::verify()` checks low-S. Safe.
   - `secp256k1` crate (rust-secp256k1) → `Message::from_slice().verify()` enforces low-S. Safe.
   - Hand-rolled secp256k1 verify with `s < n` but NOT `s <= n/2` → malleable. Flag.
4. **EIP-2** (Ethereum): low-S required for all transaction signatures since Homestead (2016). If the codebase predates EIP-2 or explicitly bypasses it → flag.
5. **BIP-62** (Bitcoin, historical): attempted to fix malleability pre-SegWit. Post-SegWit, witness data is not part of txid → malleability no longer a txid concern. But SegWit adoption is not universal.
6. **Ed25519**: NOT malleable. The signature is fully deterministic; there is no second valid (R, s) pair. `ed25519-dalek` enforces canonical encoding.
7. **For m-of-n multisig**: if m signatures are required and any signature can be malleated, an attacker can change the txid without invalidating the multisig → replay protection based on txid fails.

**Golden signature**: take a valid ECDSA signature (r, s) with s > n/2, compute (r, n−s), verify it also passes. If yes → malleable. Tier-1-e2e.

**Source**: Bitcoin transaction malleability pre-SegWit [model-knowledge]; Ethereum pre-EIP-2 [model-knowledge].

---

### CHECK 9 — BLS rogue-key attack / missing proof-of-possession (NEW)

**Signal**: BLS signature aggregation (`aggregate_verify`, `fast_aggregate_verify`, `aggregate_signatures`) that combines public keys from multiple signers without verifying proof-of-possession for each key.

**Procedure**:
1. **The attack**: Attacker sees honest party's public key `PK_h`. Attacker computes `PK_a = g^a / PK_h` (depends on `PK_h`). Aggregate key = `PK_h + PK_a = g^a`. Attacker can sign ANY message as if it were the aggregate — without knowing any honest secret key. The algebra: `PK_a = g^a * PK_h^{-1}` → `PK_h + PK_a = g^a`. Attacker knows `a`, signs with `a`, claims it's an aggregate of honest + attacker.
2. **Defense**: before aggregation, verify each public key has a **proof-of-possession** — a signature by that key on its own public key (or on "PoP" + identity). This proves the submitter knows the secret key and didn't derive `PK_a` from others' keys.
3. **Grep for `aggregate` / `aggregate_verify` / `fast_aggregate_verify`** on BLS signatures. Is there a prior step that calls `pop_verify` or `verify_proof_of_possession` on EACH individual key?
4. **Ethereum 2.0 specific**: `fast_aggregate_verify` is used for attestation aggregation. PoP is verified during validator deposit (deposit contract validates the BLS signature). The aggregation path assumes pre-verified keys — but if a custom BLS scheme bypasses the deposit contract → no PoP.
5. **Substrate BEEFY specific**: BLS PoP verified at session key registration. The bridge finality gadget (`beefy-gadget`) uses pre-verified keys. Verify the registration path includes PoP.
6. **Cosmos SDK specific**: if using BLS for validator signatures (less common, most use Ed25519), verify the `bls12-381` crate's `pop_verify` is called at key registration.

**Golden signature**: craft `PK_a = g^a / PK_h`, forge an aggregate signature without knowing any honest secret key. Tier-1-e2e.

**Source**: Boneh-Drijvers-Neven (ASIACRYPT 2018) — BLS rogue-key attacks [model-knowledge]; Ethereum 2.0 PoP debate [model-knowledge].

---

### CHECK 10 — Ed25519 cofactor / small-subgroup (NEW)

**Signal**: Ed25519 signature verification that does not account for the cofactor 8.

**Procedure**:
1. **Ed25519 has a cofactor of 8.** The curve order is `8 * l` where `l` is a large prime. Points of order 1, 2, 4, or 8 exist. An attacker using a small-order point as their public key can produce "valid" signatures on attacker-chosen messages if verification doesn't clear the cofactor.
2. **`verify()` vs `verify_strict()`**: `ed25519-dalek::VerifyingKey::verify()` multiplies the point by the cofactor internally (safe — clears the small-order component before the main check). `verify_strict()` additionally checks `is_torsion_free()` AND canonical encoding — more expensive but stricter.
3. **Hand-rolled Ed25519 verifier**: if it computes `[s]B - [h]A` without multiplying `A` by the cofactor 8, small-order public keys pass for any message where the attacker controls the signature. Flag at High.
4. **Monero ed25519 variant** (key images): key images link signatures to detect double-spending. A small-subgroup key image wraps to identity after scalar multiplication → linkability broken → double-spend possible.
5. **Solana specific**: Solana's ed25519 syscall enforces `verify_strict()`. Programs using the syscall are safe. Programs with hand-rolled ed25519 compiled to BPF must handle the cofactor themselves.
6. **Cosmos/Tendermint specific**: `ed25519-consensus` crate uses `verify_strict()` — safe. Verify this crate is used, not a hand-rolled verifier.

**Golden signature**: create an ed25519 keypair where the public key has order 8; forge a signature that passes cofactor-less verification. Tier-1-e2e.

**Source**: ed25519-dalek before `is_torsion_free()` was standard [model-knowledge]; Monero small-subgroup key-image attack [model-knowledge].

---

### CHECK 11 — Merkle proof verification gap (NEW)

**Signal**: light client or bridge code that verifies a Merkle/inclusion proof from another chain.

**Procedure** — five minimum checks for any Merkle proof verifier:

| # | Check | What happens if missing |
|---|-------|------------------------|
| 1 | **Root hash comparison** — computed root matches a TRUSTED root (from consensus state, from a trusted oracle, from the light client's stored state root) | Attacker provides a valid proof for a DIFFERENT tree whose root they control |
| 2 | **Leaf preimage binding** — the leaf value being proved matches what the caller provides (not just "SOME leaf exists" but "THIS specific leaf exists at this path") | Attacker proves inclusion of THEIR leaf, not the caller's leaf |
| 3 | **Path length validation** — fixed-depth tree → exact expected length; variable-depth → at most max depth | Attacker provides a truncated proof that appears valid |
| 4 | **Hash function consistency** — all hashes in the proof use the same hash function (no SHA-256 node hash + SHA-512 leaf hash confusion) | Attacker exploits hash-function mismatch to create cross-function collisions |
| 5 | **Empty-proof bypass** — a proof with zero steps (`proof_path = vec![]`) → computed root equals leaf hash → attacker proves any leaf by claiming it IS the root | Attacker supplies any value as both leaf and root |

**Prefix-equality (Dragonberry mechanism)**: for any proof spec with attacker-influenced structural fields (leaf prefix, inner-node prefix/suffix), verify **exact equality + length bounds**, not substring/`contains`/prefix-of matching. ICS-23 only required the input leaf prefix to *contain* the spec prefix with no length check → an attacker whose tree holds a key shaped `…|len(subkey)|subkey` could extend the leaf prefix and forge membership of a non-existent subkey.

**Framework-specific**:
- **ICS-23 (IBC)**: `verify_membership` and `verify_non_membership` must check: key→value mapping, commitment root matches trusted consensus state, proof spec (hash, encoding) matches expected spec, and structural prefix fields match by exact equality + length (per the Dragonberry mechanism above). Pin a post-Dragonberry `ics23` version.
- **Hand-rolled Merkle verifier**: flag at High — use `ics23` (Cosmos), `rs_merkle`, or `merkle-proof` crate. Merkle proof verification is subtle; hand-rolled code has a higher bug density than any other crypto component.
- **`tendermint-rs`**: uses `ics23` for state proofs. Verify the `ics23` crate version is not advisory-affected.

**Golden signature**: craft a proof for a non-existent leaf that passes all five checks. Tier-1-e2e.

**Source**: IBC ICS-23 Dragonberry (2022) — under-constrained leaf-prefix validation (substring vs exact + missing length check) [model-knowledge]; various bridge light client proof verification gaps [model-knowledge].

---

### CHECK 12 — Signer-API oracle / decoupled public key (NEW)

**Signal**: a signing API that accepts a *separately-supplied* public key (or a `Keypair` assembled from independent private + public halves) into a deterministic signer — especially serialize/deserialize of 64-byte `private||public` keypairs.

**Procedure**:
1. **The flaw**: in EdDSA the public key feeds the deterministic computation of `S` but NOT `R`. If an attacker can drive the signer with an *arbitrary* public key on a fixed message, two calls produce the same `R`, different `S` → the private scalar is recoverable.
2. **Grep for APIs that build a signer from decoupled key halves**, or that assemble a `Keypair`/`SigningKey` from independent public + private types rather than deriving the public key from the secret.
3. **Crate version**: `ed25519-dalek` < 2.0 exposed this oracle; ≥ 2.0 confines decoupled usage to clearly-labelled `hazmat` functions — verify the version and that no `hazmat` path is reachable with caller-controlled pubkeys.
4. **Generalise**: any deterministic signer where the public key is an *input* rather than *derived from the secret* is a candidate oracle.

**Anti-pattern (FP guard)**: a signer that derives the public key internally from the secret (the safe default) is not exposed.

**Golden signature**: obtain two signatures over one message with two different supplied public keys; if they share `R`, extract the key. Tier-1-e2e.

**Source**: `ed25519-dalek` < 2.0 double-public-key signing oracle — RUSTSEC-2022-0093 [model-knowledge].

---

### CHECK 13 — AEAD plaintext-on-failure (in-place decrypt) (NEW)

**Signal**: `decrypt_in_place` / `decrypt_in_place_detached` whose buffer is read by the caller after the call.

**Procedure**:
1. **The flaw**: on tag-verification failure these APIs return `Err`, but because decryption happens in-place, the buffer now holds the *decrypted-but-unauthenticated* plaintext. A caller that ignores the error and reads the buffer leaks plaintext / enables a CCA oracle.
2. **Grep `decrypt_in_place*`**: confirm the caller treats `Err` as fatal and never reads the buffer on failure.
3. **Version gate**: `aes-gcm` 0.10.0–0.10.2 left the unauthenticated plaintext in the buffer (RUSTSEC-2023-0096); 0.10.3 re-encrypts on failure. Confirm the pinned `aes-gcm` is ≥ 0.10.3 — a `cargo audit` hit.
4. **Generalise** to any AEAD with in-place APIs (`chacha20poly1305`, `aes-gcm-siv`): the buffer is poisoned on tag failure.

**Anti-pattern (FP guard)**: detached in-place APIs on `aes-gcm` ≥ 0.10.3 (buffer restored on failure) are safe; the finding is version- AND usage-gated.

**Golden signature**: submit a ciphertext with a bad tag, observe recoverable plaintext in the buffer post-call. Tier-1-e2e.

**Source**: `aes-gcm` 0.10.0–0.10.2 `decrypt_in_place_detached` — RUSTSEC-2023-0096 [model-knowledge].

---

## Phase 4: Framework-specific knowledge

### Cosmos SDK / IBC

- **BLS signatures**: `bls12-381` crate. Subgroup check = `G1Projective::is_on_curve()` + `is_in_correct_subgroup_assuming_on_curve()`.
- **ICS-23**: always use the `ics23` crate; never hand-roll Merkle proof verification. Verify crate version against RUSTSEC advisories.
- **`sdk.PrivKey`** (Go, but Rust IBC reimpl): Go SDK zeros keys on GC. Rust re-implementations must use `Zeroize`.

### Tendermint / CometBFT

- **Ed25519 for consensus votes**: `ed25519-consensus` crate or `ed25519-dalek` with `verify_strict()`. Consensus votes are high-value — forgery = chain takeover.
- **Secp256k1 for validator keys** (historical): low-S enforcement needed. Tendermint's `crypto` package normalizes S.

### Ethereum (execution + consensus)

- **BLS12-381 for validator sigs**: `blst` (preferred) or `milagro_bls` (legacy). PoP verified during validator deposit via deposit contract — verify BOTH the deposit validation AND the aggregation path.
- **ECDSA tx sigs**: `ecrecover` precompile does NOT enforce low-S. EIP-2 enforces low-S at tx validation — verify the tx validation path, not the precompile.
- **Keccak256**: NOT SHA3-256. The Ethereum Keccak256 variant differs from NIST SHA3. Verify `sha3` crate with `Keccak256` mode, or `tiny-keccak`.
- **EIP-155 replay protection**: chain ID in v parameter. Verify NEW transactions use EIP-1559 (type 2) or at least EIP-155.

### Solana

- **Ed25519 syscall**: enforces `verify_strict()` at the runtime level. Programs using the syscall are safe. Hand-rolled ed25519 in BPF loses this guarantee.
- **secp256k1 syscall**: enforces low-S. Hand-rolled secp256k1 in BPF must enforce manually.
- **BPF zeroisation**: `zeroize` crate may not compile to BPF or be a no-op. Verify alternative zeroing exists (overwrite with random bytes before return).

### Substrate / Polkadot

- **sr25519** (Schnorr on Ristretto255): deterministic nonce from key + message. Verify `schnorrkel` crate is used, not hand-rolled.
- **ed25519 for Grandpa finality**: `ed25519-dalek` with `verify_strict()`. Forgery = finality override.
- **BLS12-381 for BEEFY**: `blst` or `milagro_bls`. PoP verified at session key registration.
- **`sp_core::Pair`**: zeroisation on `Drop`. Hand-rolled key types wrapping `[u8; 32]` without `Zeroize` → flag.

### CosmWasm (Rust)

- **`cosmwasm-crypto`**: thin wrappers around `ed25519-dalek` and `k256`. `ed25519_verify` and `secp256k1_verify` use strict verification by default since 1.0.
- **No native RNG**: WASM has no OS entropy. Contracts generating keys from WASM randomness → flag at High.

---

## Stage-3 PoC discipline

### Tier ladder

| Tier | Evidence | When to use |
|------|----------|-------------|
| **Tier-1-fuzz** | Nonce reuse: sign 10k messages, check for duplicate r-values across different messages. Signature malleability: verify (r, n−s) passes. Merkle proof: forge proof for non-existent leaf. | Deterministic to test, mechanical evidence |
| **Tier-2-prop** | Non-constant-time: `dudect` on verification function. Side-channel: timing measurement between valid/invalid inputs. | Timing measurement, statistical evidence |
| **Tier-3-unit** | RNG choice: predict the next "random" value. Zeroisation: MIRI/valgrind shows secrets persist. Weak hash: cite collision attack, show broken property. | Low cost, clear evidence — acceptable for most E01/E03/E04 findings |
| **Tier-4-derivation** | Mathematical argument for why primitive misuse breaks the security model. | When mechanical testing is infeasible (requires hash-burning budget, specialized hardware) |

### Test templates

**Nonce reuse fuzz** (CHECK 5):
```rust
#[test]
fn test_no_nonce_reuse_across_messages() {
    let key = SigningKey::generate(&mut OsRng);
    let mut seen_r = HashSet::new();
    for i in 0..10_000 {
        let msg = format!("message-{}", i);
        let sig = key.sign(msg.as_bytes());
        let r = sig.r(); // extract r component
        if seen_r.contains(&r) {
            panic!("k-reuse detected: same r={r:?} for different messages");
        }
        seen_r.insert(r);
    }
}
```

**Malleability test** (CHECK 8):
```rust
#[test]
fn test_ecdsa_not_malleable() {
    let (sig, msg) = get_valid_signature();
    let n = Secp256k1::order(); // curve order
    let s_high = n - sig.s();
    let malleated = Signature::from_scalars(sig.r(), s_high).unwrap();
    let pk = sig.recover_verifying_key(msg).unwrap();
    assert!(pk.verify(msg, &malleated).is_err(), "signature is malleable: (r, n-s) also verifies");
}
```

**Curve point validation test** (CHECK 6):
```rust
#[test]
fn test_rejects_small_order_point() {
    // Craft a point of order 8 on Ed25519
    let small_order_bytes: [u8; 32] = [ /* known small-order point encoding */ ];
    let point = EdwardsPoint::from_bytes(&small_order_bytes);
    assert!(point.is_some());
    let point = point.unwrap();
    assert!(point.is_small_order(), "test harness: must be small-order");
    // This should REJECT
    let result = target_verify(&point, &message, &signature);
    assert!(result.is_err(), "accepted small-order public key");
}
```

**Empty Merkle proof bypass test** (CHECK 11):
```rust
#[test]
fn test_rejects_empty_merkle_proof() {
    let attacker_leaf = hash(b"attacker_value");
    let empty_proof = MerkleProof { path: vec![] };
    let result = light_client.verify_inclusion(&trusted_root, &attacker_leaf, &empty_proof);
    assert!(result.is_err(), "empty proof bypass: accepted leaf as root");
}
```

---

## Output fields beyond shared FINDING schema

```yaml
crypto_primitive: RNG | hash | signature | encryption | KDF | commitment | merkle_proof
misuse_class: weak-rng | non-ct-compare | missing-zeroize | weak-hash | nonce-reuse | curve-validation | side-channel | malleability | bls-rogue-key | ed25519-cofactor | merkle-proof-gap | signer-api-oracle | aead-plaintext-on-failure
check_number: CHECK 1-13
api_call_location: <file:line of the misuse>
recommended_replacement: <specific function / crate to use instead>
side_channel_evidence: <if applicable: dudect output, timing measurement>
poc_tier: Tier-1-fuzz | Tier-2-prop | Tier-3-unit | Tier-4-derivation
framework_note: <CosmosSDK/Tendermint/Ethereum/Solana/Substrate/CosmWasm — specific semantics>
```

---

## Anti-patterns (do NOT report)

- `rand::thread_rng()` for non-security purposes (test data, sampling, UX shuffling). `thread_rng()` IS a CSPRNG on standard platforms — it's only a finding on WASM/no_std targets where it degrades.
- Hash function choice for non-security purposes (BLAKE3 vs SHA-256 for content-addressing = perf trade-off, not a finding).
- "Should use post-quantum crypto" — not a real-world finding. PQ migration is roadmap work, not a vulnerability.
- Side-channel concerns requiring physical access (cache-timing across VMs, power analysis) — out of scope for application-layer DLT auditing.
- `thread_rng()` on standard Linux/Mac targets — it's a ChaCha12 CSPRNG. Flag only on WASM, no_std embedded, or when a seedable PRNG is used instead.
- Ed25519 `verify()` (not `verify_strict()`) — `verify()` multiplies by cofactor internally and is safe for all standard uses. Only flag a hand-rolled verifier that omits the cofactor multiplication.
- Generic "this hash might be weak" without citing a specific collision or preimage attack with compute cost.

---

## Coordination with other angles

- **Arithmetic (Angle 3)**: owns numeric overflow/truncation. When crypto code uses arithmetic for key derivation that overflows → Angle 3 finds the overflow, Angle 5 frames the crypto impact.
- **Memory Safety (Angle 1)**: picks up when secret zeroisation gap → MIRI detects leftover bytes. Angle 5 finds the missing `Zeroize`; Angle 1 confirms with MIRI.
- **Concurrency (Angle 4)**: owns key-material accessed without synchronization (race on key buffer during signing). Angle 5 owns the signing-protocol correctness.
- **Logic & State Machine (Angle 7)**: owns protocol-level crypto integration failures (validator key rotation race, BLS aggregation skipping `pop_verify` as a state-machine invariant). Angle 5 owns the primitive-level misuse (which primitives to use); Angle 7 owns the protocol-level integration (when and how they're called).
- **ZK Circuit Soundness (Angle 9)**: owns ZK circuit constraint completeness — under-constrained witness cells, missing range checks, custom-gate gaps (Group J). Angle 5 owns the Rust code around the circuit (witness-generation RNG, proof serialization, key handling); Angle 9 owns the constraint system itself. When both are affected (witness generation uses `thread_rng()` AND the circuit doesn't constrain the cell), both contribute.
- **Signature Verification angle** (smart-contract mode): owns application-level signature validation logic (missing `is_valid_signature` check). Angle 5 owns the primitive-level correctness of the signature verification itself.
