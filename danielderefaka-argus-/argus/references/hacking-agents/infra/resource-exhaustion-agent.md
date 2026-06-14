# Resource Exhaustion & DoS Agent (`infra` mode — Angle 6)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, devil's-advocate, pre-auth panic sweep, asymmetric-cost quantification, resource-bounds, eclipse/peer-table, cross-domain-deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

**Research grounding**: [`resource-exhaustion-research.md`](../../research/resource-exhaustion-research.md) — 12-class bug taxonomy (F01–F12) anchored in real RustSec DoS advisories (rust-libp2p pre-allocation buffering RUSTSEC-2022-0084; the ckb unbounded peer-score map RUSTSEC-2021-0108), the Ethereum devp2p UDP reflection/amplification class, and production DLT DoS vulnerabilities. Every CHECK below is traceable to a bug class in the dossier.

> **Calibration**: Resource exhaustion is the most asymmetric attack class in DLT infrastructure: the attacker spends kilobytes of network traffic to consume gigabytes of validator memory or CPU. A single validator brought down by DoS reduces network security. Three sub-classes dominate: **(1) Unbounded allocation from attacker-controlled size** — a length field from an untrusted message feeds `Vec::with_capacity(n)` without a max cap; the devp2p class. **(2) Algorithmic complexity attacks** — quadratic loops, HashDoS collision insertion, regex backtracking — where small crafted input triggers disproportionate resource consumption. **(3) Pre-auth resource consumption** — memory or CPU burned BEFORE any authentication check, so an unauthenticated attacker can exhaust the server trivially.
>
> Tooling is strong: `cargo-fuzz` finds allocation-explosion and OOM-panic paths; ASan finds memory exhaustion; manual static analysis finds unbounded collection patterns. The LLM's advantage is identifying the attacker-controlled INPUT source and tracing it across functions to the resource-consumption SINK — a cross-function trace that static analyzers don't do.

**Primary verification backends**: `cargo-fuzz` + libfuzzer for OOM/panic explosion; AddressSanitizer for large-heap detection; criterion benchmarks for algorithmic complexity regression; manual stress tests for connection/leak exhaustion. Vectors in **Group F** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical findings:

1. **High-signal grep patterns**:
   ```bash
   # Unbounded growth patterns — CHECK 1
   rg '\.push\(' --type rust -l
   rg '\.insert\(' --type rust -l
   rg '\.extend\(' --type rust -l
   # Large allocation from attacker-controlled capacity — CHECK 5
   rg 'with_capacity\(' --type rust -l
   rg 'vec!\[.*;' --type rust -l
   rg 'String::with_capacity' --type rust -l
   # Hasher patterns — CHECK 7
   rg 'FxHash' --type rust -l
   rg 'BuildHasherDefault' --type rust -l
   rg 'with_seed' --type rust -l   # fixed-seed ahash
   # Decompression without size cap — CHECK 9
   rg 'zstd::decode' --type rust -l
   rg 'flate2::read::GzDecoder' --type rust -l
   rg 'snap::read::FrameDecoder' --type rust -l
   # Clone chains — CHECK 6
   rg '\.clone\(\)' --type rust -l
   # Regex — CHECK 8
   rg 'regex::|fancy_regex::|pcre2::' --type rust -l
   # Recursive functions — CHECK 3
   rg 'fn \w+\(.*\) \{[^}]*\w+\(' --type rust -l  # coarse; refine per-file
   # Connection leaks — CHECK 10
   rg '\.subscribe\(' --type rust -l
   rg 'ws://' --type rust -l
   rg 'PubSub' --type rust -l
   # tokio::time::timeout — CHECK 12
   rg 'tokio::time::timeout' --type rust -l
   # Pre-auth — CHECK 11 (manual trace from this signal)
   rg '#\[tokio::test\]' --type rust -l  # RPC test files as entry points
   rg '\.authenticate\(|\.verify_signature|\.check_auth' --type rust -l
   ```

2. **Build a cargo-fuzz harness for the project** (if fuzzable targets exist):
   ```bash
   cargo fuzz init
   ```
   Seed a target that feeds malformed/gigantic inputs to deserialization and message processing entry points.

---

## Phase 2: Resource surface inventory

Enumerate every resource-consuming surface:

