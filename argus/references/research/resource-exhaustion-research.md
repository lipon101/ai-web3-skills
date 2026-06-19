# Resource Exhaustion & DoS — Research Dossier

> **Feeds**: `hacking-agents/infra/resource-exhaustion-agent.md`
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 9 verified advisories (each fetched: identifier + mechanism confirmed) + 1 verified protocol-spec correction (devp2p discv4) + 2 verified misattribution-guard sources + 1 verified framework fact
> **Status**: drafted-verified

> **Anchor case (cross-protocol precedent — verify before porting)**: **HTTP/2 Rapid Reset, CVE-2023-44487** (NVD; Cloudflare technical breakdown). A client sends `HEADERS` with `END_STREAM`, then *immediately* sends `RST_STREAM`. Because a cancelled stream no longer counts against the max-concurrent-streams limit, the client can open a replacement stream instantly and churn through requests faster than the server tidies them up — a backlog of upstream work accumulates and exhausts server resources. The bandwidth cost to the attacker is trivial; the asymmetry is the whole attack. The Rust HTTP/2 stack (`h2`) shipped its OWN distinct variants of reset-queue exhaustion (RUSTSEC-2023-0034, RUSTSEC-2024-0003 below) — the lesson is methodological, not a single pattern: **any state-machine transition that lets a client cheaply create server-side work which is cleaned up lazily is a DoS surface.**

---

## 0. Calibration headline

Resource exhaustion is the most *asymmetric* DLT attack class: kilobytes of attacker traffic consume gigabytes of validator memory / CPU / file descriptors. A downed validator weakens consensus (fewer validators → cheaper to attack). In p2p networks, DoS pairs with eclipse: exhaust the target's connection slots, then feed it a private chain view.

The empirically-confirmed modal bug in Rust DLT infra is **unbounded collection growth driven by attacker-influenced input with no eviction or cap** — confirmed in three separate real advisories with different shapes:
- a `Vec` that is appended-to but only drained on connection close (yamux `pending_frames`, CVE-2024-32984),
- a `HashMap` keyed on a monotonically-increasing id whose entries are never deleted (`ckb` `misbehavior` map keyed on `PeerIndex`/`SessionId`, CVE-2021-45699),
- a "pending accept" / reset queue that grows when the peer stops reading (`h2`, RUSTSEC-2023-0034 / -2024-0003).

The crucial nuance, learned from the yamux and h2 cases: the growth is often **not** a single `with_capacity(attacker_n)` call. It is a queue that drains slower than it fills because the *attacker controls the drain rate* via TCP back-pressure (closing their receive window). A length-prefix audit alone misses this; you must also audit *who controls the drain side of every unbounded queue*.

Tool coverage is strong for the allocation-explosion shape — `cargo-fuzz` finds OOM/`capacity overflow` panic paths; ASan finds memory exhaustion. The back-pressure-driven growth shape is harder to fuzz and is found by reasoning: trace each unbounded collection's *producer* and *drain* to their respective rate-controllers.

---

## 1. Bug-class taxonomy

> Real-instance column cites only fetched, identifier-confirmed sources (section 7). Classes with no confirmed-id instance are labelled `[generic pattern — no specific incident]`.

