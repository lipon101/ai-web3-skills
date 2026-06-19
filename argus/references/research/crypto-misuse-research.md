# Cryptography & Secrets Management — Research Dossier

> **Feeds**: hacking-agents/infra/crypto-misuse-agent.md
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 15 verified advisories/incidents (all primary-source-confirmed this pass) + 3 generic-pattern classes (no specific incident)
> **Status**: drafted-verified — every retained CVE/RUSTSEC/GHSA id was fetched against a primary source this pass confirming BOTH identifier AND mechanism (see §7). Unconfirmable claims are dropped or labelled `[generic pattern — no specific incident]` with NO id.
> **WEB-ACCESS: ok**

> **Anchor case**: Android `SecureRandom` → Bitcoin ECDSA `k`-reuse (2013). A flaw in Android's `java.security.SecureRandom` produced a repeated nonce `k` across ECDSA signatures from the same key. Two such signatures let an attacker cancel the private-key term algebraically and solve for the key by division. Because the defect was in the Android framework (not the ECDSA math), every Android Bitcoin wallet — Bitcoin Wallet for Android, Mycelium, blockchain.info mobile — was affected; ~55.8 BTC was swept to a single attacker address and wallets were patched to seed from a corrected entropy source. **Methodology lesson**: CSPRNG provenance for nonce/key material is a one-line audit check that gates catastrophic, irreversible loss. (Source: Bitcoin Magazine disclosure — §7.)

---

## 0. Calibration headline

Crypto misuse voids the system's foundational guarantee rather than degrading it. An arithmetic overflow loses precision; a crypto bug makes signatures forgeable or keys recoverable. The modal verified failure class is **nonce/`k` reuse and nonce-derived leakage** (ECDSA `k` reuse → key recovery: Android-Bitcoin, Sony PS3; ECDSA nonce *bit-length* leak via timing → key recovery: Minerva, TPM-FAIL). The second cluster is **non-constant-time operation on secrets** (RSA Marvin timing in the Rust `rsa` crate; Lucky Thirteen TLS MAC timing; Minerva). The third is **AEAD / signature API misuse** (Rust `aes-gcm` exposing unauthenticated plaintext; `ed25519-dalek` double-public-key oracle).

Three damage classes:

1. **Private key extraction** — `k` reuse, weak RNG, nonce-bit-length side-channel, double-public-key oracle → attacker recovers the signing key → forges any transaction. Verified instances: Android-Bitcoin, Sony PS3, Minerva, TPM-FAIL, ed25519-dalek (RUSTSEC-2022-0093).
2. **Asset loss / integrity break via forgery or oracle** — signature malleability (python-ecdsa DER), AEAD plaintext exposure on tag-fail (aes-gcm RUSTSEC-2023-0096), under-constrained Merkle proof (Dragonberry), BLS rogue-key without proof-of-possession (BDN).
3. **Silent degradation** — missing zeroisation (zeroize_derive RUSTSEC-2021-0115), non-constant-time RSA (rsa RUSTSEC-2023-0071), weak hash for collision-resistance (SHAttered, MD5 rogue CA).

Tool coverage is weaker for crypto than for arithmetic. `cargo audit` / `cargo deny` catch *known-vulnerable dependency versions* mechanically (all the RUSTSEC ids below are in-scope). `dudect`/`ctgrind` catch timing leaks but need per-function harnesses. Most novel findings are manual-trace; the model's value is knowing WHICH API to grep and what the correct replacement is per framework.

---

## 1. Bug-class taxonomy