- **Allocation sites on attacker-accessible paths**: every `Vec::push`, `HashMap::insert`, `with_capacity`, `clone`, `format!`, `to_string`, `to_owned` reachable from network input, RPC parameters, p2p message deserialization, or mempool submission.
- **Loop constructs with attacker-controlled bounds**: every `for`, `while`, `loop` where the iteration count depends (directly or transitively) on untrusted input.
- **Recursive functions**: every function that calls itself or participates in a mutual-recursion cycle with input influencing depth.
- **Decompression/decoding sites**: every call to a decompression or decoding library on data from the network.
- **Hash maps with non-SipHash hasher**: every `HashMap`/`HashSet` using `FxHash`, `ahash` with fixed seed, or custom `BuildHasher` on attacker-accessible paths.
- **Network operations without timeouts**: every `read`, `write`, `recv`, `accept` without a `tokio::time::timeout` wrapper.
- **Subscription/registration sites**: every `.subscribe()`, event listener registration, or connection pool insertion where unsubscription is not guaranteed on disconnect.
- **Pre-auth code paths**: every operation between packet receipt and authentication completion.

---

## Phase 3: Per-class checks

### CHECK 1 — Unbounded queue/collection growth (F01)

**Signal**: `Vec::push`, `HashMap::insert`, `.extend()`, or `+=` in a loop driven by attacker-controlled input with no max-size check.

**Procedure**:
1. For every collection mutation on a network-accessible path: is there a bound check before the mutation (e.g., `if queue.len() < MAX_QUEUE_SIZE { push }` or `ensure!(queue.len() < MAX, Error::Full)`)?
2. Trace the loop bound: does the attacker control how many iterations run? If the loop pushes one item per iteration, the attacker controls total collection size.
3. **Growth-without-bound**: `HashMap::insert` in a loop is especially dangerous because the map resizes automatically — attacker drives O(n) insertions, map reallocates log(n) times, total cost > O(n).
4. **Producer/drain audit (interrogate BOTH sides separately)**: for every long-lived collection field on connection/session/node state (not a local), answer two questions independently — (a) **Producer**: what caps the insert side, or is it driven directly by attacker message volume? (b) **Drain**: what bounds removal, and *who controls its rate*? A collection is exploitable if EITHER the producer is uncapped OR the drain rate is attacker-controllable while the producer is not.
5. **Back-pressure drain (yamux shape)**: an outbound queue drained only when the socket is writable is attacker-controlled — the peer closes its TCP receive window to stall the drain while the producer keeps appending. A length-prefix audit misses this; trace the drain-rate controller of every outbound queue, not just the producer cap.
6. **Monotonic-key / no-eviction (ckb shape)**: a `HashMap` keyed on a monotonically-increasing id (`SessionId`/`PeerIndex`, request id, peer counter) with inserts but no `.remove()` on disconnect/cleanup is unbounded by construction — every reconnect adds a permanent entry. Grep for maps keyed on counter-like types with no removal path.
7. Severity: HIGH if the collection grows without bound AND the service allocates memory linearly with attacker input. CRITICAL if the collection is in a pre-auth path (F11 context).

**Golden signature**: Fuzz with N=MAX items; observe OOM or RSS explosion. For the drain-controlled and monotonic-key shapes: integration test that drives the producer (open streams / trigger violations / reconnect) while refusing to read the socket, then asserts the collection's len/RSS grows without bound.

**Source**: Ethereum devp2p neighbor table unbounded growth [model-knowledge]; libp2p gossipsub peer-score map [model-knowledge].

---

### CHECK 2 — Quadratic / superlinear complexity (F02)

**Signal**: Nested loops where both outer and inner bounds are attacker-controlled; `O(n²)` or worse in message processing.

**Procedure**:
1. For every nested loop on a network-accessible path: can the attacker control both loop bounds? If outer is N messages and inner is M items per message → attacker sends N messages each with M items → O(N×M) operations.
2. **Cross-request accumulation**: a single request bounds inner/outer, but an attacker sends N sequential requests → effective O(N) per-request, and N is unbounded. This is still DoS but the per-request bound makes it less severe than unbounded-nested.
3. **Iterator chains**: `.filter().map().collect()` on attacker-controlled iterators — each filter pass is O(n), chaining 3 filters is 3n, not n³, but if one filter produces n² elements, that feeds the next stage.
4. Severity: HIGH if both bounds are attacker-controlled with no cap. MEDIUM if one bound is capped but the product still high (e.g., max 1000 × max 1000 = 1M operations per request).

