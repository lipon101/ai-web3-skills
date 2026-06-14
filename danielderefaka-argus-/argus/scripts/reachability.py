#!/usr/bin/env python3
"""
Stage 4 reachability analyzer (infra mode).

Reads a rust-analyzer-derived call graph + an entry-points inventory + a target
function name, and emits a reachability verdict:
  Remote | Authenticated | Local | Test-only | unclear

Conservative over-approximation on dynamic dispatch (trait objects): if any
implementor of a trait is reachable from an entry point, the target is
considered reachable.

Usage:
    python3 reachability.py \
        --callgraph $RUN_DIR/1-protocol-map/callgraph.json \
        --target-function crate::serialize::write_header \
        --entry-points $RUN_DIR/1-protocol-map/entry-points.md \
        --component-type validator-client \
        --output $RUN_DIR/4-impact/F-NN.reachability.json

Call-graph JSON schema expected (compatible with `rust-analyzer analysis-stats
--output json` or a custom-extracted variant):
{
  "functions": {
    "crate::module::function_name": {
      "callers": ["crate::module::caller_a", "crate::module::caller_b"],
      "is_pub": true,
      "is_test_only": false,
      "attributes": ["rpc", "extern_c", ...]
    },
    ...
  },
  "trait_implementors": {
    "MyTrait": ["crate::ImplA", "crate::ImplB"]
  }
}

If `rust-analyzer` output isn't in this exact shape (it isn't, by default), the
Stage 1 protocol-mapping stage transforms its output into this schema before
this script runs. That transform is part of `enumerate.sh` (or a future
`callgraph-extract.sh`) — not in scope for this script.

Exit codes:
    0 — verdict written; reachability resolved
    1 — verdict written; reachability=unclear (callgraph incomplete)
    2 — invocation error (missing args, bad files)
"""

import argparse
import json
import re
import sys
from collections import deque
from pathlib import Path

# ─── Entry-point pattern classification ───────────────────────────────────────

# Patterns that mark a function as Remote-reachable
REMOTE_PATTERNS = [
    r"#\[rpc\]",
    r"#\[jsonrpsee::",
    r"#\[actix_web::",
    r"#\[tonic::",
    r"libp2p::NetworkBehaviour",
    r"on_message",
    r"handle_request",
    r"#\[no_mangle\].*extern",
    r"extern \"C\"",
]

# Patterns that mark a function as Authenticated-reachable
AUTHENTICATED_PATTERNS = [
    r"#\[require_auth\]",
    r"validator_only",
    r"trusted_peer_only",
    r"#\[admin\]",
    r"signed_extrinsic",
]

# Patterns that mark a function as Local-reachable
LOCAL_PATTERNS = [
    r"fn main\(",
    r"clap::Parser",
    r"std::env::args",
    r"read_config",
    r"load_keystore",
    r"#\[command\]",
]


def classify_entry_point(fn_name: str, attributes: list[str], source_excerpt: str | None) -> str | None:
    """Return one of 'remote' / 'authenticated' / 'local' or None if not an entry point."""
    text = " ".join(attributes) + " " + fn_name + " " + (source_excerpt or "")
    for pat in REMOTE_PATTERNS:
        if re.search(pat, text, re.IGNORECASE):
            return "remote"
    for pat in AUTHENTICATED_PATTERNS:
        if re.search(pat, text, re.IGNORECASE):
            return "authenticated"
    for pat in LOCAL_PATTERNS:
        if re.search(pat, text, re.IGNORECASE):
            return "local"
    return None


# ─── Entry-points.md parsing (Stage 1 output) ─────────────────────────────────


def parse_entry_points_md(path: Path) -> dict[str, str]:
    """
    Parse Stage 1's entry-points.md for explicit reachability annotations.
    Returns dict mapping function path -> reachability bucket override.

    Expected line format:
        - `crate::module::function` [REACHABILITY=remote]
        - `crate::module::other_fn` [REACHABILITY=authenticated]
    """
    overrides: dict[str, str] = {}
    if not path.exists():
        return overrides

    pat = re.compile(
        r"`([\w:]+)`\s*\[REACHABILITY=(remote|authenticated|local|test-only)\]",
        re.IGNORECASE,
    )
    for line in path.read_text().splitlines():
        m = pat.search(line)
        if m:
            overrides[m.group(1)] = m.group(2).lower()
    return overrides


# ─── Reverse-BFS over the call graph ──────────────────────────────────────────


