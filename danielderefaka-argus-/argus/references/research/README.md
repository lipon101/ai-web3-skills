# Research Dossiers — grounding angles in evidence, not intuition

> **Why this directory exists**: Argus's Stage-2 angles were written from first-principles reasoning ("what could go wrong in concurrent code?"). That produces surface-level pattern matching. The Orchard finding proved the gap: a real bug required framework-specific knowledge (Halo2's `assign_advice` vs `copy_advice`), a published-research understanding of constraint composition, and mechanical tooling (MockProver) the angle didn't know existed. One real vulnerability sharpened the ZK angle more than months of additive angle-writing.
>
> A **research dossier** is the evidence base for one angle. It is built BEFORE (or to retrofit) the angle's methodology. The angle file (`hacking-agents/**/*-agent.md`) is the *operational distillation*; the dossier is the *source material* it was distilled from.

## The core discipline: methodology, not patterns

This is the single rule that separates a good dossier from a bug list.

- **Pattern** (weak): "Check for missing `copy_advice` in Halo2 EC mul." Catches one bug. Overfits. Dies the moment the next bug looks different.
- **Methodology** (strong): "For every assigned cell, verify at least one gate constrains it to its intended value — not just to internal consistency with sibling cells." Catches Orchard AND the next missing-constraint bug that looks nothing like it.

Every dossier finding must answer: **"What systematic procedure would have discovered this — without already knowing the answer?"** If the only procedure is "look for exactly this bug," it belongs in a RAG/precedent note, not in angle methodology. (This mirrors the RC-METHOD vs RC-AGENT distinction: a methodology gap is fixable in the pipeline; a one-off pattern is not.)

## The verification mandate (MANDATORY — learned the hard way)

A dossier written from model memory is not evidence-grounded — it is plausible-sounding fiction with real-looking citations. This is not hypothetical: the first v0.6.3 sweep authored 8 dossiers from model knowledge, and an adversarial verification pass (each claim fetched against NVD/RUSTSEC/GHSA) found **only 38% of real-world claims verified** — with fabricated anchors (a Substrate `memory_units` buffer-overflow story attached to a CVE that is actually a browser-extension XSS), misattributed CVE ids (CVE-2019-14858 is Ansible, not python-ecdsa), and marquee incidents described with invented mechanisms (Wormhole as a truncation bug — it was a signature bypass). The re-research pass, which *fetched primary sources*, produced 0 such errors.

Therefore, before any dossier is marked `drafted-verified` or feeds an `*-agent.md`:

