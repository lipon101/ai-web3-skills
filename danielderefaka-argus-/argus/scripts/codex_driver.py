#!/usr/bin/env python3
"""
Argus Codex runtime driver (NEW v0.5.0).

Provides command-line shims for the four Claude-Code-only tools that Argus's
orchestrator references throughout the pipeline:

    AskUserQuestion    → ask         — write Q to a file, wait for the answer file
    TodoWrite          → todo        — append / update $RUN_DIR/_todos.md
    WebFetch / Search  → fetch       — best-effort via system tools (curl), else record
    Task (subagent)    → no-op       — Codex either has native parallel agents OR
                                       the orchestrator falls back to sequential

The driver is invoked from Bash by the orchestrator when running under Codex CLI.
It is platform-aware: if invoked under Claude Code (where the native tools exist),
it prints a notice and exits — you do not need this driver there.

Usage:
    python3 codex_driver.py detect-platform
    python3 codex_driver.py ask --run-dir <dir> --question "..." --options "A,B,C"
    python3 codex_driver.py todo --run-dir <dir> --add "research entry points"
    python3 codex_driver.py todo --run-dir <dir> --start "research entry points"
    python3 codex_driver.py todo --run-dir <dir> --done "research entry points"
    python3 codex_driver.py todo --run-dir <dir> --list
    python3 codex_driver.py fetch --run-dir <dir> --url "https://..." --out body.html
    python3 codex_driver.py manifest --run-dir <dir> --start-stage 1 --name protocol-map
    python3 codex_driver.py manifest --run-dir <dir> --end-stage 1 --status completed
    python3 codex_driver.py manifest --run-dir <dir> --read

Exit codes:
    0  — success / answer available / file written
    1  — pending (e.g. `ask` returned but no answer yet)
    2  — invocation error
    3  — platform mismatch (running under Claude, driver not needed)

Per `references/checkpoint-protocol.md`, this driver is also the writer for the
per-run manifest at $RUN_DIR/_manifest.json — orchestrators on EITHER platform
can use the `manifest` subcommand to maintain checkpoints.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


# ─── Platform detection ──────────────────────────────────────────────────────

def detect_platform() -> str:
    """Return 'claude' | 'codex' | 'unknown' based on env markers."""
    if os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("CLAUDECODE"):
        return "claude"
    if os.environ.get("CODEX_HOME") or os.environ.get("CODEX_AGENT"):
        return "codex"
    return "unknown"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json_atomic(path: Path, data: dict) -> None:
    """Write JSON via the write-rename atomicity pattern."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.parent.mkdir(parents=True, exist_ok=True)
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


# ─── ask — AskUserQuestion equivalent ────────────────────────────────────────
# Protocol:
#   1. Write question + numbered options to $RUN_DIR/_pending_question.md
#   2. Print the question + options to stdout for the user to see
#   3. Wait (poll) for $RUN_DIR/_pending_answer.md to appear
#   4. Read the answer (first non-empty, non-comment line)
#   5. Delete both files; print the answer to stdout
#
# When called with --no-wait, the driver exits immediately after step 2 with
# code 1 (pending). The orchestrator (or user) writes the answer file later;
# a subsequent `ask --collect` reads it.

