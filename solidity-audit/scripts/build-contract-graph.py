#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


CONTRACT_RE = re.compile(r"\b(?:abstract\s+)?contract\s+([A-Za-z_][A-Za-z0-9_]*)")
INTERFACE_RE = re.compile(r"\binterface\s+([A-Za-z_][A-Za-z0-9_]*)")
LIBRARY_RE = re.compile(r"\blibrary\s+([A-Za-z_][A-Za-z0-9_]*)")
IMPORT_RE = re.compile(r'import\s+(?:[^;]*?\s+from\s+)?["\']([^"\']+\.sol)["\']\s*;')
INHERIT_RE = re.compile(
    r"\b(?:abstract\s+)?contract\s+[A-Za-z_][A-Za-z0-9_]*\s+is\s+([^{]+)\{",
    re.MULTILINE,
)


def read_paths(argv):
    if argv:
        return [Path(p) for p in argv]
    return [Path(line.strip()) for line in sys.stdin if line.strip()]


def parse_file(path: Path):
    text = path.read_text(encoding="utf-8", errors="ignore")
    declared = CONTRACT_RE.findall(text)
    interfaces = INTERFACE_RE.findall(text)
    libraries = LIBRARY_RE.findall(text)
    imports = IMPORT_RE.findall(text)
    inherits = []
    for group in INHERIT_RE.findall(text):
        inherits.extend(
            item.strip().split(" ")[0]
            for item in group.split(",")
            if item.strip()
        )
    return {
        "path": str(path),
        "declared_contracts": declared,
        "declared_interfaces": interfaces,
        "declared_libraries": libraries,
        "imports": imports,
        "inherits": inherits,
        "text": text,
    }


def main():
    paths = [p for p in read_paths(sys.argv[1:]) if p.exists() and p.suffix == ".sol"]
    parsed = [parse_file(path) for path in paths]

    known_names = set()
    for item in parsed:
        known_names.update(item["declared_contracts"])
        known_names.update(item["declared_interfaces"])
        known_names.update(item["declared_libraries"])

    output_contracts = []
    for item in parsed:
        text = item.pop("text")
        referenced = []
        for name in sorted(known_names):
            if name in item["declared_contracts"]:
                continue
            if re.search(rf"\b{name}\b", text):
                referenced.append(name)
        neighbors = sorted(set(item["inherits"] + referenced))
        output_contracts.append(
            {
                **item,
                "references": referenced,
                "neighbors": neighbors,
            }
        )

    json.dump({"contracts": output_contracts}, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
