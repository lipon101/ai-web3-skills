# Argus Research Index

> **Purpose**: Track which angles have research dossiers (evidence-based methodology grounded in real-world vulnerabilities) and which still rely on first-principles intuition.
> **Principle**: Every angle's methodology should trace to at least one real production vulnerability, one published audit taxonomy, or one academic result. "What could go wrong?" is not sufficient. "What DID go wrong?" is the standard.

---

## Research Status by Angle

### `infra` mode — 9 angles

| Angle | Dossier | Status | Priority |
|-------|---------|--------|----------|
| **ZK Circuit Soundness** (Angle 9) | `zk-circuit-research.md` | **Verified (v0.6.2)** — 24-class taxonomy built via web-research workflow (70+ primary sources, 0 model-knowledge tags). Anchor: Zcash Orchard. Wired into agent (CHECK 1-19, J01-J16). | Wired into agent. |
| **Memory Safety** (Angle 1) | `memory-safety-research.md` | **Verified (v0.6.4)** — 14 fetched advisories. Anchors: lru `IterMut` Stacked-Borrows (RUSTSEC-2026-0002), smallvec `insert_many` OOB (RUSTSEC-2021-0003). Fabricated CVE-2022-31094 removed; agent corrected. | **High** — unsafe blocks are the most common Rust attack surface. |
| **Unsafe Trait Soundness** (Angle 2) | `unsafe-trait-research.md` | **Verified (v0.6.4)** — 9 RUSTSEC advisories + Rudra OSDI 2021. Anchor: conquer-once `OnceCell` Sync-without-Send (RUSTSEC-2020-0101). crossbeam CVE-2022-23639 corrected to an alignment-bug guard. | **Medium** — narrower than Memory Safety. |
| **Arithmetic** (Angle 3) | `arithmetic-research.md` | **Verified (v0.6.4)** — 8 fetched advisories + 6 generic-pattern classes. Wormhole/Binance/Monero-"F-15" fabrications removed (each was a non-arithmetic bug). | **High** — arithmetic bugs caused real financial loss. |
| **Concurrency** (Angle 4) | `concurrency-research.md` | **Verified (v0.6.4)** — 8 fetched advisories. Parity-"OnDemand" deadlock and AWS-Shuttle-target fabrications corrected. | **High** — concurrency bugs are consensus-critical. |
| **Crypto Misuse** (Angle 5) | `crypto-misuse-research.md` | **Verified (v0.6.4)** — 15 fetched advisories (highest-scoring dossier). CVE-2019-14858 (Ansible) and CVE-2022-31173 (recursion DoS) misattributions fixed. | **High** — crypto misuse can break the entire security model. |
| **Resource Exhaustion** (Angle 6) | `resource-exhaustion-research.md` | **Verified (v0.6.4)** — 9 fetched advisories. Anchors: rust-libp2p (RUSTSEC-2022-0084), ckb (RUSTSEC-2021-0108). CVE-2018-20990 (=`tar`, not smallvec) misattribution fixed; devp2p re-described as reflection/amplification. | **Medium** |
| **Logic & State Machine** (Angle 7) | `logic-state-machine-research.md` | **Verified (v0.6.4)** — 9 fetched sources (CometBFT/Cosmos-SDK GHSAs + correct Solana post-mortem). PoH-drift and Geth-reentrancy fabrications corrected. | **High** — logic/state bugs are the most common infra finding class. |
| **Supply Chain & FFI** (Angle 8) | `supply-chain-ffi-research.md` | **Verified (v0.6.4)** — 11 fetched advisories. Anchors: `rustdecimal` typosquat (RUSTSEC-2022-0042), shlex (RUSTSEC-2024-0006). Fabricated CVE-2022-31094 and misattributed RUSTSEC-2023-0071 removed. | **Medium** |

### `smart-contract` mode — 10 angles

| Angle | Dossier | Status | Priority |
|-------|---------|--------|----------|
| Vector Scan | — | Not started | Medium |
| Math Precision | — | Not started | High — real financial loss bugs |
| Auth / Account / Signer | — | Not started | High |
| Economic Security | — | Not started | Medium |
| Execution Trace | — | Not started | Medium |
| Invariant | — | Not started | Medium |
| Periphery | — | Not started | Low |
| First Principles | — | Not started | Low |
| Crypto Soundness | — | Not started | Medium |
| Differ | — | Not started | Medium |

---

## Research Dossier Template

Every dossier should follow `zk-circuit-research.md`'s structure:

```
1. Known vulnerabilities (production) — with root cause, code citation, disclosure source
2. Research organizations & publications — who has published on this domain?
3. Vulnerability taxonomy — from real findings, not intuition
4. Tooling landscape — what tools exist? What can we integrate?
5. Academic papers — formal results, survey papers, empirical studies
6. Public audit reports — what did real audits find?
7. Methodology extraction — how each finding maps to a methodology CHECK
8. Gap analysis — what methodology are we still missing?
9. Immediate action items — prioritized next steps
```

---

## Sourcing Rules

1. **Every vulnerability cited must include**: project name, root cause (with code citation if available), disclosure source, severity.
2. **Taxonomies must be from public sources**: audit firm publications, academic papers, CVE databases. No "I think this class exists" entries.
3. **Methodology extraction must be traceable**: each CHECK in an agent file should cite which specific finding(s) it was derived from.
4. **`[INCOMPLETE]` tags are required** on any claim that hasn't been verified against a primary source. Do not remove the tag until the source is read.
5. **No fabricated references**. If we know a publication exists but don't have the URL, note it as `[INCOMPLETE]` with what we know about it.

---

## Research Cadence

The plan: one dossier per angle, priority order, each one building the evidence base that the methodology rests on. Each dossier is a standalone `references/research/<angle>-research.md` file. The angle's agent file links to it. The CHANGELOG gets an entry when a dossier is created or substantially updated.

**Status**: **All 9 infra angles have primary-source-verified dossiers** (ZK at v0.6.2; the other 8 re-researched and verified at v0.6.4 after the v0.6.3 model-knowledge drafts failed verification at 38% — see `VERIFICATION-REPORT-v0.6.3.md`). Every retained advisory carries a fetched URL; unverifiable classes are labeled `[generic pattern — no specific incident]`. The 4 agent files that had propagated wrong CVEs are corrected. **Remaining**: wire the verified dossiers' `## 6 Gaps → angle changes` into each agent file (methodology, not just citations); smart-contract mode angles (10, not started).
