<div align="center">

# Argus

**A Rust-first, submission-grade security audit pipeline.**

One command runs an 8-stage adversarial pipeline end-to-end — from protocol map to
platform-ready findings — across both smart contracts and DLT infrastructure.

[![Version](https://img.shields.io/badge/version-0.6.5-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Rust-first](https://img.shields.io/badge/Rust--first-native-orange.svg)](references/rust-protocol-types.md)
[![Runtimes](https://img.shields.io/badge/Claude%20Code%20%7C%20Codex%20CLI-supported-8A2BE2.svg)](references/codex-compat.md)

[Install](#install) · [Usage](#usage) · [What you get](#what-you-get) · [Modes](#two-modes) · [Changelog](CHANGELOG.md)

</div>

---

Argus runs one command, picks a mode at Stage 0 (auto-default by project shape, user-overridable),
and writes a single timestamped output folder to `<project-root>/argus/<UTC-timestamp>/`.
It is built for Rust ecosystems from first principles — not a Solidity skill with Rust labels.

**Current version**: 0.6.5 — see [CHANGELOG.md](CHANGELOG.md). See [`references/audit-modes.md`](references/audit-modes.md)
for the mode-routing index, and [`references/research/`](references/research/) for the verified dossiers behind every infra angle.

## Two modes

| | **`smart-contract` mode** (legacy) | **`infra` mode** |
|---|---|---|
| **Target** | Solana Anchor · CosmWasm · Substrate pallets | Validator clients · consensus engines · p2p networking · crypto libraries · storage engines · RPC nodes · bridge relayers · wallets · smart-contract VMs |
| **Method** | LLM-driven 8-angle adversarial review (Pass A/B/C/D) | 9 evidence-grounded attacker angles, each distilled from a primary-source-verified research dossier |
| **Coverage** | 132-vector Rust-native library | Arithmetic · concurrency · crypto-misuse · logic/state-machine · memory-safety · resource-exhaustion · supply-chain/FFI · unsafe-trait · ZK-circuit-soundness |
| **Verification** | PoC gate (Tier 1-4) | Deterministic backends — Miri · Kani · Loom · Rudra · cargo-fuzz · cargo-audit · cargo-deny · cargo-geiger · Clippy — at Stage 3 |
| **Verdict** | Contest-platform criteria (Code4rena · Sherlock · Cantina · Immunefi · HackenProof · CodeHawks) | Impact × Reachability matrix at Stage 4 (tool output **is** the verdict — no Pass A/B/C/D); CVE disclosure workflow at Stage 6 |

Each infra dossier traces every bug class to a real, fetched advisory (RUSTSEC / CVE / GHSA) — not intuition. See [Evidence-grounded](#evidence-grounded-infra-mode).

## What you get

One command runs an 8-stage pipeline and produces a single output folder under `<project-root>/argus/<UTC-timestamp>/`:

| Output | What's inside |
|--------|---------------|
| `1-protocol-map/` | Protocol overview, attack surface, trust model, entry points, invariants, hot zones |
| `2-candidate-findings/` | One `F-NN.md` per candidate finding (8 parallel angles, deduped by `group_key`) |
| `3-poc/F-NN/` | Runnable PoC, repro steps, gate verdict (Tier 1-4) |
| `4-adversarial/F-NN.md` | 4-pass adversarial review (selector + generator + symmetric judge + severity calibrator) |
| `5-platform/F-NN.md` | Platform-fit verdict + score (per-platform AI-N rules) |
| `6-program/F-NN.md` | Live bounty-page triage |
| `7-duplication/F-NN.md` | GitHub duplicate probes |
| `8-final/{submission-grade,refine,discard}.md` | Final ranked output (only the strongest survive) |

Optional **Stage 9** (fix verification) consumes a vulnerability description + a fix diff and produces `PASS | FAIL | NEEDS REVIEW`.

## Built for

- **Rust security researchers** running end-to-end audits on Solana / Anchor, CosmWasm, Substrate, generic Rust services
- **Protocol teams** preparing for an audit — fix the obvious so auditors can focus on what matters
- **Bug-bounty hunters** who want submission-grade output, not a noisy candidate dump

Not a substitute for a formal audit — but the discipline you need to stop submitting AI-generated false positives.

## Install

### Option 1 — Quick install (Bash)

```bash
git clone https://github.com/DanielDerefaka/argus.git
cd argus
chmod +x install.sh
./install.sh                    # installs to every detected target (Claude Code + Codex CLI)
# ./install.sh --target claude  # Claude Code only
# ./install.sh --target codex   # Codex CLI only
```

Installs Argus to `~/.claude/skills/argus/` and/or `~/.codex/skills/argus/` (whichever are present) and registers `/argus`, `/argus-fix-verify`, `/argus-doctor`, and `/argus-resume` as Claude Code slash commands. Restart Codex once after install to pick up the skill — see [`references/codex-compat.md`](references/codex-compat.md) for Codex tool-translation notes.

### Option 2 — Claude Code plugin marketplace

Add to your `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "argus": {
      "source": {
        "source": "github",
        "repo": "<argus-repo>"
      }
    }
  },
  "enabledPlugins": {
    "argus@argus": true
  }
}
```

### Option 3 — Manual

1. Run `/plugin` in Claude Code
2. Go to the **Marketplaces** tab
3. Add a marketplace pointing at the Argus repo
4. Install the `argus` plugin

## Usage

```
/argus
```

Argus prompts you (once) for:

- The Rust target path (default = cwd)
- The bounty / program URL (Stage 6 source of truth)
- The target project's GitHub repo URL (Stage 7)
- A manual-validation acknowledgment (Stage 5 — required for Cantina targets)

Then the pipeline runs autonomously. Output appears under `<target>/argus/<UTC-timestamp>/`.

**Verify a fix:**

```
/argus-fix-verify
```

**Check your install or resume an interrupted run:**

```
/argus-doctor              ← check the skill is wired in correctly (add --check-rust for infra toolchain)
/argus-resume <run-dir>    ← pick up an interrupted run at its last checkpoint
```

## Why "Rust-first"

Argus is **not** a Solidity audit skill with Rust labels. The audit catalogue is Rust-native:

- Anchor `signer` / `has_one` / `seeds` / `bump` constraint patterns
- Solana PDA confusion (`find_program_address` vs `create_program_address`), account-substitution, account-discriminator gaps
- CosmWasm `info.sender` / `cw-ownable` / submessage `reply` re-entry
- Substrate `ensure_signed` / `ensure_root` / origin confusion / weight DoS
- SPL Token-2022 transfer hooks + transfer fees
- `unwrap()` / `expect()` / `as`-truncation / unchecked `+ - * /` on `u64`/`u128`
- Borsh / scale-codec / serde deserialization edge cases (length-prefix DoS, canonical-form collisions)
- `unsafe` blocks, `Send` / `Sync` violations, async cancellation safety
- IBC / bridge / cross-pallet integration risks

See [references/rust-protocol-types.md](references/rust-protocol-types.md) for the full per-protocol-type threat profiles, and [references/dlt-infra-types.md](references/dlt-infra-types.md) for the infra-mode threat profiles.

## Evidence-grounded (infra mode)

Every infra-mode angle is built from a **research dossier** that traces each bug class to a real, fetched advisory — not "what could go wrong" intuition. The dossiers live in [`references/research/`](references/research/) and follow a hard rule (the [verification mandate](references/research/README.md)): **no claim ships without a primary source.** A model-knowledge draft of these dossiers once verified at only 38% (fabricated CVEs, misattributions); they were re-researched against NVD / RUSTSEC / GHSA until every advisory id resolved. Anything not confirmable is labelled `[generic pattern — no specific incident]` with no id attached — methodology, never a fake citation.

This is what keeps infra mode from raising "fake surface bugs": the angles look for **real** vulnerability shapes, and a finding is only CONFIRMED when a deterministic backend (Miri / Kani / Loom / cargo-fuzz) reproduces it at Stage 3.

## ⚠️ AI-provenance discipline

Argus is AI tooling. Findings produced by Argus pipelines are AI-generated by definition. **Cantina explicitly bans unverified AI-generated findings (rule AI-3) and enforces detection aggressively.** Other platforms increasingly do the same.

Before submitting any Argus finding to any platform:

1. Manually re-read the cited code at the cited line numbers
2. Independently re-derive the exploit path
3. Run the PoC yourself and confirm the output
4. Re-verify scope against the live program page
5. Re-write the writeup in your own words

For Cantina targets, Stage 5 enforces a manual-validation-acknowledgment gate before any finding ADVANCEs. For other platforms, the discipline is strongly recommended via Stage 8 output.

## Tips

- **Start at the verdict.** Argus's `8-final/submission-grade.md` is allowed to be empty. An empty SUBMIT bucket is a successful run when nothing survived. Don't pad it.
- **Rerun.** LLM output is non-deterministic. Two passes over the same code often catch things one pass misses.
- **Use `2-candidate-findings/leads.md`** as a manual-investigation queue — high-signal trails that didn't reach FINDING confidence.
- **Trust the kills.** Argus is intentionally severe. A `KILL(refuted)` at Stage 4 means a code citation blocks the PoC's exact step — believe it before re-litigating.
- **Don't override Stage 4 Pass D severity calibration.** It's allowed to UPGRADE, not just downgrade — claimed severity is not a ceiling.

## Repository layout

<details>
<summary>Click to expand the full tree</summary>

```
argus/
├── README.md                          ← this file
├── SKILL.md                           ← methodology (read by Claude Code)
├── VERSION
├── CHANGELOG.md
├── CLAUDE.md                          ← rules for Claude when extending Argus
├── LICENSE
├── install.sh
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── commands/
│   ├── argus.md                       ← /argus slash command
│   └── argus-fix-verify.md            ← /argus-fix-verify slash command
├── agents/
│   └── openai.yaml                    ← OpenAI-compatible agent definition
├── references/
│   ├── pipeline-overview.md           ← spine — handoff contract for every stage
│   ├── poc-standards.md
│   ├── adversarial-review.md          ← invalidation library + Pass D
│   ├── platform-validation.md
│   ├── program-triage.md
│   ├── duplication-check.md
│   ├── output-format.md
│   ├── fix-verification.md
│   ├── rust-protocol-types.md         ← protocol-type threat profiles + temporal + composability
│   ├── attack-vectors/
│   │   └── rust-attack-vectors.md     ← Rust-native vector library
│   ├── hacking-agents/
│   │   ├── shared-rules.md
│   │   ├── vector-scan-agent.md
│   │   ├── math-precision-agent.md
│   │   ├── auth-account-agent.md
│   │   ├── economic-security-agent.md
│   │   ├── execution-trace-agent.md
│   │   ├── invariant-agent.md
│   │   ├── periphery-agent.md
│   │   ├── first-principles-agent.md
│   │   ├── differ-agent.md
│   │   └── infra/                     ← 9 infra-mode angles, each dossier-grounded
│   │       ├── arithmetic · concurrency · crypto-misuse · logic-state-machine
│   │       ├── memory-safety · resource-exhaustion · supply-chain-ffi · unsafe-trait
│   │       ├── zk-circuit-soundness-agent.md
│   │       └── depth-methodology.md
│   ├── research/                      ← primary-source-verified dossiers (evidence base per angle)
│   │   ├── README.md (verification mandate) · RESEARCH-INDEX.md
│   │   ├── <angle>-research.md × 9 · zk-framework-constraint-surface.md
│   │   └── VERIFICATION-REPORT-v0.6.3.md
│   └── platform-criteria/
│       ├── code4rena.md
│       ├── sherlock.md
│       ├── sherlock-bb.md
│       ├── cantina-comp.md
│       ├── cantina-bb.md
│       ├── immunefi.md
│       ├── hackenproof.md
│       └── generic.md
├── evals/                             ← benchmark runner + ground-truth comparison
│   ├── runner.md
│   ├── compare.md
│   └── benchmarks/
│       └── README.md
└── assets/                            ← prior findings + project docs (per-run)
    ├── docs/README.md
    └── findings/README.md
```

</details>

## License

MIT. See [LICENSE](LICENSE).

## Credits

Argus extracts and adapts workflow ideas from:

- **X-Ray** (Pashov Audit Group) — protocol mapping discipline, TodoWrite phasing, "code reading wins over subagent summaries"
- **Solidity Auditor** (Pashov Audit Group) — 8 parallel attacker angles, structured FINDING/LEAD format with `group_key` dedup, weaponize-across-codebase rule
- **The Judge** (heavyw8t) — invalidation library (UP/CP/DT/EG/US/SH/DI/TI/SC/IM/AM/OS), symmetric judge trigger, Pass D severity calibrator, anti-hallucination UNCERTAIN rule
- **Bug Validator** (mettal / santiagoib) — per-platform AI-N rule lists, subtractive scoring, severity-alignment discipline
- **HackenProof Skills** — pre-validation gates, reversibility rule (Need More Info > premature invalidation), fix verification 5-phase

The audit logic is rebuilt from these patterns for Rust ecosystems — not copied.