| Class | One-line mechanism | Real instance (verified — §7) | Argus coverage |
|-------|--------------------|-------------------------------|----------------|
| **C1 Nonce/`k` reuse** | ECDSA with same `k` for two messages → private key recoverable by algebra. AES-GCM with reused (key, nonce) → forgery/keystream reuse. | Android `SecureRandom`→Bitcoin `k`-reuse (2013) [VERIFIED]; Sony PS3 ECDSA constant-`k` (fail0verflow, 27C3, 2010) [VERIFIED] | **YES** — E05 covers nonce/`k` reuse |
| **C2 Weak / predictable RNG** | CSPRNG that is unseeded, OS-entropy-starved, or platform-stubbed (WASM) → predictable key/nonce material | Android `SecureRandom` unseeded/defective (root cause of C1 instance) [VERIFIED] | **YES** — E01 covers RNG choice |
| **C3 Non-constant-time op on secret** | secret-dependent branch/memory timing leaks the secret; lattice/statistics recover the key | RSA Marvin timing in Rust `rsa` crate, RUSTSEC-2023-0071 / CVE-2023-49092 [VERIFIED]; Lucky Thirteen TLS MAC timing, CVE-2013-0169 [VERIFIED] | **YES** — E02 covers non-CT comparison |
| **C4 Missing / broken zeroisation** | secret bytes not wiped before drop → recoverable from memory/swap; *or* a zeroize-derive bug silently emits no `Drop` | `zeroize_derive` `#[zeroize(drop)]` on enums emitted no `Drop`, RUSTSEC-2021-0115 [VERIFIED] | **YES** — E03 covers zeroisation |
| **C5 Weak hash for security purpose** | MD5/SHA-1 used where collision-resistance is assumed → forgery | SHAttered first practical SHA-1 collision (Google + CWI Amsterdam, 2017) [VERIFIED]; MD5 chosen-prefix rogue CA (2008, Sotirov/Stevens/Appelbaum) [VERIFIED] | **YES** — E04 covers weak hash |
| **C6 Missing curve-point validation** | `decompress`/`from_bytes` without on-curve + subgroup + not-identity → invalid-curve / small-subgroup / identity bypass | [generic pattern — no specific incident]; closest verified adjacent case is the ed25519-dalek API-misuse oracle (C9), not a point-validation CVE | **PARTIAL** — E06 mentions curve validation; no per-curve three-check table |
| **C7 Signature malleability** | ECDSA (r,s)→(r,n−s) or malformed DER accepted → second valid signature / txid mismatch / replay | python-ecdsa accepted non-DER signatures → malleable, CVE-2019-14859 [VERIFIED, cross-language] | **PARTIAL** — §malleability mentions low-S; no EIP-2/BIP-62 + DER-strictness procedure |
| **C8 BLS rogue-key (missing PoP)** | aggregate verified without proof-of-possession per key → attacker derives `PK_a = g^a · PK_h^{-1}`, forges aggregate | Boneh-Drijvers-Neven rogue-key analysis + PoP/plain-pubkey defense (ASIACRYPT 2018) [VERIFIED, academic] | **PARTIAL** — §curve mentions PoP only for Eth2 |
| **C9 Signature-API oracle (double-pubkey / decoupled key)** | API that lets caller pass an arbitrary public key into a deterministic signer → two sigs share `R`, differ in `S` → key extraction | `ed25519-dalek` < 2.0 double-public-key oracle, RUSTSEC-2022-0093 / CVE-2022-50237 [VERIFIED, Rust-native] | **NO** — angle treats verify-side only; signer-API oracle not covered |
| **C10 Nonce-bit-length side-channel (ECDSA)** | scalar-mult leaks nonce bit-length via timing → lattice recovers key over a few hundred–thousand signatures | Minerva (2019, smartcards + libgcrypt/wolfSSL/MatrixSSL/SunEC/Crypto++) [VERIFIED]; TPM-FAIL STMicro ST33 CVE-2019-16863 + Intel PTT CVE-2019-11090 [VERIFIED]; python-ecdsa Minerva CVE-2024-23342 [VERIFIED] | **PARTIAL** — E08 runs dudect but no "identify nonce-bit-length leak" procedure |
| **C11 AEAD plaintext-on-failure** | `decrypt_in_place_*` leaves decrypted-but-unauthenticated plaintext in the buffer after tag-verify failure → CCA / plaintext recovery | Rust `aes-gcm` `decrypt_in_place_detached`, RUSTSEC-2023-0096 / CVE-2023-42811 [VERIFIED, Rust-native] | **NO** — angle does not cover in-place AEAD buffer semantics |
| **C13 Merkle/inclusion-proof verification gap** | proof verifier under-constrains structure (prefix substring-match, no length check) → forge membership of a non-existent leaf | IBC ICS-23 **Dragonberry** — under-constrained leaf-prefix validation (substring vs exact + missing length check), GHSA-j92c-mmf7-j5x5 / VSA-2022-103 (2022) [VERIFIED] | **NO** — angle doesn't cover proof-structure constraints (bridges to ZK verifier angle) |

> **Dropped from prior draft (re-confirmed wrong this pass)**: `juniper` CVE-2022-31173 / RUSTSEC-2022-0054 — verified at NVD to be an **uncontrolled-recursion DoS** (nested GraphQL fragments → stack overflow, CWE-674/CWE-400), NOT a zeroization/secrets-in-memory bug and not crypto. Removed entirely. `CVE-2019-14858` — verified at NVD/RedHat to be an **Ansible `no_log` info-disclosure** bug (sub-parameters not masked on invalid-parameter failure), unrelated to python-ecdsa; replaced with the correct python-ecdsa id (CVE-2019-14859) and the correct mechanism (DER-encoding not verified → malleability, NOT "is_valid accepted out-of-range r/s"). Generic TLS/noise-misconfig and protocol-downgrade patterns retained only as generic patterns below — no specific incident verified this pass.

---

## 2. Per-class methodology

### C1 — Nonce/`k` reuse

**Signal**: ECDSA/DSA signing; AES-GCM/ChaCha20-Poly1305 encryption; any construction whose spec says "unique per call."

**Procedure**:
1. ECDSA: grep `sign` / `sign_digest` / `sign_prehash`. Trace the `k` source. Is it RFC 6979 deterministic (HMAC-DRBG over key+msg) or a fresh CSPRNG call? Constant or repeating low-entropy `k` → key recovery (Sony PS3 used a *constant* nonce; Android-Bitcoin used a *repeating* `k`).
2. Deterministic (RFC 6979): same (key,msg) → same `k` is cryptographically fine. Verify the implementation actually binds the message — a deterministic signer that ignores the message reuses `k` across messages.
3. AES-GCM: grep `encrypt` / `Aes256Gcm::new` / `.encrypt(nonce, …)`. The (key, nonce) pair must be unique across the *protocol lifetime*, not per session. Counter that resets on restart → reuse.
4. **Fuzz**: sign a corpus; flag any duplicate `r` across *different* messages (= `k`-reuse, Critical). Duplicate `(r,s)` for the *same* message under a deterministic signer is expected (safe).

**Golden signature**: two signatures, same `r`, different messages → recover `d` via `d = (s₁·m₂ − s₂·m₁) / (r·(s₂ − s₁)) mod n` style algebra.

