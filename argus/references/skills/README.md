# Argus Skills (v0.4.2)

Operational deep-dives for specific Anchor/Solana audit surfaces. Each Stage 2 angle loads the relevant skill(s) when its bundle's `1-protocol-map/attack-surface.md` indicates the project touches that surface.

Skills are **distinct from vectors**:

- A **vector** (in `references/attack-vectors/rust-attack-vectors.md`, V1–V132) is a single failure pattern with a one-line signal and a fixed-pattern comparator. Argus has 132 of these and they're catalogue entries.
- A **skill** is a step-by-step audit procedure for a *surface* — what to enumerate, what to grep, what order to check, what counts as a finding vs noise, what comparators to cite. A skill loads multiple vectors as evidence points.

## Skill catalogue (v0.4.2)

| Skill | Loads when | Loaded by angle(s) | Primary vectors |
|-------|-----------|--------------------|-----------------|
| [`anchor-account-validation`](anchor-account-validation.md) | Project uses Anchor framework (`Anchor.toml` exists OR any `#[derive(Accounts)]` struct in source) | Auth/Account, Vector Scan, First Principles | V1, V4, V40 |
| [`anchor-cpi-safety`](anchor-cpi-safety.md) | Any `CpiContext::new` / `invoke` / `invoke_signed` call site in scope | Periphery, Execution Trace, Auth/Account | V3, V36, V42 |
| [`pda-seed-space`](pda-seed-space.md) | Any `Pubkey::find_program_address` / `create_program_address` / Anchor `seeds = [..]` usage | Auth/Account, First Principles | V3, V40 |
| [`spl-token-2022-extensions`](spl-token-2022-extensions.md) | Project imports `spl-token-2022` OR uses Token-2022 mint accounts | Periphery, Economic, Invariant | V89, V90 (extension-aware variants) |
| [`solana-sysvars-and-clock`](solana-sysvars-and-clock.md) | Any `Clock::get` / sysvar account / `Sysvar<'info, Clock>` / `recent_blockhashes` reference | Execution Trace, Math Precision, Invariant | V117, V125 |
| [`rust-panics-in-bpf`](rust-panics-in-bpf.md) | All Anchor / Solana-native programs (every BPF target where panic = transaction abort = DoS) | Vector Scan, Math Precision, infra Resource-Exhaustion | V25, V26, V81 |

## How skills are loaded

Each Stage 2 angle definition (`references/hacking-agents/*-agent.md`) has a **Load also** directive listing the skills that angle pulls in when its bundle triggers them. Stage 1's `attack-surface.md` § 10-point walk surfaces which surfaces are present; the orchestrator passes that list to each angle along with the matched skill bundle.

If a skill's load condition fires but the skill file is absent (corrupt install), the angle proceeds without it and records `skill_unavailable: <skill_name>` in its output for Stage 4 review.

## When to write a new skill

Add a skill when:

- A whole **surface** (not a single vector) recurs across audits and benefits from a dedicated audit procedure.
- The procedure has 4+ distinct sub-checks that don't fit cleanly into a single vector's "signal / fixed pattern" shape.
- Cross-cutting between multiple angles — a surface that Auth/Account, Periphery, AND Invariant all need to reason about justifies a single shared skill.

Do **not** write a skill when:

- A single new vector covers the case (add to `rust-attack-vectors.md` instead).
- The procedure is identical to an existing skill plus one bullet (extend the existing skill).
- The surface is project-specific (skills must generalize across at least 3 audits).

## Skill structure (template)

Every skill follows the same shape:

```markdown
# <Skill Name> (v0.4.x)

> Loads when: <one-line trigger>
> Primary vectors: <V-IDs from rust-attack-vectors.md>
> Coordinates with: <other skills>

## What this surface is

<1-paragraph plain-English description of the surface — what it does, why it matters>

## When to load this skill

<bullet-list of code signals: imports, derives, function calls, file patterns>

## Step-by-step audit procedure

<numbered list of mechanical checks: enumerate, grep, compare>

## What counts as a finding

<bullet list of distinct failure modes — each maps to one vector ID or one new finding-class>

## What does NOT count (SC-2 / known design)

<bullet list of intentional designs that look like bugs but aren't>

## Comparator citations

<table of canonical reference implementations + their file:line — for the comparator_citation FINDING field>

## Common false-positive shapes

<bullet list of patterns that trigger the audit signal but are sound>
```

## Wiring discipline

- Skills are read-only references. They are not executed.
- Skills cite the vector library (`V<n>`) rather than restate vector descriptions — the vector library is canonical.
- Skills cite real comparator implementations (`anchor-lang/...:LINE`, `spl-token-2022/...:LINE`) for the `comparator_citation` FINDING field per shared-rules.md § Comparator-claim discipline.
- Skills MUST NOT reference external auditing skills or projects by name. Argus is its own discipline; ported ideas are restated as Argus's own.
