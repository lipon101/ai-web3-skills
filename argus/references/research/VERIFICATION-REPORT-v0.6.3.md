# Argus v0.6.3 Dossier Verification Report

## 1. Verdict Headline

**This work CANNOT be trusted as "evidence-grounded" in its current state and requires a corrections pass before any dossier feeds a downstream `*-agent.md`.** Across 8 dossiers and 71 graded claims, only 27 (38%) verified cleanly, and the failures are not random noise — they concentrate precisely on the *anchor cases* and the *named identifiers* each dossier uses to claim real-world grounding. Five dossiers reach for marquee incident names (Wormhole, Binance Bridge, Parity, Heartbleed) or specific CVE/RUSTSEC IDs and attach them to the *wrong bug class*, the *wrong project*, or a *fabricated mechanism*. The methodology content (taxonomies, per-class procedures, Kani/Miri/Loom/fuzz tooling) is consistently sound and Rust-native — but every dossier's "this really happened" evidence layer is corrupted to some degree. The saving grace is honesty: most dossiers self-tag `[model-knowledge]` and several declare "0 primary sources reviewed," so the work is disclosed as unverified rather than passed off as confirmed. That candor is why the verdict is "corrections pass," not "roll back."

## 2. Scorecard

| Dossier | Claims | VERIFIED | WRONG_DESC | MISATTRIBUTED | FABRICATED | UNVERIFIABLE | Grade |
|---|---|---|---|---|---|---|---|
| arithmetic-research.md | 9 | 3 | 3 | 1 | 1 | 1 | needs-corrections |
| concurrency-research.md | 11 | 0 | 2 | 0 | 0 | 9 | major-problems |
| crypto-misuse-research.md | 17 | 14 | 1 | 2 | 0 | 0 | needs-corrections |
| logic-state-machine-research.md | 14 | 7 | 1 | 0 | 0 | 6 | needs-corrections |
| memory-safety-research.md | 4 | 1 | 2 | 1 | 0 | 0 | major-problems |
| resource-exhaustion-research.md | 9 | 4 | 2 | 1 | 0 | 2 | needs-corrections |
| supply-chain-ffi-research.md | 3 | 1 | 0 | 2 | 0 | 0 | major-problems |
| unsafe-trait-research.md | 4 | 0 | 2 | 0 | 0 | 2 | major-problems |
| **TOTAL** | **71** | **30** | **13** | **7** | **1** | **20** | — |

> Note: VERIFIED total is 30 by per-claim tally (the headline "27 clean" excludes 3 VERIFIED-but-cross-language-analogy anchors flagged as weak Rust grounding: Compound, Lido, Heartbleed-in-crypto-misuse). Both framings are reported for transparency.

## 3. Confirmed Errors (Corrections Worklist)

### A. WRONG_DESCRIPTION — real ID/incident, wrong mechanism or bug class