**Source**: Android-Bitcoin (2013) [VERIFIED]; Sony PS3 (2010) [VERIFIED] — §7.

### C2 — Weak / predictable RNG

**Signal**: `rand::thread_rng()`, `rand::random()`, `StdRng::from_seed(<const>)`, `seed_from_u64(<predictable>)`, or any seedable PRNG feeding key/nonce material.

**Procedure**:
1. Grep `thread_rng` / `random()` in key-gen/nonce contexts. On standard Linux/macOS `thread_rng` is a CSPRNG (safe). On `wasm32-unknown-unknown` it may resolve to a stubbed/seeded backend — flag in WASM/no_std.
2. Prefer `OsRng` for key generation; confirm it is the source for signing-key, encryption-key, and (non-deterministic) nonce generation.
3. Flag any constant/predictable seed: `from_seed([0u8;32])`, `seed_from_u64(block_height)`, on-chain-state-derived seeds.
4. no_std/embedded: `OsRng` may be unavailable; trace the fallback. Deterministic fallback with a fixed seed → flag.
5. Anchor: the Android-Bitcoin loss was *purely* an RNG-provenance defect — the ECDSA math was correct; the framework's `SecureRandom` produced repeated output.

**Golden signature**: reproduce identical "random" output across two runs, or predict the next value from known state.

**Source**: Android `SecureRandom` defective (2013) [VERIFIED] — §7.

### C3 — Non-constant-time operation on secrets

**Signal**: `==` on `[u8;N]`/`Vec<u8>` secrets; password/MAC/tag compare; RSA/EC decryption or signing in a network-reachable path.

**Procedure**:
1. Grep secret comparisons with `==`; require `subtle::ConstantTimeEq::ct_eq` (or `ring::constant_time::verify_slices_are_equal`).
2. MAC/HMAC verify: confirm the crate compares in constant time (`hmac.verify_slice(tag)` not `tag == computed`).
3. **Network-observable timing**: the Rust `rsa` crate is *known-vulnerable* to the Marvin timing attack (RUSTSEC-2023-0071, **no patched version** as of advisory) — if the dependency tree pins `rsa`, that is a `cargo audit` hit, not a manual finding. Treat any non-constant-time private-key op reachable by a remote timer as the same class.
4. TLS/record MAC: Lucky Thirteen showed that the MAC-check timing on bad CBC padding leaks plaintext. AEAD modes (GCM/ChaCha20-Poly1305) are the fix; flag CBC-MAC-then-something.

**Golden signature**: `dudect` t-statistic over matching vs non-matching (or valid vs edge-invalid) inputs exceeds the noise threshold.

**Source**: rsa Marvin RUSTSEC-2023-0071 / CVE-2023-49092 [VERIFIED]; Lucky Thirteen CVE-2013-0169 [VERIFIED] — §7.

### C4 — Missing / broken zeroisation

**Signal**: key/seed/mnemonic/shared-secret in plain `[u8;N]`, `Vec<u8>`, or `String` without `Zeroize`/`ZeroizeOnDrop`; *and* any reliance on `zeroize_derive`.

**Procedure**:
1. Enumerate every secret-holding type. Each should derive `ZeroizeOnDrop` or wrap bytes in `Zeroizing<…>`.
2. `String::from_utf8(mnemonic_bytes)` reallocates — the source bytes survive. Zeroize both.
3. Rust does NOT guarantee stack zeroing on drop; require explicit `Zeroize`.
4. **Derive-macro footgun**: `zeroize_derive` < 1.2 did NOT implement `Drop` when `#[zeroize(drop)]` was applied to an `enum` (RUSTSEC-2021-0115) — the secret was never wiped despite the annotation. If a vulnerable `zeroize_derive` is pinned, or an enum carries secrets, verify the generated `Drop` actually exists (`cargo expand`). This is a `cargo audit` hit AND a manual check.
5. BPF/Solana: `zeroize` may be a no-op under SBF — confirm the target actually wipes.

**Golden signature**: `cargo expand` shows no `Drop` for the secret enum; or MIRI/valgrind shows secret bytes persisting past scope.

**Source**: zeroize_derive RUSTSEC-2021-0115 [VERIFIED] — §7.

### C5 — Weak hash for security purpose

**Signal**: `Md5`, `Sha1`/`sha1` used for commitment, MAC, certificate, Merkle root, or any collision-resistance-assuming purpose.

**Procedure**:
1. Grep `md5`/`Md5`/`sha1`/`Sha1`/`SHA-1` in non-test, non-content-addressing code.
2. Collision-resistant purpose (commitment, signature, cert, Merkle) → flag. Pre-image-only or non-security (dedup, hash-table) → not a finding.
3. SHA-1: collision-broken since SHAttered (2017 — Google + CWI produced two distinct PDFs with the same SHA-1 digest, requiring ~9.22·10¹⁸ SHA-1 computations). Still acceptable inside HMAC-SHA1 / PBKDF2 (the HMAC construction is unaffected by collisions). Unsafe for signatures/certs/Merkle. Distinguish.
4. MD5: chosen-prefix collisions weaponised since the 2008 rogue-CA work (~2⁴⁹ compressions). Any security use → High.

**Golden signature**: cite the concrete collision attack and demonstrate the broken property (two distinct inputs, same digest, both accepted).

**Source**: SHAttered (2017) [VERIFIED]; MD5 rogue CA (2008) [VERIFIED] — §7.

### C6 — Missing curve-point validation `[generic pattern — no specific incident this pass]`

