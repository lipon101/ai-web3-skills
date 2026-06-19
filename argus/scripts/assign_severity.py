#!/usr/bin/env python3
"""
Stage 4 severity assigner (infra mode).

Implements the deterministic Impact × Reachability matrix + downgrade rules
from `references/infra-impact-analysis.md`.

Usage:
    python3 assign_severity.py \
        --reachability remote \
        --vector-id A01 \
        --downgrade-rule none \
        --downgrade-evidence ""

Output: JSON to stdout (or --output <path>) with:
    final_severity: CRITICAL | HIGH | MEDIUM | LOW | INFORMATIONAL
    matrix_lookup: CRITICAL | HIGH | MEDIUM | LOW | INFORMATIONAL  (pre-downgrade)
    impact_tier: System Compromise | Data Corruption | ...
    downgrade_applied: <rule_name or "none">
    downgrade_evidence: <user-supplied citation>
    reasoning: <plain-English summary>

Exit codes:
    0 — severity assigned
    1 — vector_id not in VECTOR_TO_IMPACT table (default impact tier applied, warning logged)
    2 — invocation error (invalid reachability, invalid downgrade)
"""

import argparse
import json
import sys

# ─── Vector → Impact Tier mapping ─────────────────────────────────────────────
#
# Per `dlt-infra-attack-vectors.md` and `infra-impact-analysis.md` Step 2.
# Multiple-tier mappings choose the HIGHEST tier.