**Golden signature**: Benchmark: time-vs-input-size plot with linear size increase → superlinear time curve (`cargo bench` or manual timing).

**Source**: JSON-RPC batch request quadratic processing [model-knowledge]; Tendermint mempool transaction recheck [model-knowledge].

---

### CHECK 2b — Reset/cancel-driven server work (Rapid-Reset class)

**Signal**: A protocol state machine where a *client-initiated* transition (cancel, reset, abort, unsubscribe-then-resubscribe) is cheap to send but triggers server-side allocation/cleanup that is deferred or asynchronous.

**Procedure**:
1. Identify every client-controllable transition that does NOT count against a concurrency/rate limit — Rapid Reset's core: a cancelled stream stops counting toward max-concurrent-streams, so the cap is bypassed.
2. For each: does it create server-side work (queue an item, spawn a task, allocate a buffer) cleaned up *lazily* relative to how fast the client can re-trigger?
3. If the client can re-trigger faster than cleanup completes → backlog accumulates → DoS. The defense is to bound *outstanding work*, not just *concurrent active items*.
4. **Receive-window variant (h2 shape)**: a flood of invalid frames forces the server to generate reset frames that queue behind a peer-closed receive window → OOM + CPU. Bound the number of internal-error/forced resets before closing the connection.
5. Severity: HIGH if a cheap transition bypasses the concurrency cap and outstanding work is uncapped. MEDIUM if outstanding work is capped but cleanup is slow.

**Golden signature**: Load test flipping the state machine (open→reset) in a tight loop while measuring server-side queue depth / task count; assert it stays bounded.

**Source**: HTTP/2 Rapid Reset — CVE-2023-44487; `h2` remote-reset pending-accept queue — RUSTSEC-2023-0034 / CVE-2023-26964; `h2` invalid-frame forced-reset queue — RUSTSEC-2024-0003 / CVE-2019-9514. See `resource-exhaustion-research.md` §F02.

---

### CHECK 3 — Deep recursion / stack overflow (F03)

**Signal**: Recursive function processing attacker-controlled input with no depth limit.

**Procedure**:
1. For every recursive or mutually-recursive function reachable from network input: is there a max depth check? Pattern: `if depth > MAX_DEPTH { return Err(...) }` at function entry.
2. **Implicit recursion depth**: deserialization of nested structures (JSON arrays, RLP lists) can recurse through the parser. Serde's default deserialization has a recursion limit — but custom `Deserialize` impls may bypass it.
3. **Tail recursion**: Rust does NOT guarantee tail-call optimization. Even a tail-recursive function without a depth limit can overflow the stack.
4. Severity: HIGH if no depth limit and the recursion depth is attacker-controlled. MEDIUM if limited by a compile-time constant that's too generous (>1000).

**Golden signature**: Fuzz with deeply nested input; observe stack overflow panic or SIGSEGV.

**Source**: JSON/RLP parser recursion without depth limit [model-knowledge]; Ethereum trie node recursion [model-knowledge].

---

### CHECK 4 — Lock held across I/O causing DoS (F04)

**Signal**: `MutexGuard` / `RwLockWriteGuard` / `.lock().await` held across `.await` that performs network I/O.

**Procedure**: See Concurrency Agent CHECK 9 (lock-held-across-await). This is a joint class. From the resource-exhaustion perspective: the lock-holder consumes one thread/task, and every other task blocked on the same lock is a resource drain. If the I/O is slow (attacker-controlled peer slow-walks a response), the lock becomes a DoS primitive.

**Golden signature**: Loom model + stress test: slow peer while other tasks queue on the same lock.

**Source**: Parity Ethereum block import lock during I/O [model-knowledge].

---

### CHECK 5 — Large allocation from attacker-controlled capacity (F05)

**Signal**: `Vec::with_capacity(n)`, `HashMap::with_capacity(n)`, `String::with_capacity(n)`, `vec![0; n]`, `vec![default(); n]` where `n` is derived from untrusted input without a max cap.