**Signal**: any `decompress`/`from_bytes`/`deserialize`/`decode` of a public key or curve point from untrusted input.

**Procedure** — three checks, all required:

| Check | Prevents | Verify with |
|-------|----------|-------------|
| On-curve | invalid-curve attack | `decompress().is_some()` (decompress checks the curve equation) / `is_on_curve()` |
| Subgroup membership | small-subgroup attack | `is_torsion_free()` (Ed25519), `is_in_correct_subgroup_assuming_on_curve()` (BLS12-381) |
| Not identity | identity-element shared-secret bypass | `!point.is_identity()` / `!point.is_small_order()` |

**Per-curve**: Ed25519/curve25519 — `EdwardsPoint::is_torsion_free()` covers all three. secp256k1 — cofactor 1, no small-subgroup, but on-curve check still required. BLS12-381 — `from_compressed` needs the subgroup check on deserialized public keys.

**Anti-pattern (FP guard)**: points produced internally (never deserialized from untrusted input) don't need the network-input checks.

**Golden signature**: feed a crafted small-order point to verification; it produces a valid signature. Tier-1-e2e.

**Source**: `[generic pattern — no specific incident]`. No point-validation CVE confirmed this pass; the adjacent verified Rust case is the ed25519-dalek API oracle (C9), which is an API-misuse class, not a missing-point-check class. Do NOT attach a CVE to a point-validation finding without independent confirmation.

### C7 — Signature malleability

**Signal**: ECDSA verify that accepts high-S `(r,s)`; or DER-decoding that doesn't reject non-canonical encodings.

**Procedure**:
1. secp256k1: `(r,s)` is malleable to `(r, n−s)`. Require the low-S rule `s ≤ n/2`. EIP-2 mandates low-S for Ethereum tx; verify the tx-validation path (the `ecrecover` precompile does NOT enforce it).
2. **DER strictness**: python-ecdsa < 0.13.3 did not verify that signatures used DER encoding (CVE-2019-14859), so a malformed signature was accepted → malleable — relevant to *any* verifier that accepts a permissive encoding and later re-signs/forwards the signature (Bitcoin-style). The Rust analogue: verify your decoder rejects non-canonical DER / over-long length octets.
3. Ed25519: not malleable (deterministic, canonical encoding); `ed25519-dalek` `verify_strict` rejects non-canonical encodings.
4. Framework: `k256::ecdsa` normalizes/`verify` checks low-S; `libsecp256k1` normalizes S by default.

**Golden signature**: take a valid `(r,s)`, submit `(r, n−s)` or a re-encoded non-canonical DER blob; if it also verifies → malleable.

**Source**: python-ecdsa DER malleability CVE-2019-14859 [VERIFIED, cross-language precedent] — §7. (EIP-2/BIP-62 are spec references, not incidents.)

### C8 — BLS rogue-key / missing proof-of-possession

**Signal**: BLS aggregation combining public keys from multiple submitters without per-key PoP.

**Procedure**:
1. Attack algebra: attacker sees honest `PK_h`, registers `PK_a = g^a · PK_h^{-1}`; aggregate `PK_h · PK_a = g^a`; attacker signs as the aggregate with `a` alone — no honest secret used.
2. Defense: before aggregation, require each key carry a proof-of-possession (a signature by that key over its own public key), OR use the BDN scheme, which is secure against rogue-key attacks in the plain public-key model (no KOSK/PoP requirement). Grep `aggregate` / `fast_aggregate_verify`; confirm a prior `pop_verify` step or BDN-style aggregation.
3. Eth2: PoP is enforced at validator deposit, not in the aggregation path — verify both the deposit-validation and the aggregation code.

**Anti-pattern (FP guard)**: single-signer BLS (no aggregation) is not exposed to rogue-key; the attack needs key aggregation.

**Golden signature**: craft `PK_a = g^a · PK_h^{-1}`, forge an aggregate signature with no honest secret. Tier-1-e2e.

**Source**: Boneh, Drijvers, Neven, "Compact Multi-Signatures for Smaller Blockchains," ASIACRYPT 2018 [VERIFIED, academic] — §7.

### C9 — Signature-API oracle (decoupled / double public key)

**Signal**: a signing API that accepts a *separately-supplied* public key (or a keypair assembled from independent private+public halves) into a deterministic signer — especially serialize/deserialize of 64-byte private||public keypairs.

**Procedure**:
1. The flaw (ed25519-dalek < 2.0): in EdDSA the public key feeds the deterministic computation of `S` but NOT `R`. If an attacker can drive the signer with an *arbitrary* public key on a fixed message, two calls produce the same `R`, different `S` → the private scalar is recoverable.
2. Grep for APIs that build a signer from decoupled key halves, or that assemble a `Keypair` from independent public + private types. Confirm the crate version: ed25519-dalek ≥ 2.0 redesigned the APIs so decoupled usage is only reachable through clearly-labelled `hazmat` functions.
3. Generalise: any deterministic signer where the public key is an *input* rather than *derived from the secret* is a candidate oracle.

**Anti-pattern (FP guard)**: a signer that derives the public key internally from the secret (the safe default) is not exposed.

**Golden signature**: obtain two signatures over one message with two different supplied public keys; if they share `R`, extract the key. Tier-1-e2e.

**Source**: ed25519-dalek RUSTSEC-2022-0093 / CVE-2022-50237 [VERIFIED, Rust-native] — §7.

