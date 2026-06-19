# AGENTS.md — rules for Codex when extending Argus

Instructions for Codex when contributing to the Argus skill.

## What this repo is

A single Codex skill named **argus** — a Rust-first, submission-grade audit pipeline. Not a marketplace of skills; one focused capability with progressive disclosure across reference files.

## Structure rules

- One skill, one purpose. Argus does end-to-end Rust audit + fix verification — that is the entire scope.
- `SKILL.md` is the methodology. Keep it concise (under 200 lines). All detail lives in `references/`.
- `references/` uses subfolders for organization:
  - `hacking-agents/` — one file per Stage 2 attacker angle.
  - `attack-vectors/` — Rust-native vector library, expandable.
  - `platform-criteria/` — one file per supported bug-bounty / contest platform.
- New stages, new angles, or new platforms each get their own file. Do not bloat existing files.

## Writing rules

- No fabricated examples. Outputs must reflect real model behavior on real Rust code.
- No secrets, API keys, or personal data anywhere in the repo.
- Code citations always include `file:line` (or `crate::module::function`). Prose alone is not evidence.
- If you write code samples in references, they must be valid Rust (parseable by `rustc --crate-type lib --emit=metadata`). No pseudo-code where real code would do.

## Versioning

- `VERSION` file is the single source of truth for the skill version.
- Every change updates `CHANGELOG.md` BEFORE the change is considered complete. Entries go under the current version section with the appropriate category (`Added` / `Changed` / `Fixed` / `Removed`). If a new version section doesn't exist, create one. Never modify entries for already-released versions.
- Bump `VERSION` on any user-visible behavior change (not just doc fixes).

## Stage discipline

Argus's value comes from the staged pipeline. When adding to it:

- New stages must define INPUT / OPERATIONS / OUTPUT / VERDICT / KILL CRITERIA / EXIT CONDITION (the contract template in `pipeline-overview.md`).
- New stages must integrate into the finding state machine. They cannot read past the immediate prior stage's output.
- New stages cannot UPGRADE severity. Pass D in Stage 4 is the only severity-grade authority. Later stages may DOWNGRADE only.

## Writing for the audit catalogue

When adding to `references/hacking-agents/<angle>-agent.md` or `references/attack-vectors/rust-attack-vectors.md`:

- The angle / vector must be **Rust-native**. If the description reads like a Solidity item with Rust labels swapped in, rewrite it from first principles using the Rust ecosystem's actual primitives (Anchor constraints, CosmWasm `info.sender`, Substrate `Origin`, Borsh / scale-codec, SPL Token-2022, etc.).
- Every entry includes: signal (how to detect it), failure (what goes wrong), code-citation pattern (what to grep / Read for).
- New vectors get an ID (`V36`, `V37`, …) and integrate into the Vector Scan agent's classification block.

## Platform criteria

When adding a new platform (or updating an existing one):

- Source the rules from the platform's published criteria page (URL in the file header).
- Bundled criteria are kept current to project sources at the time of release. **Live page wins** — the file must include the WebFetch divergence-check note.
- Severity definitions, automatic-invalidator list (with IDs), PoC requirements, and quality signals are mandatory sections.

## Tone and brevity

- Reference files are operational — they tell the model what to do, not what someone thinks about the topic.
- Bullet brevity: one tight sentence per bullet, max two lines. The code reference carries the evidence; prose must not duplicate it.
- No marketing language. No "comprehensive" / "robust" / "industry-leading". State the function, stop.

## Banned

- Do not turn Argus into a multi-skill marketplace. One skill, one purpose.
- Do not skip the AI-provenance discipline. Every output that goes to the user must carry the manual-validation reminder.
- Do not loosen the severity rules. Pass D upgrades and Stage 5-7 downgrades — never the reverse.
- Do not add features that aren't gated by stages. Argus's value is the gates.