**Procedure**:
1. For every `with_capacity` call where the capacity argument traces to network input, RPC parameter, deserialized message, or peer-supplied data: is there a `max_cap` guard BEFORE the allocation?
2. **Borsh/scale-codec/serde**: these allocate based on the serialized data's declared size. `borsh::BorshDeserialize` on `Vec<T>` reads a `u32` length prefix then calls `Vec::with_capacity(len)`. The length is attacker-controlled. Mitigation: use `borsh::de::BorshDeserialize::deserialize_reader` with `std::io::Read::take(max_bytes)` to cap total bytes, or validate the length against a constant before deserialization.
3. **Prost/protobuf**: similar class — protobuf repeated fields allocate based on the encoded length. Cap the message size before deserialization.
4. **`vec![0; n]` / `vec![default(); n]`**: the Repeat expression allocates `n * size_of::<T>()` bytes. If `n` is attacker-controlled and `T` is large (e.g., `[u8; 1024]`) → rapid OOM.
5. Safe pattern: `let cap = usize::min(n, MAX_CAPACITY); Vec::with_capacity(cap)` or `ensure!(n <= MAX_CAPACITY, Error::TooLarge)` with early rejection.
6. Severity: CRITICAL if the length prefix is from an untrusted source with no cap and the allocation is pre-auth. HIGH otherwise. The devp2p class (F05 + F11) is the modal DLT critical DoS.

**Golden signature**: `cargo-fuzz` harness feeding `u32::MAX` length prefix; observe OOM. ASan confirms the large allocation site.

**Source**: rust-libp2p — victim tricked into pre-allocating buffers for messages never sent → cumulative-allocation DoS — RUSTSEC-2022-0084 / CVE-2022-23486; ckb — `misbehavior` HashMap keyed on monotonic `SessionId`, never pruned, grows unbounded via repeated reconnects — RUSTSEC-2021-0108 / CVE-2021-45699; h2 — remote-reset pending-accept queue grows → OOM — RUSTSEC-2023-0034 / CVE-2023-26964; Borsh deserialization docs (length-prefix `with_capacity`). **Misattribution guard**: CVE-2018-20990 is the `tar` crate (symlink overwrite), NOT smallvec; the real smallvec advisory (RUSTSEC-2018-0003 / CVE-2018-20991) is a double-free that belongs to the memory-safety angle. See `resource-exhaustion-research.md` §F05.

---

### CHECK 6 — Memory amplification via clone chains (F06)

**Signal**: `input.clone()` followed by `format!("{}{}", input, suffix)`, multiple `to_owned()` calls, or `collect::<Vec<_>>()` on a large iterator — each step creates a new allocation from the same input.

**Procedure**:
1. For every clone/copy chain on a network-input path: count how many independent allocations are made FROM THE SAME INPUT before the input is consumed or validated.
2. **String concatenation**: `format!("{}:{}:{}:{}", a, b, c, d)` allocates a new String; each `to_string()`/`to_owned()` in the argument list adds another. If `a`, `b`, `c`, `d` are all attacker-controlled, the amplification is 4×.
3. **Batch clone**: `let a = input.clone(); let b = input.clone(); let c = input.clone();` → 3× memory. Before any validation. If the attacker sends 1MB, the service allocates 3MB.
4. Severity: MEDIUM (amplification is typically constant-factor, not unbounded). HIGH if the clone count scales with attacker-controlled input.

**Golden signature**: Manual trace of clone chains; ASan large-allocation report.

**Source**: RPC request body clone chain [model-knowledge].

---

### CHECK 7 — HashDoS (F07)

**Signal**: `HashMap<_, _, BuildHasherDefault<FxHash>>` or `ahash::RandomState::with_seed(fixed)` on attacker-accessible code paths.

**Procedure**:
1. Enumerate every `HashMap` and `HashSet` whose keys are derived from attacker input (RPC parameters, p2p message fields, mempool transaction data).
2. For each: check the hasher type:
   - `std::collections::HashMap<K, V>` (default) → `RandomState` → SipHash-1-3 with random per-process seed → **safe**.
   - `HashMap<K, V, BuildHasherDefault<FxHash>>` → FxHash is deterministic → **attackable**.
   - `HashMap<K, V, FixedState>` with `RandomState::with_seed(CONST)` → deterministic → **attackable**.
   - `ahash::HashMap` with default `RandomState::new()` → uses random seed → **safe**.
   - `ahash::HashMap` with `RandomState::with_seed(fixed)` or `RandomState::with_seeds(fixed, ...)` → deterministic → **attackable**.
   - Custom `BuildHasher` impl → audit the hash function; if it lacks a random key → **attackable**.