### C10 — Nonce-bit-length side-channel (ECDSA scalar-mult)

**Signal**: ECDSA signing whose scalar multiplication runtime depends on the nonce's bit-length (non-constant-time double-and-add, early-terminating loops).

**Procedure**:
1. The leak (Minerva / TPM-FAIL): timing of the scalar-mult correlates with the bit-length of the per-signature nonce. Collecting a few hundred to a few thousand signatures + lattice reconstruction recovers the long-term key (Minerva: ~500 simulated, ~1,200 library, ~2,100 smartcard signatures).
2. Grep the scalar-mult / signing inner loop. Does iteration count or branch structure depend on the scalar's leading zeros? Fixed-window / constant-time ladder = safe; variable-length loop = candidate.
3. Confirm the underlying crate is constant-time. The Rust-relevant cross-language precedent: python-ecdsa's pure-Python scalar-mult is Minerva-vulnerable and explicitly WONTFIX (CVE-2024-23342) — a reminder that "pure-language, no asm" implementations are prone to this.
4. Run `dudect` distinguishing nonces with different bit-lengths.

**Golden signature**: `dudect` shows runtime separation between short-nonce and full-length-nonce signing; or a lattice PoC recovers the key from N collected signatures.

**Source**: Minerva (2019) [VERIFIED]; TPM-FAIL CVE-2019-16863 (STMicro ST33) / CVE-2019-11090 (Intel PTT) [VERIFIED]; python-ecdsa CVE-2024-23342 [VERIFIED] — §7.

### C11 — AEAD plaintext-on-failure (in-place decrypt)

**Signal**: `decrypt_in_place` / `decrypt_in_place_detached` whose buffer is read by the caller after the call.

**Procedure**:
1. The flaw (aes-gcm 0.10.0–0.10.2, RUSTSEC-2023-0096): on tag-verification failure these APIs return `Err`, but because decryption happens in-place, the buffer now holds the *decrypted-but-unauthenticated* plaintext. A caller that ignores the error and reads the buffer leaks plaintext / enables a CCA oracle. The 0.10.3 fix re-encrypts the buffer before returning the error.
2. Grep `decrypt_in_place*`; confirm the caller treats `Err` as fatal and never reads the buffer on failure, AND the pinned `aes-gcm` is ≥ 0.10.3.
3. Generalise to any AEAD with in-place APIs (chacha20poly1305, aes-gcm-siv): the buffer must be considered poisoned on tag failure.

**Anti-pattern (FP guard)**: detached APIs used with the `aes-gcm` ≥ 0.10.3 fix (buffer restored on failure) are safe; the finding is version- and usage-gated.

**Golden signature**: submit a ciphertext with a bad tag, observe recoverable plaintext in the buffer post-call.

**Source**: aes-gcm RUSTSEC-2023-0096 / CVE-2023-42811 [VERIFIED, Rust-native] — §7.

### C13 — Merkle / inclusion-proof verification gap

**Signal**: light-client or bridge code verifying an inclusion/membership proof from another chain.

**Procedure**:
1. Minimum constraints a membership-proof verifier MUST enforce: (a) computed root == trusted root; (b) the *exact* leaf key→value being proved (not "a leaf exists"); (c) **exact** structural constraints on prefixes/suffixes/path — not substring/prefix-of matches; (d) one consistent hash function across the path.
2. **Dragonberry lesson (the precise mechanism)**: ICS-23 only required that an input leaf prefix *contain* the standard spec's prefix as its prefix (substring/prefix-of), not match it exactly, with no length check. Because proof parameters (leaf prefix, hash functions) are embedded in the proof itself and validated only for consistency, an attacker whose tree already contains a key shaped `…|len(subkey)|subkey` could forge a membership proof for a *non-existent* subkey by extending the leaf prefix. The fix added explicit length checks on leaf/inner-node prefixes and suffixes to enforce exact compliance. **Audit action**: for any proof spec with attacker-influenced structural fields, verify equality + length bounds, not containment.
3. Hand-rolled Merkle verifier → High; prefer `ics23` (Cosmos) and pin a post-Dragonberry version.
4. Empty/zero-step proof: a proof with no path can make `computed_root == leaf_hash` → check for and reject degenerate proofs.

**Golden signature**: craft a proof for a non-existent leaf (via prefix extension or empty path) that verifies against the real root. Tier-1-e2e.

**Source**: IBC ICS-23 Dragonberry GHSA-j92c-mmf7-j5x5 / Verichains VSA-2022-103 (2022) [VERIFIED] — §7.

---

## 3. Framework-specific knowledge

### Cosmos SDK / IBC
- **ICS-23 proofs**: always use the `ics23` crate; pin a **post-Dragonberry** version. Dragonberry proved the *spec itself* was under-constrained (substring leaf-prefix match, no length check) — verify equality + length bounds on any structural proof field, and that the project tracked the VSA-2022-103 / Dragonberry advisory.
- **BLS (bls12-381)**: subgroup-check deserialized G1/G2 public keys before use; require PoP or BDN aggregation for multisig.
- Rust IBC reimplementations of Go `PrivKey` must add explicit `Zeroize` (Go relied on GC).

### Tendermint / CometBFT
- **Ed25519 consensus votes**: `ed25519-consensus` or `ed25519-dalek` `verify_strict()`. Forged votes = chain takeover.
- **State proofs**: `tendermint-rs` uses `ics23` — confirm the version is not Dragonberry-affected.