| Class | One-line mechanism | Real instance (verified source) | Argus coverage |
|-------|--------------------|---------------------------------|----------------|
| **F01 Unbounded collection growth (producer/drain asymmetry)** | A `Vec`/`HashMap`/queue grows under attacker-influenced input with no cap or eviction; drain rate is attacker-controllable | yamux `pending_frames` Vec drained only on close — **CVE-2024-32984 / GHSA-3999-5ffv-wp2r**; `ckb` `misbehavior` HashMap keyed on monotonic `PeerIndex`(=`SessionId`), entries never removed — **RUSTSEC-2021-0108 / CVE-2021-45699**; `h2` pending-accept queue — **RUSTSEC-2023-0034 / CVE-2023-26964** | **YES** |
| **F02 Reset/cancel-driven server work (Rapid-Reset class)** | A cheap client state transition (cancel/reset) creates server-side work cleaned up lazily; concurrency cap is bypassed | HTTP/2 Rapid Reset — **CVE-2023-44487**; `h2` invalid-frame → forced reset frames queued behind a closed receive window — **RUSTSEC-2024-0003 / CVE-2019-9514** | **PARTIAL** — covered as F01 today; deserves its own check |
| **F03 Multiplexer back-pressure DoS** | Stream multiplexer (mplex/yamux) lacking back-pressure lets a peer open endless streams / buffer partial payloads / pre-allocate buffers → many small chunks → OOM | rust-libp2p mplex/yamux — **RUSTSEC-2022-0084 / CVE-2022-23486 / GHSA-jvgw-gccv-q5p8** | **YES** |
| **F04 Decompression / decoding bomb** | Small compressed/encoded input expands to GB+; no max-uncompressed-size cap; ratio = attacker amplification | Cargo (tar+gzip) extraction from alternate registry with no size limit → "zip bomb" exhausts disk — **CVE-2022-36114 / GHSA-2hvr-h6gw-qrxp**; brotli-sys "one-shot" decompress, integer overflow copying chunks >2 GiB → crash — **RUSTSEC-2021-0131 / CVE-2020-8927** | **YES** |
| **F05 Large allocation from attacker-controlled length prefix** | A length/count field from an untrusted message used as allocation size with no max cap → OOM | `[generic pattern — no specific incident]` (Borsh/scale-codec/serde `Vec<T>` deserialize reads len then reserves) | **PARTIAL** — mentioned, no systematic length-prefix audit |
| **F06 HashDoS (collision attack via substituted hasher)** | A `HashMap`/`HashSet` whose default DoS-resistant hasher is replaced with a deterministic one → attacker pre-computes colliding keys → O(n²) | `[generic pattern — no specific incident]` (std `HashMap` is SipHash-1-3 + per-instance random seed = SAFE; risk is only `FxHash`/fixed-seed `ahash`/constant-seed custom hasher on attacker-reachable maps) | **PARTIAL** — mentioned, no systematic hasher audit |
| **F07 Pre-auth resource consumption** | Allocation / deserialization / CPU work — or *reply generation* — done BEFORE the auth or endpoint-proof check → unauthenticated attacker exhausts resources; can also be a reflection/amplification surface | devp2p discv4: `Neighbors` reply sent before endpoint-proof → UDP reflection/amplification (fix: endpoint-proof verification, NOT a length cap) — **ethereum/devp2p discv4 spec** | **NO** |
| **F08 Slowloris / slow-read** | Connections held with no overall deadline; attacker drips bytes slowly → connection/stream slots tied up | `[generic pattern — no specific incident]` (classic HTTP/1.1 slowloris; in Rust, missing `tokio::time::timeout` on stream reads) | **NO** |

> **Misattribution guard (do NOT file under allocation/OOM)**: **RUSTSEC-2018-0003 / CVE-2018-20991** (`smallvec::insert_many` double-free during unwind) is a **memory-safety** bug, not a resource-exhaustion bug — it belongs to the memory-safety angle. Two prior-draft citation errors are explicitly invalidated here (each verified this pass): (a) **CVE-2018-20990** is the **`tar` crate** (arbitrary file overwrite via symlink/hardlink, CWE-59), an unrelated crate — never a smallvec/allocation advisory; (b) **RUSTSEC-2018-0017** is the **`tempdir`** crate deprecation notice — also unrelated. The only correct smallvec advisory is RUSTSEC-2018-0003 / CVE-2018-20991. Listed here only so a future pass does not re-introduce any of these errors.

---

## 2. Per-class methodology (novel / under-covered classes)

### F01 — Unbounded collection growth (producer/drain asymmetry)