3. **NoHash / identity hasher**: `HashMap<K, V, BuildHasherDefault<NoHash>>` — keys ARE the hash. If the attacker can choose keys → trivial collision (same bits → same bucket).
4. Severity: HIGH if a HashDoS-vulnerable map is in a pre-auth path. MEDIUM if post-auth. LOW if the map size is known-capped to a small value.

**Golden signature**: `grep 'FxHash\|BuildHasherDefault\|with_seed'` on attacker-accessible paths. Fuzz harness: insert pre-computed colliding keys; measure insertion time divergence from random keys.

**Source**: Rust HashMap documentation [model-knowledge]; FxHash collision research [model-knowledge].

---

### CHECK 8 — Regex catastrophic backtracking (F08)

**Signal**: `fancy-regex` or foreign (C/C++ via FFI) regex engine operating on attacker-supplied input. The `regex` crate (Rust-native) is **safe** — it uses a DFA/NFA-based engine that guarantees linear time.

**Procedure**:
1. Enumerate every regex match/search/replace on network-input strings.
2. Check the crate: `regex` → safe (linear-time, no backtracking). `fancy-regex` → uses backtracking for some features (backreferences, look-around) → attackable. `pcre2`/`onig`/C-backed regex → backtracking → attackable.
3. For every backtracking-capable regex: inspect the pattern for exponential blowup patterns:
   - `(a+)+$` — nested quantifiers on the same character class
   - `(a|aa)+$` — alternation with common prefix under quantifier
   - `.*.*` — multiple unbounded wildcards chained
4. Severity: HIGH if `fancy-regex` with exponential-backtracking pattern on pre-auth input. MEDIUM otherwise. Safe: `regex` crate → informational at most.

**Golden signature**: Feed pathological input matching the pattern's worst-case; observe CPU spike (multi-second or timeout on a short string).

**Source**: PCRE backtracking [model-knowledge]; `regex` crate linear-time guarantee [model-knowledge].

---

### CHECK 9 — Decompression/decoding bomb (F09)

**Signal**: `zstd::decode_all()`, `flate2::read::GzDecoder`, `snap::read::FrameDecoder`, `brotli::Decompressor`, or any decompression/decoding function operating on network-supplied data WITHOUT a pre-check on the maximum uncompressed size.

**Procedure**:
1. For every decompression call on network data: is there a max-uncompressed-size check BEFORE decompression starts?
2. **Streaming decompressors**: `GzDecoder::new(reader).read_to_end(&mut buf)` — the `read_to_end` will allocate until the stream ends. If the attacker sends a decompression bomb (1KB compressed → GB uncompressed), the Vec grows unboundedly. Fix: wrap the reader in `std::io::Read::take(max_bytes)`.
3. **zstd**: `zstd::decode_all(&compressed)` allocates the full uncompressed buffer. Use `zstd::stream::read::Decoder` with a `take(max_bytes)` wrapper.
4. **Image decoding bombs**: `image::load_from_memory(&bytes)` — a 100KB compressed image can decode to 4K × 4K × 4 channels = 64MB. Use `image::load_from_memory_with_format` with format validation before full decode, or cap the input size.
5. **Compression ratio worst-cases**: zstd can achieve >1000:1 on highly repetitive data. The worst-case attacker payload is a carefully constructed stream of zeros.
6. Severity: CRITICAL if decompression is pre-auth with no size cap. HIGH if post-auth with no size cap. MEDIUM if capped but the cap is too generous (>100MB).

**Golden signature**: `cargo-fuzz` harness feeding a decompression bomb (1KB → 1GB); observe OOM.

**Source**: zstd decompression bomb [model-knowledge]; image decoding bomb [model-knowledge].

---

### CHECK 10 — Subscription/connection leak (F10)

**Signal**: Subscribe/register/unsubscribe asymmetry — a subscription is created on some event but never cleaned up on disconnect/error/timeout.