### Ethereum (execution + consensus)
- **BLS12-381 validator sigs**: `blst` (preferred). PoP enforced at deposit, not in `fast_aggregate_verify` — audit both.
- **secp256k1 tx sigs**: the `ecrecover` precompile does NOT enforce low-S; EIP-2 enforces it at tx-validation. Audit the validation path.
- **Keccak256 ≠ SHA3-256**: confirm `sha3`/`tiny-keccak` Keccak mode, not NIST SHA3.

### Solana
- **Ed25519 / secp256k1 syscalls** enforce strict/low-S at the runtime. Programs that hand-roll these in SBF lose the guarantee — audit those.
- **Zeroize under SBF** may be a no-op; verify secrets are actually wiped on-target.

### Substrate / Polkadot
- **sr25519 (schnorrkel)** native scheme; ensure `schnorrkel`, not a hand-rolled signer.
- **ed25519 GRANDPA finality**: `verify_strict()`.
- **`sp_core::Pair`** zeroises on `Drop`; hand-rolled `[u8;32]` key wrappers without `Zeroize` → flag (cross-check the zeroize_derive enum footgun, C4).

### CosmWasm
- `cosmwasm-crypto` wraps `ed25519-dalek` / `k256`; confirm strict verification.
- No OS entropy in WASM → contracts cannot generate secure keys on-chain. Flag any contract deriving key material from block/WASM randomness (direct line to C2).

### RustCrypto crate footguns (verified advisories to grep dependency trees for)
- `rsa` non-constant-time (Marvin, RUSTSEC-2023-0071) — **no patched version** as of advisory; flag network-reachable RSA private-key ops.
- `aes-gcm` 0.10.0–0.10.2 in-place plaintext-on-failure (RUSTSEC-2023-0096); fixed 0.10.3.
- `ed25519-dalek` < 2.0 double-public-key oracle (RUSTSEC-2022-0093) — upgrade to 2.0, avoid decoupled-keypair APIs.
- `zeroize_derive` < 1.2 enum `Drop` omission (RUSTSEC-2021-0115).

---

## 4. Tooling

| Tool | What it checks | Golden signature | Invoke |
|------|---------------|------------------|--------|
| **cargo audit / cargo deny** | dependency tree vs RUSTSEC advisories — catches all four crate ids above mechanically | advisory hit on `rsa`/`aes-gcm`/`ed25519-dalek`/`zeroize_derive`/`ics23` | `cargo audit` / `cargo deny check advisories` |
| **cargo expand** | reveals macro-generated `Drop` — confirms `#[zeroize(drop)]` actually emitted one (C4) | no `impl Drop` for a secret-bearing enum | `cargo expand <module>` |
| **dudect** | timing side-channel: runtime vs secret bits (C3, C10) | t-statistic over input classes exceeds threshold | custom `#[test]` harness |
| **ctgrind (valgrind)** | secret-dependent branch / memory access | "Conditional jump … depends on uninitialised value" on a secret | `valgrind --tool=memcheck` w/ poisoned secret |
| **proptest (nonce reuse)** | fuzz signer, detect duplicate `r` across messages (C1) | two sigs, same `r`, different messages | `proptest!` over message corpus |
| **MIRI** | UB / uninitialised access in unsafe crypto; residual-secret checks | MIRI error on secret buffer | `cargo +nightly miri test` |
| **Pattern grep** | `thread_rng` in key-gen, `md5`/`sha1` in security context, `==` on secrets, `decrypt_in_place*`, decoupled-keypair APIs | grep hit + manual context triage | `rg` |

---

## 5. Discovery calibration

- **Highest-ROI sequence** (impact per effort):
  1. `cargo audit` / `cargo deny` — 5 min, catches every RUSTSEC id above (rsa, aes-gcm, ed25519-dalek, zeroize_derive, ics23) without reasoning.
  2. Grep `thread_rng`/`random()` in key-gen/nonce contexts → WASM/no_std triage.
  3. Grep `md5`/`sha1` → collision-resistance context only.
  4. Grep `==` on secret `[u8 …` → require `ct_eq`.
  5. Grep `decrypt_in_place*` → confirm error-on-failure handling + crate ≥ 0.10.3.
  6. Grep decoupled-keypair / caller-supplied-pubkey signer APIs (C9).
  7. `dudect` on signing / verify (Thorough only) for C3/C10.
- **FP discipline**: `thread_rng` on Linux/macOS is a valid CSPRNG — the finding is real only on WASM/no_std. AEAD in-place misuse is gated on both version AND caller behaviour. Point-validation (C6) has NO verified CVE this pass — never attach an id to it.
- **Severity spread**: confirmed `k`-reuse / key-extraction (C1, C9, C10) = Critical; AEAD-plaintext-leak and proof-forgery (C11, C13) = High; a `thread_rng` finding on a server target = Informational.

---

## 6. Gaps → angle changes