VECTOR_TO_IMPACT: dict[str, str] = {
    # Group A — Memory Corruption (mostly System Compromise; A05 is Confidentiality)
    "A01": "System Compromise",  # transmute size mismatch
    "A02": "System Compromise",  # transmute lifetime extension
    "A03": "Data Corruption",  # Stacked Borrows violation
    "A04": "System Compromise",  # invalid pointer arithmetic
    "A05": "Confidentiality Breach",  # uninitialized memory read
    "A06": "System Compromise",  # double free
    "A07": "System Compromise",  # use-after-free
    "A08": "Data Corruption",  # provenance loss
    "A09": "Data Corruption",  # data race on UnsafeCell
    "A10": "Data Corruption",  # alignment violation

    # Group B — Unsound Abstractions (Integrity Weakening or Data Corruption)
    "B01": "Data Corruption",  # unsound Send
    "B02": "Data Corruption",  # unsound Sync
    "B03": "Integrity Weakening",  # unsound TrustedLen
    "B04": "Data Corruption",  # custom Drop leak / double-free
    "B05": "Integrity Weakening",  # ExactSizeIterator mismatch
    "B06": "System Compromise",  # unsafe Deref provenance violation
    "B07": "Integrity Weakening",  # unsafe From breaking invariant
    "B08": "System Compromise",  # custom allocator alignment violation
    "B09": "Data Corruption",  # panic in unsafe leaving dangling state
    "B10": "Data Corruption",  # repr(C) FFI mismatch

    # Group C — Integer Overflow (Data Corruption or Funds At Risk)
    "C01": "System Compromise",  # unchecked index from user input
    "C02": "System Compromise",  # with_capacity overflow → undersized alloc → OOB
    "C03": "Data Corruption",  # subtract-then-compare underflow
    "C04": "Data Corruption",  # lossy cast on 32-bit
    "C05": "Funds At Risk",  # wrapping fee calculation
    "C06": "Integrity Weakening",  # off-by-one range mishandling
    "C07": "Data Corruption",  # mmap layout error
    "C08": "Integrity Weakening",  # timestamp arithmetic wrap

    # Group D — Concurrency (Denial of Service or Data Corruption)
    "D01": "Denial of Service",  # lock ordering deadlock
    "D02": "Denial of Service",  # lost Condvar wakeup
    "D03": "Data Corruption",  # Arc refcount overflow → premature free
    "D04": "Data Corruption",  # incorrect atomic ordering
    "D05": "Data Corruption",  # UnsafeCell unprotected (data race)
    "D06": "Data Corruption",  # transmute MutexGuard lifetimes
    "D07": "Denial of Service",  # RwLock writer starvation
    "D08": "Data Corruption",  # Cell/RefCell in Send context

    # Group E — Cryptographic Failures (Confidentiality / Integrity / Funds)
    "E01": "Funds At Risk",  # rand::random for keys
    "E02": "Confidentiality Breach",  # non-constant-time compare
    "E03": "Confidentiality Breach",  # missing zeroisation
    "E04": "Integrity Weakening",  # weak hash for security
    "E05": "Funds At Risk",  # nonce reuse → key recovery
    "E06": "Integrity Weakening",  # weak prime
    "E07": "Integrity Weakening",  # improper sig verification (accepts invalid)
    "E08": "Confidentiality Breach",  # side channel via early-exit

    # Group F — DoS (always Denial of Service)
    "F01": "Denial of Service",
    "F02": "Denial of Service",
    "F03": "Denial of Service",
    "F04": "Denial of Service",
    "F05": "Denial of Service",
    "F06": "Denial of Service",
    "F07": "Denial of Service",

    # Group G — Error Handling & State Machine (Data Corruption or Integrity)
    "G01": "Integrity Weakening",  # silent Result ignore
    "G02": "Denial of Service",  # panic poisons mutex
    "G03": "Data Corruption",  # FFI re-entrancy state mutation
    "G04": "Data Corruption",  # early-return state corruption
    "G05": "Data Corruption",  # async cancellation partial write
    "G06": "Data Corruption",  # TOCTOU
    "G07": "Integrity Weakening",  # block-time assumption
    "G08": "Data Corruption",  # epoch/slot truncation

    # Group H — Supply Chain (varies; conservative: Data Corruption baseline)
    "H01": "Data Corruption",  # vulnerable dep (actual impact = upstream CVE class; conservative bucket)
    "H02": "System Compromise",  # FFI null deref → segfault → potential RCE on some platforms
    "H03": "System Compromise",  # alloc-contract mismatch → heap corruption
    "H04": "System Compromise",  # malicious build.rs
    "H05": "Integrity Weakening",  # unaudited unsafe in 3rd-party
    "H06": "System Compromise",  # typosquat
    "H07": "Data Corruption",  # repr(C) bool padding mismatch
    "H08": "Data Corruption",  # #[no_mangle] collision

    # Group I — DLT-Specific Logic
    "I01": "Denial of Service",  # consensus round stall
    "I02": "Funds At Risk",  # duplicate tx inclusion
    "I03": "Funds At Risk",  # reward distribution overflow
    "I04": "Integrity Weakening",  # peer-scoring bypass → eclipse setup
    "I05": "Data Corruption",  # storage key collision
    "I06": "Funds At Risk",  # bridge double-claim
    "I07": "Integrity Weakening",  # off-chain worker stale-data state change
    "I08": "Funds At Risk",  # wallet multi-sig address derivation
    "I09": "System Compromise",  # VM sandbox escape
    "I10": "Confidentiality Breach",  # RPC info leak
}

# ─── Legacy v0.3.x impact category → Immunefi v2.3 impact tier (v0.4.0) ───────
#
# The v0.3.x impact categories (System Compromise / Data Corruption / Funds At
# Risk / Denial of Service / Confidentiality Breach / Integrity Weakening) now
# serve as classifier-inputs that map to the 5 Immunefi-aligned tiers. Per
# `infra-impact-analysis.md` Step 2.

LEGACY_IMPACT_TO_TIER: dict[str, str] = {
    "System Compromise":      "Critical",
    "Data Corruption":        "Critical",
    "Funds At Risk":          "Critical",
    "Denial of Service":      "High",
    "Confidentiality Breach": "High",
    "Integrity Weakening":    "Medium",
}

# Impact-tier order for resolution (highest wins when multiple apply).
IMPACT_TIER_ORDER = ["Informational", "Low", "Medium", "High", "Critical"]

# ─── Severity matrix: (impact_tier, likelihood) → severity (v0.4.0) ───────────
#
# Per `infra-impact-analysis.md` Step 4 (Immunefi v2.3-aligned).