1. **Every real-world claim** — any CVE / RUSTSEC / GHSA id or named incident — MUST be confirmed by a *fetched primary source* (NVD, rustsec.org / rustsec advisory-db, GitHub Security Advisories, or the vendor's own disclosure) that confirms **both** the identifier **and** the mechanism. Cite the URL in section 7.
2. **No id on an unverified mechanism.** If a source cannot be fetched, the claim is dropped or carried as `[generic pattern — no specific incident]` with **no** identifier attached. A real advisory id next to a wrong mechanism is worse than no citation — it manufactures false confidence.
3. **Cross-language precedents** (Go / C / Solidity) are allowed but must be labeled as such; they are weaker than Rust-native instances and never count as the primary anchor.
4. **Status discipline**: `scaffold` → `drafted` (model-knowledge, unverified — NOT usable) → `drafted-verified` (every id fetched) → `wired-into-angle`. Only `drafted-verified` and later may inform an agent file.

The model-knowledge draft is a starting skeleton, not a deliverable. The web-verification fan-out is what turns it into evidence. Skipping it reintroduces the 62% error rate.

## Source taxonomy (where evidence comes from, strongest first)

| Tier | Source type | Why it ranks here | Examples |
|------|-------------|-------------------|----------|
| 1 | **Published post-mortems with root-cause + fix** | Ground truth: a real exploit, the exact code, the exact fix. The Orchard work log is the gold standard. | Zcash Orchard disclosure, chain-halt retrospectives, Immunefi paid-bounty write-ups |
| 2 | **Professional audit reports (public)** | Methodology you can reverse-engineer: what the auditors actually checked, in what order. | Trail of Bits, Veridise, OtterSec, Zellic, NCC Group public reports |
| 3 | **CVE / advisory databases** | Breadth: the real distribution of bug classes in production, with affected versions. | RustSec (RUSTSEC-*), GHSA, NVD, OSV |
| 4 | **Framework internals + docs** | The substrate-specific knowledge generic Rust review misses. Orchard needed the Halo2 book. | Halo2 book, arkworks docs, Cosmos SDK ADRs, Solana docs, Substrate FRAME guide |
| 5 | **Academic papers / formal-methods work** | Techniques that can be operationalized into a check or a tool. | Circuit constraint-completeness verification, RustBelt, TLA+ consensus specs |
| 6 | **Model/tooling capability data** | Calibrates discovery expectations and dispatch (which model, how directed). | The Orchard 1/4-vs-directed hit-rate data |

A dossier is weak if it draws only from tiers 5–6 (theory) and strong if it is anchored in tiers 1–3 (what actually broke).

## Dossier structure (template)

Each dossier lives at `references/research/<angle>-research.md` and follows this shape. Keep it operational — it feeds an agent, it is not an essay.

```markdown
# <Angle> — Research Dossier

> **Feeds**: hacking-agents/<path>/<angle>-agent.md
> **Last research pass**: <YYYY-MM-DD> · **Sources reviewed**: <N>
> **Status**: scaffold | drafted | wired-into-angle

## 1. Bug-class taxonomy
What distinct failure classes exist in this domain? One row per class.
| Class | One-line mechanism | Real instance (source) | Already an Argus vector? |

## 2. Per-class methodology
For each class above — the systematic discovery procedure (NOT "look for X").
### <Class name>
- **Signal**: what in the code says "look here"
- **Procedure**: the step-by-step check that finds it without knowing the answer
- **Mechanical evidence**: the tool/test that turns suspicion into proof (the tier-1 PoC shape)
- **Anti-pattern**: what looks like this class but isn't (false-positive guard)
- **Source**: <tier-N citation>

## 3. Framework-specific knowledge
Substrate-specific facts generic Rust review misses. API semantics, idioms, footguns.

## 4. Tooling
Deterministic backends that produce ground truth for this angle. Install/invoke/golden-signature.

## 5. Discovery calibration
Model/effort/prompt-directedness data, where it exists. Informs dispatch in the angle file.

## 6. Gaps → angle changes
The actionable output. For each new methodology this dossier justifies:
| Methodology | New CHECK / vector / tool | Change type | Anti-bloat: does an existing check already cover it? |

## 7. Sources
Full citation list with URLs and access dates.
```

## How a dossier becomes angle methodology

1. Build/refresh the dossier (this directory).
2. Run section 6 (Gaps → angle changes) through the anti-bloat test: does an existing CHECK/vector already cover it? If yes → tune the trigger, don't add. If no → add the minimal methodology.
3. Wire approved changes into the angle file as CHECK steps or into the vector catalogue as new IDs.
4. Bump VERSION + CHANGELOG. Mark the dossier `wired-into-angle`.
5. The dossier stays as the audit trail — when a future finding exposes a new gap, the dossier is where the next research pass appends.

## Program order

The ZK Circuit Soundness dossier is built first as the template, because it already has a tier-1 post-mortem (Orchard) and concrete methodology to validate the format against. The remaining angles follow one at a time; each dossier is a discrete, reviewable unit of work, not a big-bang rewrite.

## What a dossier must NOT be

- A bug list. (That's patterns. See "methodology, not patterns".)
- A theory dump from tiers 5–6 with no tier-1–3 anchor.
- A duplicate of the angle file. The angle is the distillation; the dossier is the evidence.
- Marketing. State the failure, cite the source, give the procedure, stop.