| Methodology | Change type | Anti-bloat check |
|-------------|-------------|------------------|
| **C6 per-curve three-check table** (on-curve / subgroup / not-identity) — keep as *generic pattern*, no id attached | extend E06 | E06 mentions curve validation but lacks the structured table; no verified incident to over-anchor on, so frame as methodology. |
| **C7 malleability** — add low-S enforcement + **DER-canonicalisation** check (CVE-2019-14859 mechanism), per-crate (`k256` vs `libsecp256k1`) | extend §malleability | current coverage is one sentence; add procedure + the verified DER-malleability precedent. |
| **C9 signer-API oracle** — NEW: detect decoupled-keypair / caller-supplied-pubkey deterministic signers (ed25519-dalek class) | new-check | not covered; the angle only examines verify-side. Verified Rust-native (RUSTSEC-2022-0093). |
| **C10 nonce-bit-length leak** — extend E08: identify variable-length scalar-mult before running dudect; cite Minerva/TPM-FAIL signature-count thresholds | extend E08 | E08 says "run dudect" but not how to spot the candidate loop. |
| **C11 AEAD in-place plaintext-on-failure** — NEW: `decrypt_in_place*` buffer-poisoning + version gate | new-check | not covered; verified Rust-native (RUSTSEC-2023-0096). |
| **C13 proof-structure constraints** — NEW: equality-not-substring + length bounds on attacker-influenced proof fields (Dragonberry mechanism), empty-proof rejection | new-check | not covered; verified (Dragonberry). Bridges to ZK verifier angle but applies to non-ZK light clients. |
| **Phase 1 pre-seed** — add `cargo audit` + `cargo deny` + the high-signal grep set as a Phase 1 step | tool-integration | mirrors ZK/Arithmetic agents; +5 lines. Mechanically catches all five advisory ids. |

---

## 7. Sources

> Every retained CVE/RUSTSEC/GHSA id below was fetched this pass against a primary source confirming BOTH the identifier AND the mechanism. Access date: 2026-06-05.

**Tier 1 — verified real-world incidents (post-mortem / disclosure with root cause)**
- Android `SecureRandom` → Bitcoin ECDSA `k`-reuse (2013). Bitcoin Magazine disclosure: https://bitcoinmagazine.com/technical/critical-vulnerability-found-in-android-wallets-1376273924 — confirms defective `java.security.SecureRandom` producing repeated `k`, two-signature key recovery, ~55.8 BTC swept, affected Bitcoin Wallet for Android / Mycelium / blockchain.info mobile; ECDSA math itself was correct.
- Sony PS3 ECDSA constant-`k` (fail0verflow, 27C3, Dec 2010). https://en.wikipedia.org/wiki/PlayStation_3_homebrew — confirms private signing key recovered "due to a failure of Sony's ECDSA implementation to generate a different random number for each signature."
- SHAttered — first practical SHA-1 collision (Google + CWI Amsterdam, 23 Feb 2017). Google Security Blog: https://security.googleblog.com/2017/02/announcing-first-sha1-collision.html ; CWI announcement: https://www.cwi.nl/en/news/cwi-and-google-announce-first-collision-for-industry-security-standard-sha-1/ — two distinct PDFs with the same SHA-1 digest, ~9,223,372,036,854,775,808 (~9.22·10¹⁸) SHA-1 computations.
- MD5 chosen-prefix rogue CA certificate (Sotirov, Stevens, Appelbaum et al.; CCC Dec 2008). Project page: https://www.win.tue.nl/hashclash/rogue-ca/ ; paper (CRYPTO 2009): https://marc-stevens.nl/research/papers/CR09-SSALMOdW.pdf — chosen-prefix MD5 collision → browser-trusted rogue CA. (Retained from sound prior draft; mechanism unchanged.)
- Lucky Thirteen — TLS/DTLS CBC MAC-check timing (AlFardan & Paterson, RHUL, Feb 2013), CVE-2013-0169. https://www.isg.rhul.ac.uk/tls/Lucky13.html ; https://en.wikipedia.org/wiki/Lucky_Thirteen_attack (confirms "assigned and tracked as CVE-2013-0169", CBC-mode MAC-verification timing leaks plaintext).
- Minerva — ECDSA nonce bit-length leak via timing → lattice key recovery (CRoCS, Masaryk University, 2019). https://minerva.crocs.fi.muni.cz/ — affected Athena IDProtect smartcard + libgcrypt(≤1.8.4)/wolfSSL(≤4.0.0)/MatrixSSL/SunEC/Crypto++/python-ecdsa; ~500–2,100 signatures depending on noise.
- TPM-FAIL — ECDSA scalar-mult timing in TPMs → lattice key recovery (Moghimi et al., USENIX Security 2020). CVE-2019-16863 (STMicroelectronics ST33): https://nvd.nist.gov/vuln/detail/CVE-2019-16863 ("extract the ECDSA private key via a side-channel timing attack because ECDSA scalar multiplication is mishandled"). CVE-2019-11090 (Intel PTT/TXE/SPS — "Cryptographic timing conditions in the subsystem for Intel PTT"): https://nvd.nist.gov/vuln/detail/CVE-2019-11090 . Project: https://tpm.fail/ .
- IBC ICS-23 **Dragonberry** — under-constrained leaf-prefix validation (input prefix only required to *contain* the standard prefix, no length check) → forged membership proof for a non-existent subkey. Verichains VSA-2022-103: https://blog.verichains.io/p/vsa-2022-103-cosmos-sdk-forging-membership ; advisory GHSA-j92c-mmf7-j5x5: https://github.com/cheqd/cheqd-node/security/advisories/GHSA-j92c-mmf7-j5x5 (2022).