SEVERITY_MATRIX: dict[tuple[str, str], str] = {
    ("Critical",       "high"):    "CRITICAL",
    ("Critical",       "medium"):  "HIGH",
    ("Critical",       "low"):     "HIGH",

    ("High",           "high"):    "HIGH",
    ("High",           "medium"):  "HIGH",
    ("High",           "low"):     "MEDIUM",

    ("Medium",         "high"):    "MEDIUM",
    ("Medium",         "medium"):  "MEDIUM",
    ("Medium",         "low"):     "LOW",

    ("Low",            "high"):    "LOW",
    ("Low",            "medium"):  "LOW",
    ("Low",            "low"):     "LOW",

    ("Informational",  "high"):    "INFORMATIONAL",
    ("Informational",  "medium"):  "INFORMATIONAL",
    ("Informational",  "low"):     "INFORMATIONAL",
}

# Test-only / unclear handling (preserved from v0.3.x)
TEST_ONLY_SEVERITY = "INFORMATIONAL"
UNCLEAR_SEVERITY_FALLBACK = "INFORMATIONAL"  # conservative; user must review

# Severity ordering for modifier logic
SEVERITY_ORDER = ["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"]

# Modifiers (v0.4.0). Each modifier shifts the tier by ±N.
DOWNGRADE_MODIFIERS = {
    "BYZANTINE-1-3":              ("-1", None),         # > 1/3 Byzantine stake
    "BYZANTINE-2-3":              ("-2", None),         # > 2/3 Byzantine stake
    "FULLY-TRUSTED-ROLE":         ("-1", "INFORMATIONAL"),
    "SELF-HARM-ONLY":             ("-1", "INFORMATIONAL"),
    "TESTNET-ONLY":               ("-1", None),
    "ON-CHAIN-ONLY-OBSERVATION":  ("-1", None),
    "LATENT-DEAD-CODE":           ("cap-HIGH", None),
    # legacy v0.3.x downgrade rules preserved as aliases
    "TRUSTED-ROLE-REQUIRED":      ("-1", "INFORMATIONAL"),  # alias for FULLY-TRUSTED-ROLE
    "PRACTICAL-DIFFICULTY":       ("-1", None),             # alias for BYZANTINE-1-3 class
    "BOUNDED-IMPACT":             ("-1", None),
    "UPGRADEABLE":                ("-1", None),
}

UPGRADE_MODIFIERS = {
    "CROSS-CHAIN-BRIDGE-FUND-LOSS":     ("+1", None),
    "FINALITY-STRICT-CHAIN":            ("+1", None),
    "ATTACKER-HAS-SOURCE-CONTROL":      ("+1", None),
    "PERMISSIONLESS-ZERO-STAKE":        ("+1", "MEDIUM"),   # +1 only if base >= Medium
    "UNAUTHENTICATED-RPC-ENDPOINT":     ("+1", "MEDIUM"),   # +1 only if base >= Medium
    "PRE-AUTH-PANIC":                   ("floor-HIGH", None),
}


def shift_severity(severity: str, delta: int, floor: str | None = None) -> str:
    """Shift severity by `delta` tiers (positive = upgrade, negative = downgrade).
    `floor`, if set, prevents descending below that severity.
    `INFORMATIONAL` ceiling never exceeded; `CRITICAL` ceiling never exceeded."""
    if severity not in SEVERITY_ORDER:
        return severity
    idx = SEVERITY_ORDER.index(severity)
    new_idx = max(0, min(len(SEVERITY_ORDER) - 1, idx + delta))
    new_severity = SEVERITY_ORDER[new_idx]
    if floor and SEVERITY_ORDER.index(new_severity) < SEVERITY_ORDER.index(floor):
        return floor
    return new_severity


