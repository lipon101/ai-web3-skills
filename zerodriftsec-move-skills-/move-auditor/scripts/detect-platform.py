#!/usr/bin/env python3
"""Detect whether a Move project targets Sui or Aptos by scanning Move.toml files."""

import argparse
import sys
from pathlib import Path


def detect_platform(project_dir: str) -> str:
    for toml_path in Path(project_dir).rglob("Move.toml"):
        content = toml_path.read_text(errors="ignore")
        if "MystenLabs/sui.git" in content:
            return "sui"
        if "aptos-labs/aptos-core.git" in content:
            return "aptos"
        if "initia-labs/move-natives.git" in content:
            return "aptos"
    return "sui"


def main() -> None:
    parser = argparse.ArgumentParser(description="Detect Move project platform (sui / aptos)")
    parser.add_argument("path", nargs="?", default=".", help="Project root directory")
    args = parser.parse_args()

    result = detect_platform(args.path)
    if not result:
        print("ERROR: Could not detect platform. No Sui or Aptos indicators found.", file=sys.stderr)
        sys.exit(1)
    print(result)


if __name__ == "__main__":
    main()
