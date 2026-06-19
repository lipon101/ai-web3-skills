#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def score(finding):
    return int(finding.get("confidence", 0))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+")
    args = parser.parse_args()

    findings_by_key = {}
    module_conclusions = []

    for raw in args.inputs:
        path = Path(raw)
        if not path.exists():
            continue
        payload = load_json(path)
        for finding in payload.get("findings", []) + payload.get("final_findings", []):
            key = finding.get("root_cause_key") or finding.get("title")
            current = findings_by_key.get(key)
            if current is None or score(finding) > score(current):
                findings_by_key[key] = finding
        if "summary" in payload:
            module_conclusions.append(payload)
        module_conclusions.extend(payload.get("module_conclusions", []))

    final_findings = sorted(findings_by_key.values(), key=score, reverse=True)
    json.dump(
        {
            "final_findings": final_findings,
            "module_conclusions": module_conclusions,
        },
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