1. **arithmetic — Wormhole ($326M, Feb 2022)**: Described as a u256→u64 amount truncation (A2). Real cause = guardian signature-verification bypass (`load_instruction_at` spoofing in `verify_signatures`), an access-control bug, no arithmetic narrowing. Fix: remove from arithmetic taxonomy or re-cite as a signature-verification incident. https://kudelskisecurity.com/research/quick-analysis-of-the-wormhole-attack
2. **arithmetic — Binance Bridge / BSC Token Hub ($570M, Oct 2022)**: Described as governance-parameter amplification overflow (A9). Real cause = IAVL Merkle-proof forgery (root hash ignored the right leaf). No arithmetic overflow incident exists. https://medium.com/immunefi/hack-analysis-binance-bridge-october-2022-2876d39247c1
3. **arithmetic — SPL Token-2022 transfer fee (A1)**: Described as `amount * fee_bps` overflow-before-division. Real documented class = fee NOT subtracted (pre-fee amount used in verification; Neodyme / Kora Paymaster). SPL's `TransferFee` uses u128/checked internally. Re-describe the mechanism or remove the "real instance" label. https://neodyme.io/en/blog/token-2022/
4. **concurrency — Parity Ethereum "OnDemand" deadlock (2019)** [ANCHOR]: Invented `Mutex<HashMap<RequestId, Sender>>` circular-wait mechanism. Real deadlock = `sync.write()` lock held across block propagation (PR #9954 / issue #9952); "OnDemand" is a separate light-client fetcher. Rewrite the anchor mechanism to match the documented sync-lock-ordering bug. https://github.com/openethereum/parity-ethereum/pull/9954
5. **concurrency — AWS Shuttle tooling claim**: States it found bugs in "AWS S3, DynamoDB clients." Real = S3 **ShardStore** storage backend (16 issues prevented). Also Shuttle is randomized, not exhaustive (don't conflate with Loom). Fix project name and framing. https://github.com/awslabs/shuttle
6. **crypto-misuse — CVE-2022-31173 (juniper)**: Filed under C4 zeroisation/secrets-in-memory. Real = uncontrolled-recursion DoS / stack overflow (CWE-674/400), RUSTSEC-2022-0054, fixed 0.15.10. Nothing to do with memory disclosure. Move out of C4 or replace. https://nvd.nist.gov/vuln/detail/CVE-2022-31173
7. **logic-state-machine — Solana PoH tick drift / Dec-2020 outage (L12)**: Described as PoH-generator clock drift → wrong slot → votes rejected. Real = Turbine block-propagation bug (blocks tracked by slot number not hash; two blocks per slot treated as identical). Rewrite mechanism. https://medium.com/solana-labs/mainnet-beta-stall-postmortem-ba0c6064e3
8. **memory-safety — CVE-2021-38194 (arkworks)** [ANCHOR]: Rebuilt as an `unwrap()`/panic/DoS on `b==0`. Real = ZK under-constraint soundness bug — `FieldVar::mul_by_inverse` enforces zero R1CS constraints (RUSTSEC-2021-0075, <0.3.1), letting a prover forge sound-looking proofs. The whole "panic = chain-halt" anchor framing is invented. https://nvd.nist.gov/vuln/detail/CVE-2021-38194
9. **memory-safety — CVE-2022-23639 (crossbeam) under A07**: Filed as a Stacked/Tree-Borrows aliasing violation. Real = alignment-assumption bug (`alignof({i,u}64) < Atomic{I,U}64` on 32-bit) → unaligned access + data race (CWE-362), RUSTSEC-2022-0041. Reclassify to alignment/atomics, not aliasing. https://rustsec.org/advisories/RUSTSEC-2022-0041.html
10. **resource-exhaustion — Ethereum devp2p Neighbors amplification (2019)** [ANCHOR]: Invented length-prefix `Vec` allocation of size N=2^32. Real = UDP reflection/amplification via missing endpoint-proof (ping-pong) before answering FindNode; response is protocol-capped (≤16 nodes/1280 bytes). Fix = endpoint-proof verification, not an allocation cap. Rewrite the anchor. https://medium.com/@bitfly/parity-and-aleth-ethereum-nodes-vulnerable-to-traffic-amplification-attacks-4453307cce3c
11. **resource-exhaustion — RUSTSEC-2022-0084 / CVE-2022-23486 (rust-libp2p) under F01**: Labeled "gossipsub peer-score map unbounded growth." Real = general stream-multiplexer (mplex/yamux) resource-management DoS, no backpressure. The gossipsub peer-score OOM is a **js-libp2p (Node.js)** advisory. Relabel mechanism. https://rustsec.org/advisories/RUSTSEC-2022-0084.html
12. **unsafe-trait — CVE-2022-23639 (crossbeam AtomicCell)** [ANCHOR, ×2 — anchor case + B02 procedure]: Described as `unsafe impl Sync` violation via spinlock TOCTOU race. Real = alignment-assumption bug (same as #9). The spinlock/TOCTOU mechanism is a conflation with GitHub issue #644 (which has no CVE). Wrong bug AND wrong bug family for a chapter on unsound Sync/Send. Replace the anchor with a real `unsafe impl Sync/Send` advisory. https://rustsec.org/advisories/RUSTSEC-2022-0041.html

### B. MISATTRIBUTED — real ID, wrong project

13. **arithmetic — "Monero Oxide F-15 (Kudelski / HackerOne)"**: Auditor was **Cypher Stack**, not Kudelski (Kudelski audited Monero Bulletproofs separately). The published Cypher Stack serai audit uses no numbered finding IDs and contains no ring-underflow finding. The "F-15" ID, Kudelski attribution, and HackerOne source are all unconfirmed. Keep the `(highest - len) < ring_size` pattern as generic, drop the fabricated citation. https://github.com/cypherstack/serai-audit
14. **crypto-misuse — CVE-2019-14858**: Cited as python-ecdsa out-of-range r/s acceptance. Real = Ansible `no_log` info-disclosure bug. The python-ecdsa malleability CVE is **CVE-2019-14859** (DER-encoding malleability) — and even that doesn't match the dossier's "is_valid accepted out-of-range r/s" description. Both ID and described bug are wrong. https://nvd.nist.gov/vuln/detail/CVE-2019-14858
15. **memory-safety — CVE-2022-31094** [repeated ×4: Anchor 2, A02, A04, G-03]: Attached to a fabricated "Substrate memory_units crate" buffer-overflow (`Vec::from_raw_parts`, FFI `size_t`→u32 truncation). Real = **ScratchTools** stored-XSS browser extension (GHSA-6r45-jjw6-q39x). `memory_units` is a real crate (from wee_alloc) but NOT Substrate and has no such advisory. The whole story is fabricated; delete or replace. https://nvd.nist.gov/vuln/detail/CVE-2022-31094
16. **supply-chain-ffi — CVE-2022-31094** [ANCHOR, ×3: header, anchor box, H01]: Same misattribution as #15 — cited as Substrate memory_units WASM-DoS, "the defining pattern of supply-chain bugs in DLT infrastructure." Real = ScratchTools XSS. Replace with a real Substrate/parity-wasm/wasmi advisory if a Rust WASM-DoS anchor is desired. https://nvd.nist.gov/vuln/detail/CVE-2022-31094
17. **supply-chain-ffi — RUSTSEC-2023-0071**: Cited as the `shlex` crate. Real = the **`rsa`** crate Marvin Attack (timing side-channel, CVE-2023-49092). The correct shlex advisory is **RUSTSEC-2024-0006 / CVE-2024-58266** (command-injection via unescaped `{` / `\xa0`, fixed 1.2.1). Swap the ID. https://rustsec.org/advisories/RUSTSEC-2023-0071
18. **resource-exhaustion — CVE-2018-20990** [×2: F01/F05 table, §2 source]: Cited as rust-smallvec OOM (F05). Real = the **`tar`** crate arbitrary file overwrite via symlink/hardlink (CWE-59, path traversal). The real smallvec advisory is CVE-2018-20991 / RUSTSEC-2018-0003 (double-free), which is *also* not an OOM bug — so wrong ID AND wrong class. https://nvd.nist.gov/vuln/detail/CVE-2018-20990

### C. FABRICATED — identifier does not exist

19. **arithmetic — "SoK: Security of Solana Programs"**: No paper with this exact title exists (dossier already hedges `[model-knowledge — likely exists]`). Real corpus: "Exploring Vulnerabilities and Concerns in Solana Smart Contracts" (arXiv:2504.07419) and VRust (CCS 2022). Replace the fabricated title with a real citation. https://arxiv.org/abs/2504.07419

## 4. Cross-Dossier Contradictions

Two CVEs are cited in more than one dossier — and in both cases the descriptions conflict, which is a useful internal-consistency signal:

1. **CVE-2022-23639 (crossbeam-utils / AtomicCell)** appears in **memory-safety** (filed as A07 Stacked/Tree-Borrows aliasing) and in **unsafe-trait** (filed as an `unsafe impl Sync` spinlock-TOCTOU race). These are two *different wrong* descriptions of the same advisory. The single correct fact — an alignment-assumption bug causing unaligned access + data race on 32-bit targets (RUSTSEC-2022-0041) — appears in neither. The contradiction confirms both are reconstructions from model knowledge, not from the advisory text.
2. **CVE-2022-31094** appears in **memory-safety** (fabricated "Substrate memory_units buffer overflow") and **supply-chain-ffi** (fabricated "Substrate memory_units WASM-DoS"). Two different fabricated mechanisms, same misattributed ScratchTools-XSS ID. The shared error strongly suggests a common upstream hallucination propagated across dossiers — worth a global grep for `memory_units` and `CVE-2022-31094` across the whole reference tree.

No other CVE is shared across dossiers. (Heartbleed/CVE-2014-0160 is cited in both crypto-misuse and memory-safety but described correctly and consistently in both — flagged only as cross-language analogy weakness, not a contradiction.)

## 5. Pattern Analysis

**Overall: systematically over-claimed at the evidence layer, sound at the methodology layer. Verified rate = 30/71 = 42% per-claim (38% if cross-language analogy anchors are excluded).**

The unverified content is NOT "mostly-right-but-sloppy." The error distribution is bimodal and structural:

- **Where dossiers commit to specifics (CVE/RUSTSEC IDs, named auditors, named incidents), they fail hard.** Every concrete numeric identifier checked across the corpus that wasn't a well-known public crypto incident was wrong: 7 misattributions + 1 fabrication + 13 wrong-descriptions = 21/71 (30%) are confirmed errors on load-bearing specifics. The "Tier-3 CVE list" pattern (crypto-misuse: both numeric CVEs wrong) and the "anchor case" pattern (memory-safety, supply-chain, unsafe-trait, resource-exhaustion, concurrency all have wrong/fabricated anchors) show the failures cluster at exactly the points the dossiers lean on hardest.
- **Where dossiers stay at class/methodology level, they mostly hold.** concurrency (0 VERIFIED) and crypto-misuse (14/17 VERIFIED) bracket the range: concurrency invents named incidents for every taxonomy row (9 UNVERIFIABLE — generic pattern + project name appended), while crypto-misuse anchors on *real, famous, well-documented* public crypto history (Android SecureRandom, Sony PS3, SHAttered, Lucky13, Minerva, TPM-FAIL) and scores 82%.
- **The dominant failure modes, named:** (1) *analogy-as-anchor* — a real incident name attached to an invented mechanism (Parity OnDemand, devp2p amplification, Wormhole, Binance Bridge, Solana PoH); (2) *ID-belongs-to-something-else* — off-by-one or cross-domain CVE confusion (14858↔14859, 20990↔20991, 2023-0071↔2024-0006, 31094=ScratchTools); (3) *project-name-as-citation* — "Aptos consensus mutex ordering", "Substrate runtime storage race" — methodology dressed as a documented bug.
- **Cross-language grounding is pervasive but disclosed.** Multiple VERIFIED claims are Solidity/EVM (Compound, Lido, MakerDAO), Go (Cosmos SDK, geth, Tendermint), or C (Heartbleed, Slowloris) — real and correct, but not Rust-DLT instances. The dossiers generally flag this; it weakens Rust-native grounding but isn't an error.

**Honesty offsets severity.** No dossier asserted a fabricated CVE *number* as confirmed fact — the one FABRICATED item was a paper title the dossier itself hedged. The `[model-knowledge]` tagging and "0 primary sources" headers mean the corpus is disclosed-unverified, not deceptively-confident. That is the difference between "corrections pass" and "roll back."

## 6. Recommendation

**Targeted corrections pass — do NOT roll back, do NOT ship as-is.**

Concrete next steps, in priority order:

1. **Fix the 21 confirmed errors (Section 3) before any dossier feeds its `*-agent.md`.** The 5 anchor-case errors (Parity OnDemand, arkworks CVE-2021-38194, devp2p amplification, crossbeam in both memory-safety and unsafe-trait, supply-chain CVE-2022-31094) are top priority — anchors are load-bearing and propagate framing into the agent prompts.
2. **Run two global greps now:** `CVE-2022-31094` and `memory_units` (cross-dossier fabrication, ≥7 occurrences), and `RUSTSEC-2023-0071` / `shlex` (off-by-year ID swap). Fix every occurrence, not just the table rows.
3. **Triage the 3 major-problems dossiers (concurrency, memory-safety, supply-chain-ffi, unsafe-trait) for a stricter rewrite:** every "Real instance" must become either a real advisory/issue URL or an explicit `[generic pattern — no specific incident]` label. concurrency in particular has zero verified incidents — strip all 11 project-name-appended "real instances" to honest generic-pattern statements or replace with the real adjacent issues the verifier surfaced (e.g., solana-labs#16102 for async-lock deadlock, paritytech/substrate#6335 for gossip).
4. **Accept-with-caveats for crypto-misuse and the class-level claims in logic-state-machine** after fixing the 2 CVE errors (crypto-misuse) and the Solana PoH mechanism (logic-state) — these have a real, defensible evidence base.
5. **Keep the methodology content unchanged** — taxonomies, per-class procedures, and Rust-native tooling (Kani, Miri, Loom, Rudra, cargo-fuzz) are sound and verified-by-construction; they do not depend on the broken anchors.

Until steps 1–3 are complete, this v0.6.3 work is **acceptable-as-internal-draft, NOT acceptable as evidence-grounded reference material.**

> AI-provenance reminder: this report is a synthesis of automated per-dossier verification results; every correction URL should be re-confirmed by a human against the primary source before edits land.