**Signal**: any `Vec::push` / `VecDeque::push_back` / `HashMap::insert` / `HashSet::insert` reachable from a network message handler, where the collection is a long-lived field (per-connection or per-node state) rather than a local.

**Procedure**:
1. Enumerate every long-lived collection field on connection/session/node state structs.
2. For each, answer two questions separately:
   - **Producer**: what bounds the *insert* side? Is there a cap, or is it driven directly by attacker message volume?
   - **Drain**: what bounds the *removal* side, and **who controls its rate**? (yamux's lesson: `pending_frames` was only drained when the socket could write — and the *peer* controls that via TCP receive window. The producer side looked fine in isolation.)
3. A collection is unbounded-exploitable if **either** the producer has no cap **or** the drain rate is attacker-controllable while the producer is not. Both yamux (drain-controlled) and ckb (no eviction at all) are real instances of this.
4. **Key-space audit (ckb shape)**: if a `HashMap` is keyed on a monotonically-increasing id (`SessionId`/`PeerIndex`, request id, peer counter) and entries are inserted-but-never-removed, the map is unbounded by construction — every reconnect adds a permanent entry. The ckb bug was exactly this: a `misbehavior` score map keyed on `PeerIndex` (an alias for the monotonic `SessionId`), with no removal on disconnect. Grep for maps keyed on counter-like types with no `.remove()` on disconnect/cleanup.

**Mechanical evidence**: integration test that (a) opens a connection, (b) drives the producer (open streams / trigger violations / send pings) while (c) refusing to read from the socket (simulate a closed receive window), then asserts the target collection's len/RSS grows without bound. For the ckb shape: reconnect+violate in a loop and assert the map never shrinks.

**Anti-pattern (false-positive guard)**: a collection with an explicit cap + eviction (LRU, ring buffer, `if len > MAX { reject }`) is safe even if attacker-driven. A `with_capacity` reservation that is bounded by a validated count is safe.

**Source**: CVE-2024-32984 (yamux), CVE-2021-45699 (ckb), RUSTSEC-2023-0034 (h2) — section 7.

### F02 — Reset/cancel-driven server work (Rapid-Reset class)

**Signal**: a protocol state machine where a *client-initiated* transition (cancel, reset, abort, unsubscribe-then-resubscribe) is cheap to send but triggers server-side allocation/cleanup that is deferred or asynchronous.

**Procedure**:
1. Identify every client-controllable state transition that does NOT count against a concurrency/rate limit (Rapid Reset's core: a cancelled stream stops counting toward max-concurrent-streams).
2. For each, ask: does it create server-side work (queue an item, spawn a task, allocate a buffer) that is cleaned up *lazily* relative to how fast the client can re-trigger?
3. If the client can re-trigger faster than cleanup completes → backlog accumulates → DoS. The defense is to bound *outstanding work*, not just *concurrent active items*. The two `h2` fixes are the canonical Rust shape: RUSTSEC-2023-0034 capped remote-reset stream counts (HEADERS/RST_STREAM flood → pending-accept queue); RUSTSEC-2024-0003 limited the number of internal-error resets before closing the connection (invalid-frame flood → reset-frame queue behind a closed window).

**Mechanical evidence**: load test that flips the state machine (open→reset) in a tight loop while measuring server-side queue depth / task count; assert it stays bounded.

**Anti-pattern**: the work is performed synchronously before the response, so the client cannot outrun it; or outstanding work is explicitly capped.

**Source**: CVE-2023-44487, RUSTSEC-2024-0003, RUSTSEC-2023-0034 — section 7.

### F05 — Large allocation from attacker-controlled length prefix

**Signal**: `Vec::with_capacity(n)`, `String::with_capacity(n)`, `vec![0u8; n]`, `HashMap::with_capacity(n)` where `n` traces to a deserialized length/count field. In Rust DLT serde stacks this is most often *implicit*: `borsh`/`parity-scale-codec`/`serde` deserializing a `Vec<T>` reads a length then reserves for it.

**Procedure**:
1. For every `with_capacity`/`vec![_; n]` whose `n` traces to network input: is there `min(n, MAX)` or a `n <= MAX else reject` *before* the allocation?
2. For implicit deserializer allocation: wrap the reader in a byte limiter (`std::io::Read::take(MAX_BYTES)`) so a forged length cannot reserve unbounded memory; or use length-bounded container types.
3. Decoder reuse: a forged length that exceeds the actual remaining bytes should fail *fast* (length-vs-available check) rather than reserving first and erroring later.

**Mechanical evidence**: `cargo-fuzz` target feeding crafted length prefixes; golden signal = OOM-killer or `capacity overflow` panic.

**Anti-pattern**: length is validated against remaining buffer length or an explicit protocol max before allocation.

> **Do NOT cite devp2p `Neighbors` here.** The devp2p amplification bug is endpoint-proof (F07), not a length-prefix over-allocation — discv4 `Neighbors` replies are protocol-capped (≤16 nodes / small packet, verified against the spec this pass). Inventing a "Vec allocation of 2^32" mechanism for it is the exact error the prior draft made.

**Source**: `[generic pattern — no specific incident]` (Borsh/scale-codec/serde deserialization semantics; no identifier-confirmed Rust DLT OOM advisory found this pass).

### F06 — HashDoS (collision attack)

**Signal**: a `HashMap`/`HashSet` on an attacker-reachable path (RPC handler, p2p message processing, mempool) whose hasher is NOT the default.

**Procedure**:
1. Establish the baseline: Rust `std::collections::HashMap` uses **SipHash-1-3 with a per-instance random seed** and is documented as HashDoS-resistant (std docs, section 7). A default `HashMap` is therefore SAFE.
2. Flag only *substituted* hashers on attacker-reachable maps: `BuildHasherDefault<FxHasher>` (deterministic), `ahash::RandomState::with_seed(fixed)` / `with_seeds(...)` (deterministic), or any hand-rolled `BuildHasher` with a constant seed (note the std docs explicitly warn that a `HashMap` built with a non-random hasher for `const`/`static` use "is not resistant to HashDoS attacks").
3. For each flagged map, judge reachability and key control: can the attacker choose keys (peer ids, tx hashes they craft, RPC params)? If keys are attacker-chosen and the hasher is deterministic → collidable → O(n²).
4. Severity: High if pre-auth and keys attacker-chosen; Medium post-auth; Low if the map is small/bounded.

**Mechanical evidence**: `grep -R 'FxHash\|BuildHasherDefault\|with_seed' ` on attacker-reachable modules; PoC inserting pre-computed colliding keys and measuring insertion time growth.

**Anti-pattern**: default `HashMap`/`HashSet`; `ahash::RandomState::new()` (random seed); keys not attacker-controllable (internal enum, validated id).

**Source**: Rust std `HashMap` docs (SipHash-1-3, per-instance random seed, DoS-resistant) — section 7. No identifier-confirmed Rust-DLT HashDoS *incident* found this pass → class is `[generic pattern — no specific incident]`.

### F07 — Pre-auth resource consumption (incl. reflection/amplification)

**Signal**: allocation, deserialization, CPU work, or *reply generation* before authentication / endpoint-proof / handshake completion.

**Procedure**:
1. For every network-facing handler, trace from packet receipt to the auth/endpoint-proof check. Enumerate work done *before* it: struct deserialization, buffer allocation, crypto setup, and **reply emission**.
2. **Reflection/amplification sub-check (devp2p lesson)**: if the handler *replies* to an unverified sender, the service is a reflector. discv4's fix was to send `Neighbors` (and `ENRResponse`) only to senders that have completed the ping→pong endpoint proof — the spec requires a valid Pong with matching ping-hash within the last **12 hours** before a `FindNode` is honored — i.e., proof-of-return-routability before any reply. Verify every UDP/connectionless reply path requires endpoint proof. The fix is the proof, NOT a size cap (Neighbors is already protocol-capped at ≤16 nodes).
3. **Asymmetric-cost check**: `ratio = attacker_bytes_in / defender_work_out` (bytes or amplified reply size). `ratio` far below 1 on a pre-auth path → HIGH.
4. Severity: HIGH for any unbounded pre-auth allocation or any unverified-sender reply path; Critical if pre-auth work scales with attacker-controlled size.

**Mechanical evidence**: enumerate pre-auth paths manually; measure RSS / reply-bytes before vs after the auth check; for reflection, measure reply-size ÷ request-size.

**Anti-pattern**: handler does only constant, tiny work before auth and never replies to an unverified sender.

**Source**: ethereum/devp2p discv4 spec (endpoint proof; 12-hour freshness; amplification mitigation) — section 7. (Cross-protocol Go/Ethereum precedent — port the *methodology*, not Geth/Solidity specifics.)

### F08 — Slowloris / slow-read

**Signal**: stream/connection reads with no *overall* deadline; incremental parsers fed from a socket with only per-read (not per-request) timeouts; body reads gated only by `Content-Length` with no time bound.

**Procedure**:
1. Enumerate network read loops. Each needs an overall request deadline (`tokio::time::timeout(Duration, whole_request_future)`), not just a per-poll timeout — a 1-byte-per-second drip satisfies per-read timeouts forever.
2. Incremental decoders (RLP/JSON/length-delimited): confirm a wall-clock cap on time-to-complete-message, plus a max message size.
3. Slot accounting: connection slots are the scarce resource; verify per-IP connection caps + idle/stall eviction.
4. Severity: Medium (sustained attack required; slot exhaustion).

**Mechanical evidence**: stress harness opening N connections dripping bytes slowly; assert slots are evicted and the server stays available.

**Anti-pattern**: overall request deadline present; idle-connection reaper present.

**Source**: `[generic pattern — no specific incident]` (classic slowloris; Tokio timeout idiom). No identifier-confirmed Rust-DLT slowloris advisory found this pass.

---

## 3. Framework-specific knowledge

- **Rust std `HashMap` is HashDoS-safe by default** — SipHash-1-3, per-instance random seed, documented as DoS-resistant ("By default, `HashMap` uses a hashing algorithm selected to provide resistance against HashDoS attacks"; the docs explicitly warn that a non-random hasher built for `const`/`static` use is *not* resistant). Do NOT flag a default `HashMap` as HashDoS. Flag only substituted deterministic hashers (`FxHash`, fixed-seed `ahash`, constant-seed custom `BuildHasher`) on attacker-reachable, attacker-keyed maps.
- **Stream multiplexers need explicit back-pressure** — mplex and yamux were both called out (RUSTSEC-2022-0084 / GHSA-jvgw-gccv-q5p8) for insufficient back-pressure: a peer opens endless streams, sends partial payloads on various protocol levels (forcing the victim to buffer), or tricks the victim into pre-allocating buffers for messages never sent → many small allocations → OOM (fixed 0.45.1). The yamux `pending_frames` Vec (CVE-2024-32984) is the concrete shape: appended on every outbound frame, drained only when the socket is writable — and the *peer* controls writability via TCP receive window (fixed 0.13.2).
- **TCP receive window is an attacker tool** — closing the receive window stalls the victim's send path. Any victim-side outbound queue that grows while the send path is stalled is exploitable (yamux, h2 reset queue). Audit the *drain* side of every outbound queue, not just the producer.
- **serde-family deserializers allocate from declared length** — `borsh`/`parity-scale-codec`/`serde` reading a `Vec<T>` reads a length then reserves. Bound the reader (`Read::take`) or the declared length before reserving.
- **`h2` reset/accept queues** — the Rust HTTP/2 crate has had *two* distinct reset-queue exhaustion advisories: RUSTSEC-2023-0034 / CVE-2023-26964 (HEADERS/RST_STREAM flood → pending-accept queue grows → OOM; fixed 0.3.17) and RUSTSEC-2024-0003 / CVE-2019-9514 (invalid-frame → forced reset-frame generation behind a closed receive window → OOM + CPU; fixed 0.3.24 / 0.4.2). Both reduce to "bound outstanding work, not just active streams."
- **devp2p discv4 endpoint proof** — connectionless (UDP) reply paths must verify return-routability (ping→pong with matching ping-hash within the last 12 hours) before replying, to prevent reflection/amplification. `Neighbors` is protocol-capped (≤16 nodes); the bug class is "reply to unverified sender," not "over-allocate from a length prefix."
- **Cargo/tar+gzip decompression** — Cargo did not cap extracted size when extracting crate archives from *alternate registries* (CVE-2022-36114; crates.io already rejected such packages server-side), letting a "zip bomb" exhaust disk space (fixed Cargo 0.65.0). Any code extracting untrusted archives must cap total uncompressed bytes; the compression ratio is the amplification factor.

---

## 4. Tooling

| Tool | What it finds | Readiness | Invoke / golden signature |
|------|---------------|-----------|---------------------------|
| **cargo-fuzz / libFuzzer** | OOM, `capacity overflow` panic, allocation explosion from crafted length prefixes / decompression inputs | HIGH | `cargo fuzz run <target>` → OOM-killer or `capacity overflow` panic |
| **AddressSanitizer** | Heap/stack memory exhaustion, OOB from undersized alloc | HIGH | `RUSTFLAGS="-Zsanitizer=address" cargo +nightly test` |
| **Integration test w/ stalled socket** | F01/F02 back-pressure growth (the shape fuzzers miss) | HIGH — bespoke | drive producer + refuse to read socket → assert queue/RSS unbounded |
| **Criterion benchmarks** | Algorithmic-complexity / HashDoS detection via input-size-vs-time | MEDIUM — manual | `cargo bench`; plot time vs n, look for super-linear |
| **Manual producer/drain trace** | Unbounded collections, missing caps, missing eviction, unverified-sender replies | N/A — human | grep long-lived collections + trace insert & remove sites |

---

## 5. Discovery calibration

No angle-specific hit-rate data collected this pass. Qualitative dispatch note: the *length-prefix over-allocation* shape (F05) is mechanically discoverable (fuzz + grep `with_capacity`) and suits a directed scan. The *producer/drain back-pressure* shape (F01/F02) and *unverified-sender reply* shape (F07) require cross-function reasoning about who controls each rate — these reward a directed LLM trace over a grep, and were exactly the shapes the prior memory-only draft got wrong. Prefer directed prompts that name the producer and the drain explicitly.

---

## 6. Gaps → angle changes

| Methodology | New CHECK / vector / tool | Change type | Anti-bloat: does an existing check cover it? |
|-------------|---------------------------|-------------|----------------------------------------------|
| Producer/drain asymmetry audit for unbounded collections (incl. back-pressure-controlled drain + monotonic-key maps) | Extend the F01 check to separately interrogate producer cap AND drain-rate controller; add monotonic-key/no-eviction sub-check | extend | Partially — current check looks at insert side only; back-pressure + key-space audits are new |
| Reset/cancel-driven server work (Rapid-Reset class) | New CHECK: cheap client transitions that bypass concurrency caps and create lazily-cleaned work | extend | No — currently folded into generic F01; deserves its own trigger |
| Length-prefix / deserializer allocation audit | CHECK: every `with_capacity`/`vec![_;n]`/serde `Vec` reserve traced to network input has a pre-allocation cap or bounded reader | extend | Partially — mentioned, no systematic procedure |
| Substituted-hasher HashDoS audit (default `HashMap` is SAFE) | CHECK: flag only `FxHash`/fixed-seed `ahash`/constant-seed custom hashers on attacker-keyed reachable maps | extend | Partially — mentioned, no hasher-inspection procedure; must encode the "default is safe" guard to avoid FP noise |
| Pre-auth resource + unverified-sender reply (reflection/amplification) | New CHECK: enumerate pre-auth work; for connectionless replies require endpoint proof; compute asymmetry ratio | new-check | No |
| Slowloris / overall-deadline audit | New CHECK: per-request (not per-read) deadline + max message size + slot eviction | new-check | No |

---

## 7. Sources

All URLs fetched this pass (2026-06-05); each confirms BOTH the identifier AND the mechanism cited above.

**Verified advisories (9):**

1. **CVE-2023-44487 — HTTP/2 Rapid Reset** (request cancellation resets many streams quickly to bypass the concurrency cap → server resource consumption; "exploited in the wild in August through October 2023"). CWE-400. NVD: https://nvd.nist.gov/vuln/detail/CVE-2023-44487 · Cloudflare technical breakdown: https://blog.cloudflare.com/technical-breakdown-http2-rapid-reset-ddos-attack/
2. **RUSTSEC-2023-0034 / CVE-2023-26964 — `h2`** (attacker floods paired `HEADERS`/`RST_STREAM` frames faster than the app can accept them → pending-accept queue grows in memory → OOM; fixed by restricting remote-reset stream counts, 0.3.17+; distinct from CVE-2023-44487). https://rustsec.org/advisories/RUSTSEC-2023-0034.html
3. **RUSTSEC-2024-0003 / CVE-2019-9514 — `h2`** (attacker sends a steady stream of invalid frames to force generation of reset frames; by closing the receive window the reset frames accumulate without bound → OOM + excessive CPU; fixed by limiting internal-error resets before closing, 0.3.24 / 0.4.2). https://rustsec.org/advisories/RUSTSEC-2024-0003.html
4. **CVE-2024-32984 / GHSA-3999-5ffv-wp2r — rust-yamux** (`pending_frames` Vec is unbounded; every frame to send is appended; attacker stops reading the socket so the TCP receive window never expands, applying back-pressure that prevents drain — "the queue will only be drained once the underlying TCP connection is closed"; frame generation triggered by opening streams / sending pings / inducing responses → unbounded growth → process killed; affected ≥0.13.0, fixed 0.13.2). https://github.com/libp2p/rust-yamux/security/advisories/GHSA-3999-5ffv-wp2r
5. **RUSTSEC-2022-0084 / CVE-2022-23486 / GHSA-jvgw-gccv-q5p8 — rust-libp2p** (a malicious node continuously opens new streams on one connection using a multiplexer without sufficient back-pressure — mplex or yamux — or sends partial payloads forcing the victim to buffer, or tricks the victim into pre-allocating buffers for messages never sent → cumulative small allocations exhaust memory → DoS; affected ≤0.45.0, fixed 0.45.1). https://rustsec.org/advisories/RUSTSEC-2022-0084.html · https://github.com/libp2p/rust-libp2p/security/advisories/GHSA-jvgw-gccv-q5p8
6. **RUSTSEC-2021-0108 / CVE-2021-45699 — `ckb` (Nervos CKB node)** (the sync protocol's `SyncState` keeps a `misbehavior` HashMap scoring peers' protocol violations, keyed on `PeerIndex` — an alias for `SessionId` — and entries are never removed; `SessionId` increases monotonically with every new connection, so a remote attacker that reconnects repeatedly grows the map without bound → memory exhaustion / crash; fixed 0.40.0). https://rustsec.org/advisories/RUSTSEC-2021-0108.html
7. **RUSTSEC-2021-0131 / CVE-2020-8927 — `brotli-sys`** (integer/buffer overflow in the bundled Brotli C library prior to 1.0.8; an attacker controlling the input length of a "one-shot" decompression request triggers a crash when copying chunks of data larger than 2 GiB; no patched `brotli-sys` released — mitigate via the streaming API with chunk limits or the pure-Rust `brotli` crate). https://rustsec.org/advisories/RUSTSEC-2021-0131.html
8. **CVE-2022-36114 / GHSA-2hvr-h6gw-qrxp — Cargo (tar+gzip)** (Cargo did not limit the amount of data extracted from compressed crate archives; a crafted package on an *alternate registry* extracts far more than its size — a "zip bomb" — exhausting disk space; crates.io already rejected such packages server-side; severity Low; fixed Cargo 0.65.0). https://github.com/rust-lang/cargo/security/advisories/GHSA-2hvr-h6gw-qrxp · Rust blog: https://blog.rust-lang.org/2022/09/14/cargo-cves/
9. **RUSTSEC-2018-0003 / CVE-2018-20991 — `smallvec`** — **MISATTRIBUTION GUARD ONLY.** Double-free during unwind: if an iterator passed to `SmallVec::insert_many` panics in `Iterator::next`, destructors run during unwinding while the vector is in an inconsistent state → possible double free (a *memory-safety* bug, NOT allocation/OOM; belongs to the memory-safety angle). Cited solely so future passes do not mis-file it under resource exhaustion. https://rustsec.org/advisories/RUSTSEC-2018-0003.html

**Verified protocol-spec correction (1):**

10. **ethereum/devp2p discv4 spec — endpoint proof** ("To prevent traffic amplification attacks, implementations must verify that the sender of a query participates in the discovery protocol"; a sender is verified only if it sent a valid Pong with matching ping-hash within the last 12 hours; "Neighbors replies should only be sent if the sender of FindNode has been verified by the endpoint proof procedure"; a Neighbors packet contains at most the closest 16 nodes). This corrects the prior draft's invented "length-prefix Vec allocation of 2^32" mechanism — the devp2p issue is UDP **reflection/amplification** fixed by **endpoint-proof verification**, not an allocation cap. Cross-protocol (Go/Ethereum) precedent — port the methodology only. https://github.com/ethereum/devp2p/blob/master/discv4.md

**Verified misattribution-guard sources (2):**

11. **CVE-2018-20990 — `tar` crate** (arbitrary file overwrite via symlink/hardlink in a TAR archive, CWE-59; versions before 0.4.16). Confirms the prior draft's "CVE-2018-20990 = smallvec/allocation" citation was wrong — it is an unrelated file-overwrite bug in a different crate. https://nvd.nist.gov/vuln/detail/CVE-2018-20990
12. **RUSTSEC-2018-0017 — `tempdir` crate** (deprecation notice; functionality merged into `tempfile`). Confirms the prior draft's "RUSTSEC-2018-0017 = smallvec" citation was wrong — it is an unrelated deprecation advisory. https://rustsec.org/advisories/RUSTSEC-2018-0017.html

**Framework facts (1):**

13. **Rust std `HashMap`** — default hasher is SipHash-1-3 with a per-instance random seed; documented: "By default, `HashMap` uses a hashing algorithm selected to provide resistance against HashDoS attacks," with an explicit warning that a `HashMap` built with a non-random hasher for `const`/`static` use "is not resistant to HashDoS attacks." Establishes that a *default* `HashMap` is SAFE and only substituted deterministic hashers are flaggable. https://doc.rust-lang.org/std/collections/struct.HashMap.html

---

> **AI-provenance reminder**: This dossier was assembled by an AI agent. Every retained identifier was fetched from the primary source above and confirmed for BOTH id and mechanism on 2026-06-05; classes without a confirmed incident are explicitly labelled `[generic pattern — no specific incident]` and carry no id. Before wiring any item into the angle or citing it in a finding, a human must re-confirm the advisory id, affected/patched versions, and mechanism against the live source — advisories are amended and superseded over time.