def cmd_ask(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    q_path = run_dir / "_pending_question.md"
    a_path = run_dir / "_pending_answer.md"

    if args.collect:
        # Read existing answer file if present
        if not a_path.exists():
            print("no answer file yet", file=sys.stderr)
            return 1
        answer = a_path.read_text().strip().split("\n")
        answer = next((ln for ln in answer if ln.strip() and not ln.startswith("#")), "")
        print(answer)
        q_path.unlink(missing_ok=True)
        a_path.unlink(missing_ok=True)
        return 0

    # Write the question
    options = [o.strip() for o in (args.options or "").split(",") if o.strip()]
    lines = [f"# Argus question — {now_iso()}", "", args.question, ""]
    for i, opt in enumerate(options):
        lines.append(f"  [{chr(ord('A') + i)}] {opt}")
    lines.append("")
    lines.append("---")
    lines.append("Write your choice (the letter or the full text) to `_pending_answer.md` in this directory.")
    q_path.write_text("\n".join(lines) + "\n")

    # Print to stdout so the user/orchestrator sees it
    print("\n".join(lines))
    print()
    print(f"[Argus] Waiting for {a_path}", file=sys.stderr)

    if args.no_wait:
        return 1

    # Poll for the answer file
    deadline = time.monotonic() + (args.timeout or 1800)  # 30-minute default
    while time.monotonic() < deadline:
        if a_path.exists():
            answer = a_path.read_text().strip().split("\n")
            answer = next((ln for ln in answer if ln.strip() and not ln.startswith("#")), "")
            print(answer)
            q_path.unlink(missing_ok=True)
            a_path.unlink(missing_ok=True)
            return 0
        time.sleep(2)
    print("timeout waiting for answer", file=sys.stderr)
    return 1


# ─── todo — TodoWrite equivalent ─────────────────────────────────────────────
# Protocol:
#   $RUN_DIR/_todos.md is a GFM markdown checklist.
#   `--add "<text>"` appends `- [ ] <text>` (or no-ops if already present).
#   `--start "<text>"` marks the matching item as `- [ ] <text> ← in progress`.
#   `--done "<text>"` marks the matching item as `- [x] <text>`.
#   `--list` prints the file.

def _read_todos(path: Path) -> list[str]:
    return path.read_text().splitlines() if path.exists() else []


def _write_todos(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + ("\n" if lines and not lines[-1].endswith("\n") else ""))


def _todo_match(line: str, text: str) -> bool:
    return text in line


def cmd_todo(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    path = run_dir / "_todos.md"
    lines = _read_todos(path)

    if args.list:
        for ln in lines:
            print(ln)
        return 0

    if args.add:
        text = args.add
        if any(_todo_match(ln, text) for ln in lines):
            print(f"todo already present: {text}", file=sys.stderr)
            return 0
        lines.append(f"- [ ] {text}")
        _write_todos(path, lines)
        return 0

    if args.start:
        text = args.start
        # Demote any existing "in progress" markers
        for i, ln in enumerate(lines):
            lines[i] = ln.replace(" ← in progress", "")
        found = False
        for i, ln in enumerate(lines):
            if _todo_match(ln, text):
                if "[x]" in ln:
                    continue  # already done; don't re-start
                if "← in progress" not in ln:
                    lines[i] = ln.rstrip() + " ← in progress"
                found = True
                break
        if not found:
            lines.append(f"- [ ] {text} ← in progress")
        _write_todos(path, lines)
        return 0

    if args.done:
        text = args.done
        found = False
        for i, ln in enumerate(lines):
            if _todo_match(ln, text):
                lines[i] = ln.replace("[ ]", "[x]").replace(" ← in progress", "")
                found = True
                break
        if not found:
            lines.append(f"- [x] {text}")
        _write_todos(path, lines)
        return 0

    print("todo subcommand requires --add | --start | --done | --list", file=sys.stderr)
    return 2


# ─── fetch — WebFetch / WebSearch equivalent ─────────────────────────────────
# Protocol:
#   Try `curl` first (universally available). Cache the response in
#   $RUN_DIR/_fetch_cache/<sha1-of-url>.html. On failure, record the URL in
#   $RUN_DIR/_unfetched_urls.txt for the orchestrator to surface as missing
#   context.

def cmd_fetch(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    cache_dir = run_dir / "_fetch_cache"
    cache_dir.mkdir(exist_ok=True)

    import hashlib
    h = hashlib.sha1(args.url.encode()).hexdigest()[:16]
    cached = cache_dir / f"{h}.html"
    out = Path(args.out) if args.out else cached

    if cached.exists() and not args.no_cache:
        out.write_bytes(cached.read_bytes())
        print(f"cached: {out}", file=sys.stderr)
        return 0

    # Try curl
    try:
        r = subprocess.run(
            ["curl", "-fsSL", "--max-time", "30", "-A", "argus/0.5.0", args.url],
            capture_output=True, check=True,
        )
        cached.write_bytes(r.stdout)
        if out != cached:
            out.write_bytes(r.stdout)
        print(f"fetched: {out}", file=sys.stderr)
        return 0
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        unfetched = run_dir / "_unfetched_urls.txt"
        with open(unfetched, "a") as fh:
            fh.write(f"{now_iso()}\t{args.url}\t{type(e).__name__}\n")
        print(f"fetch failed: {args.url} ({type(e).__name__}). URL recorded at {unfetched}", file=sys.stderr)
        return 1


# ─── manifest — checkpoint-protocol writer / reader ──────────────────────────

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


def _load_manifest(run_dir: Path) -> dict:
    path = run_dir / "_manifest.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def _bootstrap_manifest(run_dir: Path, platform: str, mode: str, depth_tier: str) -> dict:
    return {
        "argus_version": _read_version(),
        "run_id": str(uuid.uuid4()),
        "run_dir": str(run_dir),
        "started_utc": now_iso(),
        "platform": platform,
        "mode": mode,
        "depth_tier": depth_tier,
        "target": {"project_root": "", "git_commit": "", "bounty_url": None},
        "stages": [],
        "current_stage": 0,
        "last_completed_stage": -1,
        "resume_hint": "",
    }


def _read_version() -> str:
    """Find VERSION file by walking up from this script."""
    p = Path(__file__).resolve().parent
    for _ in range(5):
        v = p / "VERSION"
        if v.exists():
            return v.read_text().strip()
        p = p.parent
    return "unknown"


def cmd_manifest(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    path = run_dir / "_manifest.json"
    manifest = _load_manifest(run_dir)

    if args.read:
        if not manifest:
            print("{}", file=sys.stderr)
            return 1
        print(json.dumps(manifest, indent=2))
        return 0

    if args.init:
        if manifest:
            print(f"manifest already exists at {path}", file=sys.stderr)
            return 2
        manifest = _bootstrap_manifest(
            run_dir,
            platform=args.platform or detect_platform(),
            mode=args.mode or "smart-contract",
            depth_tier=args.depth_tier or "core",
        )
        if args.project_root:
            manifest["target"]["project_root"] = args.project_root
        if args.git_commit:
            manifest["target"]["git_commit"] = args.git_commit
        if args.bounty_url:
            manifest["target"]["bounty_url"] = args.bounty_url
        write_json_atomic(path, manifest)
        print(manifest["run_id"])
        return 0

    if not manifest:
        print(f"no manifest at {path} — run --init first", file=sys.stderr)
        return 2

    if args.start_stage is not None:
        stage = args.start_stage
        name = args.name or STAGE_NAMES.get(stage, f"stage-{stage}")
        entry = {
            "stage": stage,
            "name": name,
            "status": "in-progress",
            "started_utc": now_iso(),
            "ended_utc": None,
            "output_path": f"{stage}-{name}/" if name else f"{stage}/",
            "output_files": [],
            "tokens_in_estimated": args.tokens_in_est or 0,
            "tokens_out_estimated": args.tokens_out_est or 0,
            "tokens_in_actual": None,
            "tokens_out_actual": None,
            "model_mix": {},
            "notes": [],
        }
        manifest["stages"].append(entry)
        manifest["current_stage"] = stage
        write_json_atomic(path, manifest)
        return 0

    if args.end_stage is not None:
        stage = args.end_stage
        status = args.status or "completed"
        # Find the most recent in-progress entry for this stage
        for entry in reversed(manifest["stages"]):
            if entry["stage"] == stage and entry["status"] == "in-progress":
                entry["status"] = status
                entry["ended_utc"] = now_iso()
                if args.output_files:
                    entry["output_files"] = [f.strip() for f in args.output_files.split(",") if f.strip()]
                if args.note:
                    entry["notes"].append(args.note)
                if args.tokens_in_actual is not None:
                    entry["tokens_in_actual"] = args.tokens_in_actual
                if args.tokens_out_actual is not None:
                    entry["tokens_out_actual"] = args.tokens_out_actual
                if status == "completed":
                    manifest["last_completed_stage"] = max(manifest["last_completed_stage"], stage)
                    manifest["current_stage"] = stage + 1
                write_json_atomic(path, manifest)
                return 0
        print(f"no in-progress entry found for stage {stage}", file=sys.stderr)
        return 2

    if args.resume_hint is not None:
        manifest["resume_hint"] = args.resume_hint
        write_json_atomic(path, manifest)
        return 0

    print("manifest subcommand requires --init | --read | --start-stage | --end-stage | --resume-hint", file=sys.stderr)
    return 2


# ─── detect-platform ─────────────────────────────────────────────────────────

def cmd_detect_platform(args: argparse.Namespace) -> int:
    print(detect_platform())
    return 0


# ─── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("detect-platform", help="Print 'claude' | 'codex' | 'unknown'")
    sp.set_defaults(func=cmd_detect_platform)

    sp = sub.add_parser("ask", help="AskUserQuestion shim — write Q, wait for answer")
    sp.add_argument("--run-dir", required=True)
    sp.add_argument("--question", help="The question prose")
    sp.add_argument("--options", help="Comma-separated options")
    sp.add_argument("--no-wait", action="store_true", help="Write Q and exit; user/orchestrator collects later")
    sp.add_argument("--collect", action="store_true", help="Read the answer file if present")
    sp.add_argument("--timeout", type=int, help="Seconds to wait for answer (default 1800)")
    sp.set_defaults(func=cmd_ask)

    sp = sub.add_parser("todo", help="TodoWrite shim — markdown checklist at $RUN_DIR/_todos.md")
    sp.add_argument("--run-dir", required=True)
    sp.add_argument("--add", help="Append a pending todo")
    sp.add_argument("--start", help="Mark the matching todo as in progress")
    sp.add_argument("--done", help="Mark the matching todo as completed")
    sp.add_argument("--list", action="store_true", help="Print the todo file")
    sp.set_defaults(func=cmd_todo)

    sp = sub.add_parser("fetch", help="WebFetch shim — curl + cache")
    sp.add_argument("--run-dir", required=True)
    sp.add_argument("--url", required=True)
    sp.add_argument("--out", help="Output file (defaults to cache path)")
    sp.add_argument("--no-cache", action="store_true", help="Bypass cache; force re-fetch")
    sp.set_defaults(func=cmd_fetch)

    sp = sub.add_parser("manifest", help="Checkpoint manifest reader/writer")
    sp.add_argument("--run-dir", required=True)
    sp.add_argument("--init", action="store_true", help="Bootstrap a new manifest")
    sp.add_argument("--read", action="store_true", help="Print the manifest JSON")
    sp.add_argument("--platform", choices=["claude", "codex"])
    sp.add_argument("--mode", choices=["smart-contract", "infra"])
    sp.add_argument("--depth-tier", choices=["light", "core", "thorough"])
    sp.add_argument("--project-root")
    sp.add_argument("--git-commit")
    sp.add_argument("--bounty-url")
    sp.add_argument("--start-stage", type=int)
    sp.add_argument("--end-stage", type=int)
    sp.add_argument("--name", help="Stage name (used with --start-stage)")
    sp.add_argument("--status", choices=["completed", "failed", "skipped"])
    sp.add_argument("--output-files", help="Comma-separated file list (used with --end-stage)")
    sp.add_argument("--note", help="Free-text note appended to the stage entry")
    sp.add_argument("--tokens-in-est", type=int)
    sp.add_argument("--tokens-out-est", type=int)
    sp.add_argument("--tokens-in-actual", type=int)
    sp.add_argument("--tokens-out-actual", type=int)
    sp.add_argument("--resume-hint", help="Set the resume_hint field")
    sp.set_defaults(func=cmd_manifest)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
