---
description: "Argus install verification — checks skill is wired in correctly, reference files present, helper scripts executable, Python syntactically clean. Usage: /argus-doctor (optional: --check-rust to probe infra-mode toolchain)"
---

Run the install-verification script and report results.

Invoke:
```bash
bash ~/.claude/skills/argus/scripts/doctor.sh $ARGUMENTS
```

Show the user the full output. If FAIL count > 0, surface the failures first and recommend `bash ~/.claude/skills/argus/install.sh` to repair. If only WARN count > 0, list warnings briefly and proceed.

Arguments: $ARGUMENTS  (typical: empty for smoke check, or `--check-rust` for full infra readiness probe)