**Procedure**:
1. For every `.subscribe()`, event listener registration, or connection-pool insertion: is there a guaranteed cleanup path on: (a) client disconnect, (b) server error, (c) timeout, (d) channel close?
2. **WebSocket subscriptions**: does the subscriber count increment on subscribe and decrement on unsubscribe AND on disconnect (the `Drop` or `on_close` handler must unsubscribe)?
3. **tokio broadcast channels**: `Sender::subscribe()` returns a `Receiver`. The `Receiver` auto-unsubscribes on `Drop` — safe by construction. But if the `Receiver` is stored in a long-lived struct that never drops → leak.
4. **Custom subscription registries**: `HashMap<SubscriptionId, Callback>` with manual insert/remove. If the remove path is missing → leak.
5. Severity: HIGH if unlimited subscriptions per connection. MEDIUM if per-connection cap exists but global cap is missing. LOW if bounded at both levels.

**Golden signature**: Stress test: open N connections, subscribe M times each, disconnect without unsubscribing, check subscription count.

**Source**: Substrate RPC subscription leak [model-knowledge]; Ethereum WebSocket connection leak [model-knowledge].

---

### CHECK 11 — Pre-auth resource consumption (F11)

**Signal**: Any memory allocation, deserialization, parsing, or loop that executes BEFORE authentication/authorization completes.

**Procedure**:
1. Enumerate every network-facing function (RPC handler, p2p message handler, WebSocket upgrade handler). For each: trace the code path from packet receipt/connection accept to the FIRST authentication check (signature verification, token validation, peer ID check, capability verification).
2. List EVERY allocation between those two points:
   - `serde_json::from_slice::<Request>(&bytes)` — deserializes into a struct, allocating strings and Vecs
   - `Vec::with_capacity(n)` where n is from the (unauthenticated) message header
   - `String::from_utf8(body)` — allocates a String from the raw body
   - `borsh::from_slice::<Message>(&data)` — allocates per the message's length prefix
3. **Asymmetric cost**: compute `ratio = attacker_tx_bytes / defender_rx_bytes_allocation`. If `ratio < 0.01` → asymmetric amplification. Example: 100-byte packet triggers 10MB allocation → ratio = 1e-5 → CRITICAL pre-auth DoS.
4. **The pre-auth intersection**: CHECK 5 (length-prefix allocation) + CHECK 11 (pre-auth) = the deadliest combination. A single pre-auth packet with a forged length prefix can allocate all available memory before the peer is even validated.
5. **Reflection/amplification sub-check (unverified-sender reply)**: if a handler *replies* to a sender before the auth/endpoint-proof check, the service is a reflector. For every connectionless (UDP) reply path, verify return-routability is proven before replying — e.g., devp2p discv4 honors `FindNode`/`Neighbors` only after a valid ping→pong endpoint proof (matching ping-hash within the last 12 hours). The fix is the proof, NOT a size cap. Compute reply-size ÷ request-size as the amplification factor.
6. Severity: HIGH for any pre-auth allocation >1KB per request OR any unverified-sender reply path. CRITICAL if pre-auth work scales with attacker-controlled size without cap.

**Golden signature**: Manual trace from `fn handle_message()` to first auth check. Fuzz harness measuring pre-auth RSS.

**Source**: DLT p2p DoS research [model-knowledge]; Rust network service security patterns [model-knowledge].

---

### CHECK 12 — Slowloris / slow-read attack (F12)

**Signal**: Network read/write operations without deadlines; streaming parsers without total-timeout enforcement; request body reads without max-body-size enforcement.

**Procedure**:
1. Enumerate every network `read`/`read_exact`/`read_to_end`/`read_to_string` operation. For each: is there a `tokio::time::timeout(duration, read_op)` wrapper?
2. **Per-read vs per-connection timeout**: a timeout on each individual `read()` is insufficient — the attacker sends 1 byte every `timeout - 1ms`, staying under the per-read timeout indefinitely. Verify there is an OVERALL connection timeout or idle timeout.
3. **Streaming parsers**: JSON stream parsers (`serde_json::Deserializer::from_reader`), RLP decoders, protobuf stream parsers — these read incrementally from the network. An attacker sends 1 byte/second indefinitely. Verify the parser wrapper enforces a total parsing timeout.
4. **Headers with declared body size**: `Content-Length: 2GB` with 1-byte/second delivery. Verify: (a) a max body size check at header parsing time, AND (b) a read timeout on the body.
5. **`read_to_end` without cap**: `let mut buf = vec![]; reader.read_to_end(&mut buf)?;` — unbounded allocation AND unbounded time. Use `reader.take(max_bytes).read_to_end(&mut buf)`.
6. Severity: MEDIUM (requires sustained connections; connection slots are the limiting resource). HIGH if combined with infinite connection acceptance (no connection limit).

