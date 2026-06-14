---
name: cyfrin-audit-reports
description: Reference to Cyfrin's public audit report archive (Cyfrin/cyfrin-audit-reports) — real published smart-contract audit reports with findings, severities, and remediations. Points to the GitHub repo (large, not vendored) and explains how to mine it for prior art and report structure. Use when the user wants Cyfrin-style report models, real findings for a protocol type, or severity calibration examples.
---

# Cyfrin Audit Reports (reference)

Cyfrin's archive of published audit reports. Repo: https://github.com/Cyfrin/cyfrin-audit-reports (~56MB — fetch on demand rather than vendoring).

## How to use

1. Browse the repo's report list for a protocol/date close to the target.
2. Fetch the specific report (PDF/markdown) via `webfetch` or raw GitHub URL when needed.
3. Use it for finding-format mirroring, severity rationale, and prior-art checks.

Pair with `reference/audit-report-examples` (includes a Cyfrin sample locally), `claudit/solodit`, and `context-skills/gdocs-audit-report` for producing your own report.
