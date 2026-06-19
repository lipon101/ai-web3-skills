---
description: "Argus resume — read $RUN_DIR/_manifest.json and pick up an interrupted run at the last checkpoint. Usage: /argus-resume <run-dir>"
---

Read the checkpoint manifest and present a resume plan.

Steps:

1. Invoke `python3 ~/.claude/skills/argus/scripts/argus_resume.py $ARGUMENTS` and capture the output.
2. Show the user the rendered plan (the human-readable block). Highlight:
   - Which stages completed (✓ rows).
   - The "Resume point" — which stage to start from + the reason.
   - Any validation issues (these block resume unless the user explicitly chooses to repair or proceed-anyway).
3. If validation issues exist, ask via `AskUserQuestion`:
   - [A] Proceed anyway (ignore inconsistencies — risky)
   - [B] Re-run the failed/in-progress stage from scratch
   - [C] Abort and start a fresh `$RUN_DIR`
4. If no issues, ask:
   - [A] Resume from Stage N (the resume_point)
   - [B] Re-run from Stage N (discard partial Stage-N work)
   - [C] Abort
5. Based on the user's choice, load `SKILL.md` and continue at the indicated stage. The orchestrator MUST:
   - Read the prior stage's outputs (the files listed in completed stages' `output_files`) before proceeding — Stage N has dependencies on Stage N-1's outputs.
   - For Stage 2 partial-completion: skip already-completed angles (read `_partial.json`).
   - For Stages 3-8 per-finding: skip findings that already have a verdict file in this stage's directory.
   - Maintain the manifest via `python3 .../scripts/codex_driver.py manifest --run-dir <dir> --start-stage <N>` / `--end-stage <N>` calls.

Arguments: $ARGUMENTS  (the absolute path to an existing `$RUN_DIR` containing `_manifest.json`)