**Golden signature**: Stress test: open N connections, send 1 byte every 10 seconds on each, observe when the server stops accepting new connections.

**Source**: Slowloris attack paper [model-knowledge]; Tokio timeout documentation [model-knowledge].

---

## Stage-3 PoC discipline

| Class | Backend | Command |
|-------|---------|---------|
| F01 (unbounded growth) | cargo-fuzz + ASan | `cargo fuzz run fuzz_target_<ID>` |
| F02 (quadratic) | criterion bench | `cargo bench --bench complexity_<ID>` |
| F03 (recursion) | cargo-fuzz | `cargo fuzz run fuzz_target_<ID>` |
| F04 (lock-DoS) | Loom (see Concurrency) | `RUSTFLAGS="--cfg loom" cargo test` |
| F05 (capacity allocation) | cargo-fuzz | `cargo fuzz run fuzz_target_<ID>` |
| F06 (clone amplification) | ASan large-alloc | `RUSTFLAGS="-Zsanitizer=address" cargo test` |
| F07 (HashDoS) | custom harness | `cargo test -- --ignored test_hashdos_<ID>` |
| F08 (regex) | custom harness | `cargo test test_regex_bomb_<ID>` |
| F09 (decompression bomb) | cargo-fuzz | `cargo fuzz run fuzz_target_<ID>` |
| F10 (leak) | stress test | `cargo test -- --ignored test_leak_<ID>` |
| F11 (pre-auth) | Manual + fuzz | `cargo fuzz run fuzz_target_<ID>` |
| F12 (slowloris) | stress test | `cargo test -- --ignored test_slowloris_<ID>` |

**Tier-1-fuzz**: OOM or panic from cargo-fuzz on an attacker-controlled input path. Without fuzz confirmation: max CONTESTED.

---

## Output fields beyond shared FINDING schema

```yaml
resource_class: F01 | F02 | F03 | F04 | F05 | F06 | F07 | F08 | F09 | F10 | F11 | F12
attacker_control: <how the attacker controls the resource consumption>
amplification_factor: <attacker bytes vs defender bytes allocated, or attacker CPU cost vs defender CPU cost>
allocation_site: <file:line of the allocation or resource consumption>
pre_auth: true | false
cap_present: true | false | partial
verification_backend: cargo-fuzz | ASan | criterion | manual | stress_test | loom
```

---

## Anti-patterns (do NOT report)

- `Vec::push` in a loop with a compile-time max-iterations constant → bounded by definition, not a finding.
- `HashMap<K, V>` using `std::collections::HashMap` (SipHash-1-3, random seed) → HashDoS-safe by construction, not a finding.
- `regex::Regex` (Rust `regex` crate) — the engine guarantees O(n) linear time. Do not report backtracking on it.
- `tokio::time::timeout` wrapping every read operation → timeout-governed, not a slowloris finding.
- `Vec::with_capacity(n)` where `n` is proven to be ≤ a compile-time constant via prior validation → bounded, not a finding.
- `clone()` once on a small input (<1KB) → negligible amplification, not a finding.
- Decompression with a `Read::take(max_bytes)` wrapper where `max_bytes` is reasonable (<100MB) → bounded, not a finding.

---

## Coordination with other angles

- **Concurrency (Angle 4)** owns the lock-held-across-await pattern for deadlock analysis. Angle 6 owns the DoS dimension — the lock blocks all other consumers, amplifying the attack.
- **Memory Safety (Angle 1)** owns the OOB/UB that can result from a mis-trusted length prefix (e.g., buffer allocated too small, then over-read). Angle 6 owns the exhaustion dimension — the allocation itself is too large.
- **Supply Chain & FFI (Angle 8)** owns the dependency version audit (vulnerable decompression library versions). Angle 6 owns the API misuse — using a safe library version without size caps.
- **Logic & State Machine (Angle 7)** owns subscription state-machine completeness (does every state transition include cleanup?). Angle 6 owns the resource-leak dimension — the cleanup path exists but doesn't fire reliably.