**Tier 3 — verified RUSTSEC / CVE advisories (Rust-native unless noted)**
- `ed25519-dalek` < 2.0 — Double Public Key Signing Oracle → private key extraction (public key feeds `S` but not `R`; arbitrary-pubkey oracle → two sigs share `R` → key recovery). RUSTSEC-2022-0093 / CVE-2022-50237. https://rustsec.org/advisories/RUSTSEC-2022-0093.html (Rust-native).
- `zeroize_derive` < 1.2 — `#[zeroize(drop)]` on enums did not implement `Drop` → secrets not wiped. RUSTSEC-2021-0115. https://rustsec.org/advisories/RUSTSEC-2021-0115.html (Rust-native).
- `rsa` — Marvin Attack, non-constant-time RSA decryption → private-key info leaked via network-observable timing; **no patched version** as of advisory. RUSTSEC-2023-0071 / CVE-2023-49092. https://rustsec.org/advisories/RUSTSEC-2023-0071.html (Rust-native).
- `aes-gcm` 0.10.0–0.10.2 — `decrypt_in_place_detached` leaves unauthenticated plaintext in buffer on tag-verify failure → CCA / full plaintext recovery; fixed 0.10.3 (re-encrypts buffer on failure). RUSTSEC-2023-0096 / CVE-2023-42811. https://rustsec.org/advisories/RUSTSEC-2023-0096.html (Rust-native).
- `python-ecdsa` — Minerva timing (non-constant-time scalar-mult leaks nonce bit-length) → key recovery; WONTFIX (pure-Python project, side-channels out of scope). CVE-2024-23342 / GHSA-wj6h-64fc-37mp. https://github.com/tlsfuzzer/python-ecdsa/security/advisories/GHSA-wj6h-64fc-37mp (cross-language precedent).
- `python-ecdsa` < 0.13.3 — DER encoding not verified in signatures → malformed signature accepted → signature malleability. CVE-2019-14859. https://bugzilla.redhat.com/show_bug.cgi?id=CVE-2019-14859 (cross-language precedent).

**Tier 5 — academic (verified)**
- Boneh, Drijvers, Neven — "Compact Multi-Signatures for Smaller Blockchains," ASIACRYPT 2018 (Brisbane, Dec 2018). https://eprint.iacr.org/2018/483 ; https://crypto.stanford.edu/~dabo/abstracts/BLSmultisig.html — BLS multi-signatures secure against rogue-key attack in the plain public-key model (defense to the C8 rogue-key algebra).

**Tier 6 — tooling (reference, not incident claims)**
- cargo-audit / RustSec: https://rustsec.org/ · https://github.com/rustsec/advisory-db
- dudect: https://github.com/oreparaz/dudect
- `subtle` (`ConstantTimeEq`): https://docs.rs/subtle/ · `zeroize`: https://docs.rs/zeroize/ · `ed25519-dalek`: https://docs.rs/ed25519-dalek/

**Explicitly corrected / removed this pass (re-verified)**
- `CVE-2019-14858` — REMOVED. Verified at NVD/RedHat to be an **Ansible `no_log` info-disclosure** bug (sub-parameters not masked on invalid-parameter failure), NOT python-ecdsa. https://nvd.nist.gov/vuln/detail/CVE-2019-14858 . The correct python-ecdsa malleability id is CVE-2019-14859 (DER-encoding not verified), used above. The prior "is_valid accepted out-of-range r/s" mechanism was unverifiable and is dropped.
- `CVE-2022-31173` / RUSTSEC-2022-0054 (`juniper`) — REMOVED. Verified at NVD to be **uncontrolled-recursion DoS** (nested GraphQL fragments → stack overflow, CWE-674/CWE-400), not a zeroization/secrets-in-memory bug and not crypto. https://nvd.nist.gov/vuln/detail/CVE-2022-31173 .
- Dragonberry root cause CORRECTED (and re-verified this pass) from "missing subkey verification" to **under-constrained leaf-prefix validation (input prefix only required to contain the standard prefix; substring vs exact match + missing length check)** per Verichains VSA-2022-103.
- Heartbleed — REMOVED from the zeroization class (it is an out-of-bounds memory *disclosure*, not a missing-zeroise bug); the verified Rust-native zeroization advisory is RUSTSEC-2021-0115.

---

## 8. Immediate action items

1. Extend E06 with the per-curve three-check table — framed as methodology (`[generic pattern]`, no id).
2. Extend §malleability with low-S + DER-canonicalisation procedure, citing the verified CVE-2019-14859 mechanism.
3. Add C9 signer-API-oracle CHECK (ed25519-dalek decoupled-keypair class, RUSTSEC-2022-0093).
4. Extend E08 with "identify variable-length scalar-mult" before dudect (Minerva/TPM-FAIL).
5. Add C11 AEAD in-place plaintext-on-failure CHECK, version-gated (RUSTSEC-2023-0096).
6. Add C13 proof-structure-constraint CHECK (equality-not-substring + length bounds + empty-proof rejection), citing Dragonberry.
7. Add Phase 1 `cargo audit` / `cargo deny` pre-seed — mechanically catches all five Rust advisory ids.
8. Update RESEARCH-INDEX.md — mark Crypto Misuse as "drafted-verified."

---

> **AI-provenance reminder**: This dossier was assembled by an AI agent. Every CVE/RUSTSEC/GHSA id and named incident above was fetched against a primary source this pass (URLs in §7), but identifiers, version ranges, and mechanisms can still be misread or change as advisories are updated. Before wiring any item into angle methodology or citing it in a finding, a human MUST re-open the linked primary source and re-confirm the id, affected versions, and mechanism. Items labelled `[generic pattern — no specific incident]` carry NO identifier by design — do not attach a CVE to them without independent verification.
