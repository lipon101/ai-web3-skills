---
name: ai-auditor-primers
description: Reusable "primer" prompts that load deep domain context into an AI auditor before it reviews a specific class of protocol (e.g. ERC-4626 vaults). Source from devdacian/ai-auditor-primers. Use when the user is about to audit a protocol of a known archetype and wants the agent primed with the relevant invariants, attack patterns, and accounting pitfalls first. Primer files are copied to documents/personal-ZUp1aMpW/audit-references/ai-auditor-primers.
---

# AI Auditor Primers (reference)

A small library of "primer" documents by devdacian that front-load an AI auditor with domain expertise for a protocol archetype before it audits a real codebase. Repo: https://github.com/devdacian/ai-auditor-primers

## Local copy

Primer files live at:
`documents/personal-ZUp1aMpW/audit-references/ai-auditor-primers/`

Includes:
- `base.primer.md` — general auditor primer / scaffold.
- `amy.vault.erc4626.primer.md` — ERC-4626 vault-specific primer (share/asset accounting, inflation/donation attacks, rounding direction, first-depositor issues).

## How to use

1. Before auditing a contract, identify its archetype (vault, lending, AMM, staking, etc.).
2. Read the matching primer (start from `base.primer.md`, then the specific one) and fold its checklist/invariants into the review.
3. Combine with `smart-contract-audit`, `solidity-auditor`, and the relevant Plamen chain skills (e.g. `plamen/injectable/vault-accounting`).
4. If no primer exists for the archetype, use `base.primer.md` as a template to draft one, and consider saving it back here.

This is prompt/context material, not an executable tool.
