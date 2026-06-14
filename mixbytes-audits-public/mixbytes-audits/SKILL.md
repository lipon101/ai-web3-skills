---
name: mixbytes-audits
description: Reference to MixBytes' public audit report archive (mixbytes/audits_public) — a large corpus of real smart-contract audit reports across many DeFi protocols. Too large to vendor locally, so this skill points to the GitHub repo and explains how to mine it for finding write-ups, severity calibration, and protocol-specific prior art. Use when the user wants real-world audit examples, prior findings for a protocol type, or report-writing models from a top firm.
---

# MixBytes Public Audits (reference)

A large public archive of MixBytes audit reports. Repo: https://github.com/mixbytes/audits_public (~300MB — not copied into the workspace).

## How to use

When you need prior art or report models:
1. Browse the repo by protocol/date to find a relevant report.
2. Fetch the specific report markdown/PDF with `webfetch` or the GitHub raw URL on demand (don't bulk-clone — it's huge).
3. Use it to calibrate severity, mirror finding structure, and check whether a candidate bug matches a known class.

Pair with `claudit/solodit` (cross-firm search), `reference/audit-report-examples` (local samples), and `grimoire/finding-draft` for writing your own.