def apply_modifier(severity: str, modifier: str) -> tuple[str, str]:
    """Apply one modifier; returns (new_severity, rationale_note)."""
    if modifier in DOWNGRADE_MODIFIERS:
        rule, floor = DOWNGRADE_MODIFIERS[modifier]
        if rule == "cap-HIGH":
            if SEVERITY_ORDER.index(severity) > SEVERITY_ORDER.index("HIGH"):
                return "HIGH", f"{modifier}: capped at HIGH (latent / dead-code)"
            return severity, f"{modifier}: already <= HIGH, no shift"
        delta = int(rule)  # e.g. "-1" → -1
        new = shift_severity(severity, delta, floor)
        return new, f"{modifier}: shift {rule}{' floor:' + floor if floor else ''}"
    if modifier in UPGRADE_MODIFIERS:
        rule, gate = UPGRADE_MODIFIERS[modifier]
        if rule == "floor-HIGH":
            if SEVERITY_ORDER.index(severity) < SEVERITY_ORDER.index("HIGH"):
                return "HIGH", f"{modifier}: floor HIGH (single-packet node-kill primitive)"
            return severity, f"{modifier}: already >= HIGH, no shift"
        delta = int(rule)
        if gate and SEVERITY_ORDER.index(severity) < SEVERITY_ORDER.index(gate):
            return severity, f"{modifier}: gated (base < {gate}), no shift"
        new = shift_severity(severity, delta)
        return new, f"{modifier}: shift {rule}"
    return severity, f"unknown-modifier:{modifier}"


# Deprecated single-rule alias retained for back-compat in tests / docs
DOWNGRADE_RULES = set(DOWNGRADE_MODIFIERS.keys())


def downgrade_one_tier(severity: str) -> str:
    """Legacy helper retained for backwards-compatibility with v0.3.x callers."""
    return shift_severity(severity, -1)


