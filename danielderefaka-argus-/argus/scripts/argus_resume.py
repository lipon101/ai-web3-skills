#!/usr/bin/env python3
"""
Argus resume helper (NEW v0.5.0).

Reads `$RUN_DIR/_manifest.json` and reports the resume plan:

    - Which stages completed (and their token costs, if available).
    - Which stage is in-progress or failed (and the resume hint).
    - Which sub-tasks remain inside that stage (Stage 2 partial, Stage 3-8 per-finding).
    - Whether the manifest is well-formed and consistent with disk state.

The orchestrator invokes this at the start of a run when `$RUN_DIR/_manifest.json`
already exists. The user can choose to resume (continue from the next stage) or
to start a new run dir.

Usage:
    python3 argus_resume.py <run-dir>
    python3 argus_resume.py <run-dir> --validate
    python3 argus_resume.py <run-dir> --json                  # machine-readable report

Exit codes:
    0 — resume plan ready; safe to proceed from `next_stage`
    1 — manifest indicates the run already completed all stages (nothing to resume)
    2 — manifest missing, malformed, or inconsistent with disk
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime


STAGE_NAMES = {
    0: "cost-preview",
    1: "protocol-map",
    2: "candidate-findings",
    3: "verification",
    4: "impact",
    5: "platform-validation",
    6: "program-triage",
    7: "duplication",
    8: "output",
}


def load_manifest(run_dir: Path) -> dict:
    path = run_dir / "_manifest.json"
    if not path.exists():
        raise FileNotFoundError(f"manifest not found at {path}")
    return json.loads(path.read_text())


def validate(manifest: dict, run_dir: Path) -> list[str]:
    """Return a list of validation issues. Empty list = manifest is well-formed."""
    issues: list[str] = []

    required_top = ["argus_version", "run_id", "platform", "mode", "depth_tier", "stages", "current_stage", "last_completed_stage"]
    for k in required_top:
        if k not in manifest:
            issues.append(f"missing top-level key: {k}")

    stages = manifest.get("stages", [])
    if not isinstance(stages, list):
        issues.append("stages is not a list")
        return issues

    last_ts = None
    for i, entry in enumerate(stages):
        for k in ["stage", "name", "status", "started_utc", "output_path"]:
            if k not in entry:
                issues.append(f"stage[{i}] missing key: {k}")
                continue
        # Chronological ordering
        t = entry.get("started_utc")
        if t and last_ts and t < last_ts:
            issues.append(f"stage[{i}] started_utc {t} precedes prior {last_ts}")
        last_ts = t or last_ts
        # Check output files actually exist for completed stages
        if entry.get("status") == "completed":
            for f in entry.get("output_files", []):
                full = run_dir / entry["output_path"] / f
                if not full.exists():
                    issues.append(f"stage[{i}] ({entry['name']}) claims completed but missing file: {full}")

    # last_completed_stage matches data
    completed_stages = [e["stage"] for e in stages if e.get("status") == "completed"]
    actual_lcs = max(completed_stages, default=-1)
    declared_lcs = manifest.get("last_completed_stage", -1)
    if declared_lcs != actual_lcs:
        issues.append(f"last_completed_stage={declared_lcs} but actual max completed={actual_lcs}")

    # No two `completed` entries for same stage
    seen_completed = set()
    for entry in stages:
        if entry.get("status") == "completed":
            s = entry["stage"]
            if s in seen_completed:
                issues.append(f"stage {s} has multiple completed entries")
            seen_completed.add(s)

    return issues


def partial_completion_info(run_dir: Path, stage: int) -> dict:
    """Return per-stage partial-completion info read from disk."""
    info: dict = {"stage": stage, "type": None, "detail": {}}

    if stage == 2:
        partial = run_dir / "2-candidate-findings" / "_partial.json"
        if partial.exists():
            info["type"] = "stage-2-parallel-angles"
            info["detail"] = json.loads(partial.read_text())
        return info

    if 3 <= stage <= 8:
        # Scan per-finding verdict files
        stage_dirs = {
            3: "3-verification",
            4: "4-impact",
            5: "5-platform",
            6: "6-program-triage",
            7: "7-duplication",
            8: "8-output",
        }
        sd = run_dir / stage_dirs.get(stage, f"{stage}-?")
        if not sd.exists():
            return info
        verdicts = list(sd.glob("F-*/verdict.md"))
        # Also enumerate findings from Stage 2
        findings_dir = run_dir / "2-candidate-findings"
        all_findings = [p.stem for p in findings_dir.glob("F-*.md")] if findings_dir.exists() else []
        completed_in_stage = sorted(p.parent.name for p in verdicts)
        remaining = [f for f in all_findings if f not in completed_in_stage]
        info["type"] = f"stage-{stage}-per-finding"
        info["detail"] = {
            "completed": completed_in_stage,
            "remaining": remaining,
            "total_findings": len(all_findings),
        }
        return info

    return info


def build_resume_plan(manifest: dict, run_dir: Path) -> dict:
    """Construct the resume plan dict."""
    stages = manifest.get("stages", [])
    last_completed = manifest.get("last_completed_stage", -1)
    current = manifest.get("current_stage", 0)
    issues = validate(manifest, run_dir)

    # Determine next stage to run
    if last_completed >= 8:
        next_stage = None
        status = "completed"
    else:
        next_stage = last_completed + 1
        status = "resumable"

    # If current_stage has an in-progress or failed entry, that's the resume point
    in_progress = [e for e in stages if e["status"] == "in-progress"]
    failed = [e for e in stages if e["status"] == "failed"]

    if in_progress:
        ip = in_progress[-1]
        partial = partial_completion_info(run_dir, ip["stage"])
        resume_point = {
            "stage": ip["stage"],
            "name": ip["name"],
            "reason": "in-progress at last manifest write",
            "started_utc": ip["started_utc"],
            "partial_completion": partial,
        }
    elif failed and failed[-1]["stage"] >= last_completed:
        f = failed[-1]
        resume_point = {
            "stage": f["stage"],
            "name": f["name"],
            "reason": f"failed: {f.get('notes', ['(no reason)'])[-1] if f.get('notes') else 'no reason recorded'}",
            "started_utc": f["started_utc"],
            "partial_completion": partial_completion_info(run_dir, f["stage"]),
        }
    elif next_stage is not None:
        resume_point = {
            "stage": next_stage,
            "name": STAGE_NAMES.get(next_stage, f"stage-{next_stage}"),
            "reason": "next stage after last completed",
            "started_utc": None,
            "partial_completion": None,
        }
    else:
        resume_point = None

    # Token totals
    actual_in = sum(s.get("tokens_in_actual") or 0 for s in stages)
    actual_out = sum(s.get("tokens_out_actual") or 0 for s in stages)
    est_in = sum(s.get("tokens_in_estimated") or 0 for s in stages)
    est_out = sum(s.get("tokens_out_estimated") or 0 for s in stages)

    return {
        "run_id": manifest.get("run_id"),
        "argus_version": manifest.get("argus_version"),
        "platform": manifest.get("platform"),
        "mode": manifest.get("mode"),
        "depth_tier": manifest.get("depth_tier"),
        "target": manifest.get("target", {}),
        "started_utc": manifest.get("started_utc"),
        "completed_stages": [
            {
                "stage": s["stage"],
                "name": s["name"],
                "ended_utc": s.get("ended_utc"),
                "tokens_in_actual": s.get("tokens_in_actual"),
                "tokens_out_actual": s.get("tokens_out_actual"),
            }
            for s in stages
            if s["status"] == "completed"
        ],
        "last_completed_stage": last_completed,
        "next_stage": next_stage,
        "status": status,
        "resume_point": resume_point,
        "validation_issues": issues,
        "tokens": {
            "estimated_total": est_in + est_out,
            "actual_total": actual_in + actual_out,
            "estimated_in": est_in,
            "estimated_out": est_out,
            "actual_in": actual_in,
            "actual_out": actual_out,
        },
    }


def render_plan(plan: dict) -> str:
    """Human-readable resume plan."""
    lines = []
    lines.append("═" * 65)
    lines.append("Argus — Resume Plan")
    lines.append("═" * 65)
    lines.append("")
    lines.append(f"  Run ID:           {plan['run_id']}")
    lines.append(f"  Argus version:    {plan['argus_version']}")
    lines.append(f"  Platform:         {plan['platform']}")
    lines.append(f"  Mode / Tier:      {plan['mode']} / {plan['depth_tier']}")
    lines.append(f"  Started:          {plan['started_utc']}")
    lines.append(f"  Project root:     {plan['target'].get('project_root', '?')}")
    lines.append("")
    lines.append("─" * 65)
    lines.append("Completed stages")
    lines.append("─" * 65)
    if not plan["completed_stages"]:
        lines.append("  (none — run hasn't completed any stages yet)")
    else:
        for s in plan["completed_stages"]:
            tok = (s["tokens_in_actual"] or 0) + (s["tokens_out_actual"] or 0)
            lines.append(f"  ✓ Stage {s['stage']}: {s['name']:<25} {s['ended_utc'] or '?':<32} tokens: {tok:>10,}")
    lines.append("")
    lines.append("─" * 65)
    lines.append("Resume point")
    lines.append("─" * 65)
    rp = plan["resume_point"]
    if not rp:
        lines.append(f"  Status: {plan['status']} — nothing left to do")
    else:
        lines.append(f"  Next: Stage {rp['stage']} — {rp['name']}")
        lines.append(f"  Reason: {rp['reason']}")
        if rp.get("partial_completion") and rp["partial_completion"].get("type"):
            pc = rp["partial_completion"]
            lines.append(f"  Partial-completion: {pc['type']}")
            if pc["type"] == "stage-2-parallel-angles":
                d = pc["detail"]
                lines.append(f"    Completed angles: {d.get('angles_completed', [])}")
                lines.append(f"    Pending angles:   {d.get('angles_pending', [])}")
            elif pc["type"].startswith("stage-"):
                d = pc["detail"]
                lines.append(f"    Completed findings: {len(d.get('completed', []))}/{d.get('total_findings', 0)}")
                if d.get("remaining"):
                    lines.append(f"    Remaining: {', '.join(d['remaining'][:10])}{'…' if len(d['remaining']) > 10 else ''}")
    lines.append("")
    lines.append("─" * 65)
    lines.append("Tokens")
    lines.append("─" * 65)
    t = plan["tokens"]
    lines.append(f"  Estimated total: {t['estimated_total']:>12,}")
    lines.append(f"  Actual so far:   {t['actual_total']:>12,}")
    if t["estimated_total"] and t["actual_total"]:
        pct = t["actual_total"] / t["estimated_total"] * 100
        lines.append(f"  Burn rate:       {pct:>11.1f}%")
    lines.append("")
    if plan["validation_issues"]:
        lines.append("─" * 65)
        lines.append("Validation issues")
        lines.append("─" * 65)
        for issue in plan["validation_issues"]:
            lines.append(f"  ! {issue}")
        lines.append("")
    lines.append("═" * 65)
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir", help="Path to an Argus run directory (has _manifest.json)")
    ap.add_argument("--validate", action="store_true", help="Only validate; don't print resume plan")
    ap.add_argument("--json", action="store_true", help="Machine-readable output")
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    try:
        manifest = load_manifest(run_dir)
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as e:
        print(f"ERROR: manifest is not valid JSON: {e}", file=sys.stderr)
        return 2

    plan = build_resume_plan(manifest, run_dir)

    if args.validate:
        if plan["validation_issues"]:
            for issue in plan["validation_issues"]:
                print(issue, file=sys.stderr)
            return 2
        print("manifest valid", file=sys.stderr)
        return 0

    if args.json:
        print(json.dumps(plan, indent=2))
    else:
        print(render_plan(plan))

    if plan["status"] == "completed":
        return 1
    if plan["validation_issues"]:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