def find_paths_to_target(
    callgraph: dict, target: str, max_depth: int = 20
) -> list[tuple[str, list[str], bool]]:
    """
    Reverse-BFS from target. Returns list of (entry_function, path, used_dynamic_dispatch)
    where `path` is [entry, ..., target] and `used_dynamic_dispatch` flags whether
    any hop required over-approximation on a trait-object boundary.
    """
    functions = callgraph.get("functions", {})
    if target not in functions:
        return []

    paths: list[tuple[str, list[str], bool]] = []
    # BFS state: (current_fn, path_so_far, dyn_dispatch_used)
    queue = deque([(target, [target], False)])
    visited: set[str] = {target}

    while queue:
        current, path, dyn_used = queue.popleft()
        if len(path) > max_depth:
            continue

        fn_info = functions.get(current, {})
        callers = list(fn_info.get("callers", []))

        # Dynamic-dispatch over-approximation: if `current` is a trait method
        # called via dyn dispatch, treat ALL implementors of the trait as
        # potential callers. This is recorded in dyn_used.
        for trait, implementors in callgraph.get("trait_implementors", {}).items():
            if current.endswith(f"::{trait.split('::')[-1]}"):
                for impl in implementors:
                    if impl not in callers:
                        callers.append(impl)
                        dyn_used = True

        if not callers:
            # No callers → this is an entry point candidate (or unreachable root)
            if fn_info.get("is_pub", False) or any(
                attr in fn_info.get("attributes", [])
                for attr in ("rpc", "extern_c", "actix_web", "tonic")
            ):
                paths.append((current, list(reversed(path)), dyn_used))
            continue

        for caller in callers:
            if caller in visited:
                continue
            visited.add(caller)
            queue.append((caller, path + [caller], dyn_used))

    return paths


# ─── Verdict assembly ─────────────────────────────────────────────────────────


def assign_reachability(
    paths: list[tuple[str, list[str], bool]],
    callgraph: dict,
    entry_overrides: dict[str, str],
) -> tuple[str, dict]:
    """
    Given the set of paths from entry points to target, pick the highest-severity
    reachability bucket.

    Priority: remote > authenticated > local > test-only > unclear
    """
    if not paths:
        return "unclear", {
            "reason": "no call paths found from any entry point",
            "paths_count": 0,
        }

    priority = {"remote": 4, "authenticated": 3, "local": 2, "test-only": 1, "unclear": 0}
    best_bucket = "unclear"
    best_path = None
    best_dyn = False
    test_only_only = True

    for entry_fn, path, dyn_used in paths:
        fn_info = callgraph.get("functions", {}).get(entry_fn, {})

        # Manual override from entry-points.md
        if entry_fn in entry_overrides:
            bucket = entry_overrides[entry_fn]
        elif fn_info.get("is_test_only", False):
            bucket = "test-only"
        else:
            cls = classify_entry_point(
                entry_fn,
                fn_info.get("attributes", []),
                fn_info.get("source_excerpt"),
            )
            bucket = cls if cls else "test-only"

        if bucket != "test-only":
            test_only_only = False

        if priority[bucket] > priority[best_bucket]:
            best_bucket = bucket
            best_path = path
            best_dyn = dyn_used

    # If every path is test-only, the verdict IS test-only (not unclear)
    if test_only_only and best_bucket == "unclear":
        best_bucket = "test-only"

    return best_bucket, {
        "entry_point": best_path[0] if best_path else None,
        "call_path": best_path,
        "dynamic_dispatch_overapproximation": best_dyn,
        "paths_count": len(paths),
    }


# ─── Main ─────────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--callgraph", required=True, type=Path, help="Path to callgraph.json")
    ap.add_argument("--target-function", required=True, help="Fully-qualified function name (crate::module::fn)")
    ap.add_argument("--entry-points", type=Path, help="Path to Stage 1 entry-points.md (optional)")
    ap.add_argument("--component-type", help="DLT component type (informational; logged in output)")
    ap.add_argument("--output", required=True, type=Path, help="Output JSON path")
    ap.add_argument("--max-depth", type=int, default=20, help="Max call-graph depth (default 20)")
    args = ap.parse_args()

    if not args.callgraph.exists():
        print(f"ERROR: callgraph file not found: {args.callgraph}", file=sys.stderr)
        return 2

    try:
        callgraph = json.loads(args.callgraph.read_text())
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid callgraph JSON: {e}", file=sys.stderr)
        return 2

    entry_overrides: dict[str, str] = {}
    if args.entry_points and args.entry_points.exists():
        entry_overrides = parse_entry_points_md(args.entry_points)

    paths = find_paths_to_target(callgraph, args.target_function, args.max_depth)
    bucket, details = assign_reachability(paths, callgraph, entry_overrides)

    # v0.4.1 — evidence-tag eligibility: a callgraph produced by
    # scripts/build-callgraph.sh carries `_meta.source: "scip"`. When present,
    # the resulting reachability verdict may earn the [LSP-TRACE] evidence tag
    # (per shared-rules.md § Evidence-quality tags). Otherwise only [CODE-TRACE].
    cg_meta = callgraph.get("_meta", {}) if isinstance(callgraph, dict) else {}
    callgraph_source = cg_meta.get("source", "grep")  # default to grep fallback
    evidence_tag_eligibility = "[LSP-TRACE]" if callgraph_source == "scip" else "[CODE-TRACE]"

    output = {
        "target_function": args.target_function,
        "component_type": args.component_type,
        "reachability_bucket": bucket,
        "reachability_confidence": "high" if bucket != "unclear" else "low",
        "callgraph_source": callgraph_source,
        "callgraph_indexer": cg_meta.get("indexer"),
        "evidence_tag_eligibility": evidence_tag_eligibility,
        **details,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2))

    print(f"Reachability: {bucket}")
    if details.get("call_path"):
        print(f"Call path: {' → '.join(details['call_path'])}")
    if details.get("dynamic_dispatch_overapproximation"):
        print("Note: dynamic-dispatch over-approximation applied (any implementor reachable)")

    return 0 if bucket != "unclear" else 1


if __name__ == "__main__":
    sys.exit(main())
