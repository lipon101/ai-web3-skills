#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def render_source_section(path: Path) -> str:
    return f"## Source: {path}\n\n```solidity\n{read_text(path).rstrip()}\n```\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tasks-json", required=True)
    parser.add_argument("--references-root", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    tasks = json.loads(Path(args.tasks_json).read_text(encoding="utf-8"))
    references_root = Path(args.references_root)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    for task in tasks:
        parts = [
            f"# Audit Bundle: {task['target_contract']} x {task['label']}",
            f"- module_id: {task['module_id']}",
        ]
        for source in task["contracts"]:
            parts.append(render_source_section(Path(source)))
        for common_ref in task.get("common_references", []):
            ref_path = references_root / "common" / common_ref
            parts.append(f"## Reference: {common_ref}\n\n{read_text(ref_path)}")
        protocol_ref = task.get("protocol_reference")
        if protocol_ref:
            ref_path = references_root / "protocols" / protocol_ref
            parts.append(f"## Protocol Reference: {protocol_ref}\n\n{read_text(ref_path)}")
        judging = references_root / "workflow" / "judging.md"
        parts.append(f"## Validation Reference\n\n{read_text(judging)}")
        out_path = output_dir / f"{task['module_id']}--{task['target_contract']}--{task['label']}.md"
        out_path.write_text("\n\n".join(parts) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