# ─── Main ─────────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # v0.4.0: --likelihood replaces --reachability. --reachability still accepted
    # as legacy alias that maps to likelihood for back-compat.
    ap.add_argument(
        "--likelihood",
        choices=["high", "medium", "low", "test-only", "unclear"],
        help="Immunefi v2.3 likelihood tier (v0.4.0 replacement for --reachability)",
    )
    ap.add_argument(
        "--reachability",
        choices=["remote", "authenticated", "local", "test-only", "unclear"],
        help="LEGACY v0.3.x — maps to --likelihood: remote→high, authenticated→medium, local→low",
    )
    ap.add_argument("--vector-id", required=True, help="e.g. A01, C02, I06")
    ap.add_argument(
        "--modifier",
        action="append",
        default=[],
        help="Apply modifier(s). May be repeated. Choices: " + ", ".join(sorted(set(DOWNGRADE_MODIFIERS) | set(UPGRADE_MODIFIERS))),
    )
    ap.add_argument(
        "--modifier-evidence",
        action="append",
        default=[],
        help="Evidence citation per modifier (file:line or component-type entry). Required when --modifier is supplied.",
    )
    # Legacy v0.3.x flags (still accepted as alias for --modifier)
    ap.add_argument(
        "--downgrade-rule",
        default="none",
        choices=["none", *sorted(DOWNGRADE_MODIFIERS.keys())],
        help="LEGACY v0.3.x — single-modifier flag. Use --modifier (repeatable) for v0.4.0 stacked modifiers.",
    )
    ap.add_argument(
        "--downgrade-evidence",
        default="",
        help="LEGACY v0.3.x — evidence for --downgrade-rule",
    )
    ap.add_argument("--output", help="Path to write JSON output (default: stdout)")
    args = ap.parse_args()

    # Resolve --likelihood from --reachability if needed
    REACH_TO_LIKE = {"remote": "high", "authenticated": "medium", "local": "low",
                     "test-only": "test-only", "unclear": "unclear"}
    if args.likelihood is None:
        if args.reachability is None:
            print("ERROR: --likelihood (v0.4.0) or --reachability (legacy) required", file=sys.stderr)
            return 2
        likelihood = REACH_TO_LIKE[args.reachability]
        legacy_axis_used = True
    else:
        likelihood = args.likelihood
        legacy_axis_used = False

    # Resolve modifiers (v0.4.0 list + legacy single flag)
    modifiers: list[tuple[str, str]] = []  # (modifier_name, evidence)
    for i, mod in enumerate(args.modifier):
        ev = args.modifier_evidence[i] if i < len(args.modifier_evidence) else ""
        if not ev.strip():
            print(f"ERROR: --modifier={mod} requires matching --modifier-evidence", file=sys.stderr)
            return 2
        modifiers.append((mod, ev))
    if args.downgrade_rule != "none":
        if not args.downgrade_evidence.strip():
            print(f"ERROR: --downgrade-rule={args.downgrade_rule} requires --downgrade-evidence", file=sys.stderr)
            return 2
        modifiers.append((args.downgrade_rule, args.downgrade_evidence))

    # Impact tier resolution
    vector_id = args.vector_id.upper().strip()
    if vector_id not in VECTOR_TO_IMPACT:
        print(
            f"WARNING: vector_id '{vector_id}' not in VECTOR_TO_IMPACT table; "
            f"defaulting to 'Integrity Weakening'. Update assign_severity.py + "
            f"dlt-infra-attack-vectors.md.",
            file=sys.stderr,
        )
        legacy_impact = "Integrity Weakening"
        impact_warning = True
    else:
        legacy_impact = VECTOR_TO_IMPACT[vector_id]
        impact_warning = False

    # Map legacy v0.3.x impact category → Immunefi v2.3 impact tier
    impact_tier = LEGACY_IMPACT_TO_TIER.get(legacy_impact, "Medium")

    # Likelihood short-circuits
    if likelihood == "test-only":
        matrix_severity = TEST_ONLY_SEVERITY
        reasoning_parts = [
            f"Likelihood=test-only → severity capped at INFORMATIONAL.",
            f"Vector {vector_id} (legacy={legacy_impact} → tier={impact_tier}) not submitted; logged as LEAD.",
        ]
    elif likelihood == "unclear":
        matrix_severity = UNCLEAR_SEVERITY_FALLBACK
        reasoning_parts = [
            f"Likelihood=unclear (call graph incomplete / preconditions ambiguous).",
            "Falling back to INFORMATIONAL; manual review required.",
        ]
    else:
        key = (impact_tier, likelihood)
        if key not in SEVERITY_MATRIX:
            print(f"ERROR: matrix key {key} not defined", file=sys.stderr)
            return 2
        matrix_severity = SEVERITY_MATRIX[key]
        reasoning_parts = [
            f"Matrix: Impact={impact_tier} (legacy={legacy_impact}) × Likelihood={likelihood} → {matrix_severity}."
        ]

    # Apply modifiers in order. They stack (floor:Informational, ceiling:Critical).
    final_severity = matrix_severity
    modifier_trace: list[dict] = []
    for mod_name, mod_evidence in modifiers:
        if mod_name not in DOWNGRADE_MODIFIERS and mod_name not in UPGRADE_MODIFIERS:
            print(f"WARNING: unknown modifier '{mod_name}'; skipping", file=sys.stderr)
            continue
        prev = final_severity
        final_severity, note = apply_modifier(final_severity, mod_name)
        modifier_trace.append({
            "modifier": mod_name,
            "evidence": mod_evidence,
            "before": prev,
            "after": final_severity,
            "rationale": note,
        })
        reasoning_parts.append(f"Modifier {mod_name}: {prev} → {final_severity} ({note}; evidence: {mod_evidence})")

    output = {
        "vector_id": vector_id,
        "legacy_impact_category": legacy_impact,
        "impact_tier": impact_tier,
        "impact_warning_default_applied": impact_warning,
        "likelihood": likelihood,
        "legacy_axis_used": legacy_axis_used,
        "matrix_lookup": matrix_severity,
        "modifiers_applied": modifier_trace,
        "final_severity": final_severity,
        "severity_rationale": " ".join(reasoning_parts),
    }

    out_json = json.dumps(output, indent=2)
    if args.output:
        from pathlib import Path

        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(out_json)
    else:
        print(out_json)

    return 1 if impact_warning else 0


if __name__ == "__main__":
    sys.exit(main())
