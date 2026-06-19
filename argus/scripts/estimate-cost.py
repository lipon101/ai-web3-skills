#!/usr/bin/env python3
"""
Argus Stage 0 — Cost Estimator

Reads enumerate.sh output (or computes minimal metrics directly) and produces
a per-stage cost breakdown for the upcoming audit run.

Usage:
    python3 estimate-cost.py <project-root> [--enumerate-output <file>] [--dup-mode local-only|full] [--findings-est N]

Outputs to stdout. Argus consumes the structured block + presents to user via AskUserQuestion.
"""

from __future__ import annotations
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from dataclasses import dataclass

# ─── Pricing (per million tokens, Anthropic API as of 2026) ──────────────────
# These are list-price rates; cached input is ~10x cheaper but Argus's token
# estimate already accounts for cache hits in the per-stage profiles.

PRICING = {
    "sonnet": {"input": 3.00, "output": 15.00},   # $3/$15 per M
    "opus":   {"input": 15.00, "output": 75.00},  # $15/$75 per M
    "haiku":  {"input": 1.00,  "output": 5.00},   # $1/$5 per M
}

# Per-stage model mix (input / output token fraction by model)
# Argus uses Sonnet for selectors / checkers and Opus for the orchestrator,
# adversarial generator, and final judge. Stage 4 is the Opus-heaviest stage.
STAGE_MIX = {
    "stage1": {"sonnet": 0.70, "opus": 0.30, "haiku": 0.0},
    "stage2": {"sonnet": 0.50, "opus": 0.50, "haiku": 0.0},
    "stage3": {"sonnet": 0.60, "opus": 0.40, "haiku": 0.0},
    "stage4": {"sonnet": 0.30, "opus": 0.70, "haiku": 0.0},
    "stage5": {"sonnet": 1.00, "opus": 0.00, "haiku": 0.0},
    "stage6": {"sonnet": 1.00, "opus": 0.00, "haiku": 0.0},
    "stage7": {"sonnet": 0.80, "opus": 0.20, "haiku": 0.0},
    "stage8": {"sonnet": 1.00, "opus": 0.00, "haiku": 0.0},
}

# Subscription tier rough envelopes (5-hour windows)
SUBSCRIPTION_5H = {
    "Claude Pro (~$20/mo)":      5_000_000,
    "Claude Max-5x (~$100/mo)":  25_000_000,
    "Claude Max-20x (~$200/mo)": 100_000_000,
}


@dataclass
class Metrics:
    nsloc: int = 0
    file_count: int = 0
    project_shape: str = "generic-rust"
    test_count: int = 0
    fuzz_count: int = 0
    kani_count: int = 0
    unsafe_count: int = 0
    git_commits: int = 0


def parse_enumerate_output(path: Path) -> Metrics:
    """Parse the labeled-section output of scripts/enumerate.sh."""
    m = Metrics()
    if not path.exists():
        return m
    text = path.read_text(errors="ignore")

    # Project shape
    shape_match = re.search(r"=== Project shape ===\s*\n(\w[\w\-]*)", text)
    if shape_match:
        m.project_shape = shape_match.group(1)

    # nSLOC TOTAL
    nsloc_match = re.search(r"^TOTAL:\s*(\d+)$", text, re.MULTILINE)
    if nsloc_match:
        m.nsloc = int(nsloc_match.group(1))

    # Source file count: count entries in === Source (with line counts) === block
    src_block = re.search(r"=== Source \(with line counts\) ===\s*\n(.*?)\n===", text, re.DOTALL)
    if src_block:
        # File lines look like "<count> <path>"; total line is "<count> total"
        lines = [ln for ln in src_block.group(1).split("\n") if re.match(r"^\s*\d+\s+\S", ln)]
        # Subtract 1 if the last is the "total" line
        if lines and "total" in lines[-1]:
            lines = lines[:-1]
        m.file_count = len(lines)

    # Test-related counts
    for label, attr in [
        ("test_functions", "test_count"),
        ("proptest", "fuzz_count"),
        ("kani", "kani_count"),
    ]:
        match = re.search(rf"=== {label} ===\s*\n(\d+)", text)
        if match:
            setattr(m, attr, int(match.group(1)))

    # Unsafe blocks: count grep hits
    unsafe_block = re.search(r"=== unsafe_blocks ===\s*\n(.*?)\n===", text, re.DOTALL)
    if unsafe_block:
        m.unsafe_count = len([ln for ln in unsafe_block.group(1).split("\n") if ln.strip()])

    # Git total commits
    git_match = re.search(r"=== git_total_commits ===\s*\n(\d+)", text)
    if git_match:
        m.git_commits = int(git_match.group(1))

    return m


def derive_metrics_directly(root: Path) -> Metrics:
    """Fallback when no enumerate output is supplied — compute minimal metrics."""
    m = Metrics()

    # Project shape detection
    if (root / "Anchor.toml").exists() or any(root.glob("**/Anchor.toml")):
        m.project_shape = "anchor"
    elif (root / "Cargo.toml").exists():
        cargo = (root / "Cargo.toml").read_text(errors="ignore")
        if "cosmwasm-std" in cargo:
            m.project_shape = "cosmwasm"
        elif any(s in cargo for s in ("frame-support", "frame-system", "pallet-")):
            m.project_shape = "substrate"
        elif "solana-program" in cargo:
            m.project_shape = "solana-native"
        else:
            m.project_shape = "generic-rust"
    else:
        m.project_shape = "unknown"

    # Walk .rs files for nSLOC + count
    skip_dirs = {"target", "node_modules", "tests", "examples", "benches", "mock", "mocks"}
    for rs in root.rglob("*.rs"):
        if any(part in skip_dirs for part in rs.parts):
            continue
        if rs.name.endswith("_test.rs") or rs.name == "tests.rs":
            continue
        m.file_count += 1
        try:
            for line in rs.read_text(errors="ignore").splitlines():
                stripped = line.strip()
                if stripped and not stripped.startswith(("//", "/*", "*", "*/")):
                    m.nsloc += 1
        except Exception:
            pass

    return m


def estimate_findings_count(m: Metrics) -> tuple[int, int]:
    """Return (low, high) finding count estimate."""
    # Heuristic: ~1 finding per 50-100 nSLOC, capped between 3 and 35
    low = max(3, m.nsloc // 100)
    high = min(35, max(8, m.nsloc // 50))
    return low, high


def cost_for(input_tokens: int, output_tokens: int, mix: dict) -> float:
    """Compute USD cost given token counts and model mix."""
    cost = 0.0
    for model, frac in mix.items():
        rates = PRICING[model]
        cost += (input_tokens * frac / 1_000_000) * rates["input"]
        cost += (output_tokens * frac / 1_000_000) * rates["output"]
    return cost


# Depth-tier multipliers (v0.4.0)
# Tier-light = smoke audit (4 Stage 2 angles, Tier-3 PoC accepted, Pass A+D only)
# Tier-core  = default (8 angles, Tier-2 PoC minimum, full 4-pass)
# Tier-thorough = + 4 depth-agent re-runs, Tier-1 live e2e mandatory, 2× rebuttal
DEPTH_TIER_MULTIPLIERS = {
    "light":    {"stage1": 1.0, "stage2": 0.5, "stage3": 0.7, "stage4": 0.4,
                 "stage5": 1.0, "stage6": 1.0, "stage7": 1.0, "stage8": 1.0},
    "core":     {"stage1": 1.0, "stage2": 1.0, "stage3": 1.0, "stage4": 1.0,
                 "stage5": 1.0, "stage6": 1.0, "stage7": 1.0, "stage8": 1.0},
    "thorough": {"stage1": 1.0, "stage2": 1.6, "stage3": 1.5, "stage4": 1.8,
                 "stage5": 1.0, "stage6": 1.0, "stage7": 1.0, "stage8": 1.0},
}


def stage_estimate(m: Metrics, findings_est: int, dup_mode: str,
                   depth_tier: str = "core") -> dict:
    """Return per-stage token + cost estimates, scaled by depth tier."""
    n = m.nsloc
    f = findings_est
    mult = DEPTH_TIER_MULTIPLIERS[depth_tier]
    estimates = {}

    # Stage 1: Protocol mapping
    s1_in = n * 3 + 50_000  # source read + reference files
    s1_out = 25_000 + n // 2
    estimates["stage1"] = {
        "name": "Protocol mapping",
        "input": s1_in, "output": s1_out,
        "wall_min": 1 + n // 5000,
        "cost": cost_for(s1_in, s1_out, STAGE_MIX["stage1"]),
    }

    # Stage 2: 8 parallel attacker angles
    per_angle_in = n * 3 + 60_000
    per_angle_out = 8_000 + (f // 8) * 4_000  # ~3-5k per finding
    s2_in = per_angle_in * 8
    s2_out = per_angle_out * 8 + 30_000  # + dedupe overhead
    estimates["stage2"] = {
        "name": "Audit angles (8 parallel)",
        "input": s2_in, "output": s2_out,
        "wall_min": 4 + n // 8000,
        "cost": cost_for(s2_in, s2_out, STAGE_MIX["stage2"]),
    }

    # Stage 3: PoC generation per finding (Tier-1 attempts)
    per_finding_in = 35_000
    per_finding_out = 8_000
    s3_in = f * per_finding_in
    s3_out = f * per_finding_out
    estimates["stage3"] = {
        "name": "PoC generation",
        "input": s3_in, "output": s3_out,
        "wall_min": 3 + f * 1,  # 1 min/finding for compile+run cycles
        "cost": cost_for(s3_in, s3_out, STAGE_MIX["stage3"]),
    }

    # Stage 4: Adversarial 4-pass per finding (Opus-heavy)
    per_finding_in = 45_000
    per_finding_out = 25_000
    s4_in = f * per_finding_in
    s4_out = f * per_finding_out
    estimates["stage4"] = {
        "name": "Adversarial review (Opus-heavy)",
        "input": s4_in, "output": s4_out,
        "wall_min": 4 + f * 1,
        "cost": cost_for(s4_in, s4_out, STAGE_MIX["stage4"]),
    }

    # Stage 5: Platform validation
    per_finding_in = 25_000
    per_finding_out = 10_000
    s5_in = f * per_finding_in
    s5_out = f * per_finding_out
    estimates["stage5"] = {
        "name": "Platform validation",
        "input": s5_in, "output": s5_out,
        "wall_min": 2 + f // 4,
        "cost": cost_for(s5_in, s5_out, STAGE_MIX["stage5"]),
    }

    # Stage 6: Program triage (WebFetch + per-finding)
    s6_in = 30_000 + f * 12_000
    s6_out = 5_000 + f * 5_000
    estimates["stage6"] = {
        "name": "Program triage",
        "input": s6_in, "output": s6_out,
        "wall_min": 2 + f // 5,
        "cost": cost_for(s6_in, s6_out, STAGE_MIX["stage6"]),
    }

    # Stage 7: Duplication probes (cost depends on dup-mode)
    per_finding_probes = 25_000 if dup_mode == "full" else 5_000
    s7_in = f * per_finding_probes
    s7_out = f * (per_finding_probes // 5)
    estimates["stage7"] = {
        "name": f"Duplication probes ({dup_mode})",
        "input": s7_in, "output": s7_out,
        "wall_min": 2 + f // 4,
        "cost": cost_for(s7_in, s7_out, STAGE_MIX["stage7"]),
    }

    # Stage 8: Final output + Phase 8b formatting
    s8_in = 50_000 + f * 8_000
    s8_out = 20_000 + f * 6_000
    estimates["stage8"] = {
        "name": "Final output + report formatting",
        "input": s8_in, "output": s8_out,
        "wall_min": 2 + f // 5,
        "cost": cost_for(s8_in, s8_out, STAGE_MIX["stage8"]),
    }

    # Apply depth-tier multipliers (v0.4.0)
    for stage_key, e in estimates.items():
        factor = mult[stage_key]
        if factor == 1.0:
            continue
        e["input"] = int(e["input"] * factor)
        e["output"] = int(e["output"] * factor)
        e["cost"] = cost_for(e["input"], e["output"], STAGE_MIX[stage_key])
        e["wall_min"] = max(1, int(e["wall_min"] * factor))

    return estimates


def render_report(m: Metrics, findings_low: int, findings_high: int,
                  estimates_low: dict, estimates_high: dict, dup_mode: str,
                  bounty_url_set: bool, depth_tier: str = "core") -> str:
    """Build the structured cost-preview text."""
    lines = []
    lines.append("═" * 65)
    lines.append("Argus — Cost Preview (Stage 0)")
    lines.append("═" * 65)
    lines.append("")
    lines.append(f"  Depth tier:       {depth_tier}  (light=smoke, core=default, thorough=maximum)")
    lines.append(f"  Project shape:    {m.project_shape}")
    lines.append(f"  Codebase:         {m.nsloc:,} nSLOC, {m.file_count} source files")
    lines.append(f"  Test coverage:    {m.test_count} tests, {m.fuzz_count} fuzz, {m.kani_count} formal")
    lines.append(f"  Unsafe blocks:    {m.unsafe_count}")
    lines.append(f"  Git history:      {m.git_commits} commits" if m.git_commits else "  Git history:      (not computed)")
    lines.append(f"  Estimated finds:  {findings_low}–{findings_high} candidates → ~{(findings_low+findings_high)//2} after gates")
    lines.append(f"  Bounty URL:       {'supplied' if bounty_url_set else 'generic-mode (Stage 6 less expensive)'}")
    lines.append(f"  Dup-mode:         {dup_mode}")
    lines.append("")
    lines.append("─" * 65)
    lines.append("Per-stage estimates (low → high finding count)")
    lines.append("─" * 65)

    stages = ["stage1", "stage2", "stage3", "stage4", "stage5", "stage6", "stage7", "stage8"]
    header = f"  {'Stage':<33} {'Tokens (low)':>14} {'Cost (low–high)':>20}"
    lines.append(header)
    lines.append("  " + "─" * (len(header) - 2))

    total_in_low = total_out_low = 0
    total_in_high = total_out_high = 0
    total_cost_low = total_cost_high = 0.0
    total_wall_low = total_wall_high = 0

    for s in stages:
        e_low, e_high = estimates_low[s], estimates_high[s]
        tokens_low = e_low["input"] + e_low["output"]
        cost_str = f"${e_low['cost']:.2f} – ${e_high['cost']:.2f}"
        lines.append(f"  {e_low['name']:<33} {format_tokens(tokens_low):>14} {cost_str:>20}")
        total_in_low += e_low["input"]; total_out_low += e_low["output"]
        total_in_high += e_high["input"]; total_out_high += e_high["output"]
        total_cost_low += e_low["cost"]; total_cost_high += e_high["cost"]
        total_wall_low += e_low["wall_min"]; total_wall_high += e_high["wall_min"]

    lines.append("  " + "─" * (len(header) - 2))
    total_tokens_low = total_in_low + total_out_low
    total_tokens_high = total_in_high + total_out_high
    lines.append(f"  {'TOTAL':<33} {format_tokens(total_tokens_low) + '–' + format_tokens(total_tokens_high):>14} ${total_cost_low:.2f} – ${total_cost_high:.2f}")
    lines.append(f"  {'wall-clock':<33} ~{total_wall_low}–{total_wall_high} min")
    lines.append("")
    lines.append("─" * 65)
    lines.append("Subscription / API estimates")
    lines.append("─" * 65)
    lines.append(f"  API direct (Anthropic):                ${total_cost_low:.2f} – ${total_cost_high:.2f}")
    for tier, budget in SUBSCRIPTION_5H.items():
        pct_low = (total_tokens_low / budget) * 100
        pct_high = (total_tokens_high / budget) * 100
        lines.append(f"  {tier:<38} {pct_low:.0f}–{pct_high:.0f}% of one 5-hour window")
    lines.append("")
    lines.append("─" * 65)
    lines.append("Cost drivers in this run")
    lines.append("─" * 65)

    for driver in compute_drivers(m, findings_high, dup_mode, bounty_url_set):
        lines.append(f"  • {driver}")

    lines.append("")
    lines.append("─" * 65)
    lines.append("Notes")
    lines.append("─" * 65)
    lines.append("  • Stage 4 is the most expensive (Opus model for adversarial passes).")
    lines.append("  • Cost scales with finding count; Stage 2's dedup may produce fewer findings than estimated.")
    lines.append("  • Tier-1 PoC compile/run time is wall-clock only, not in token estimate.")
    lines.append("  • Estimates are approximate; real cost may vary ±30%.")
    lines.append("")
    lines.append("═" * 65)

    return "\n".join(lines)


def format_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    elif n >= 1_000:
        return f"{n/1000:.0f}k"
    return str(n)


def compute_drivers(m: Metrics, findings_high: int, dup_mode: str, bounty_set: bool) -> list:
    drivers = []
    if m.project_shape == "anchor":
        drivers.append("Anchor project shape: Stage 3 will attempt Tier-1 RPC discovery (localnet/devnet) — adds ~30% to Stage 3 cost vs. generic-Rust.")
    if m.nsloc > 5000:
        drivers.append(f"Large codebase ({m.nsloc:,} nSLOC): Stage 2's 8 parallel angles each read full source — Stage 2 is ~{int(m.nsloc/1000 * 0.6)}M tokens alone.")
    if findings_high > 20:
        drivers.append(f"High finding count ({findings_high}): Stages 3-7 scale linearly per finding. Consider --scope flag to focus on hot zones.")
    if m.unsafe_count > 5:
        drivers.append(f"{m.unsafe_count} unsafe blocks: Periphery + First Principles angles will deeply review — adds Stage 2 cost.")
    if not bounty_set:
        drivers.append("No bounty URL: Stage 6 runs in generic-mode (cheaper, no WebFetch). Stage 8 caps confidence at 65.")
    if dup_mode == "local-only":
        drivers.append("Local-only dup-mode: Stage 7 cheaper (no GitHub probes). Provide repo URL to enable full duplication checks.")
    if m.test_count == 0 and m.project_shape == "anchor":
        drivers.append("Zero tests detected: Stage 3 will need to scaffold from scratch — adds ~20% to Stage 3 cost.")
    if not drivers:
        drivers.append("No exceptional cost drivers — standard estimate applies.")
    return drivers


def main():
    ap = argparse.ArgumentParser(description="Argus Stage 0 Cost Estimator")
    ap.add_argument("project_root", help="Path to the Rust project to audit")
    ap.add_argument("--enumerate-output", help="Path to enumerate.sh output (preferred)")
    ap.add_argument("--dup-mode", choices=["local-only", "full"], default="local-only")
    ap.add_argument("--bounty-url-set", action="store_true",
                    help="User supplied a bounty URL at run start (Stage 6 will WebFetch)")
    ap.add_argument("--findings-est", type=int, default=None,
                    help="Override the heuristic finding-count estimate")
    ap.add_argument("--depth-tier", choices=["light", "core", "thorough"], default="core",
                    help="v0.4.0 — audit depth tier (light=smoke, core=default, thorough=maximum)")
    args = ap.parse_args()

    root = Path(args.project_root).resolve()
    if not root.exists():
        print(f"ERROR: project root not found: {root}", file=sys.stderr)
        sys.exit(1)

    if args.enumerate_output:
        m = parse_enumerate_output(Path(args.enumerate_output))
        # Backfill missing fields from direct walk if needed
        if m.nsloc == 0 or m.file_count == 0:
            fallback = derive_metrics_directly(root)
            if m.nsloc == 0: m.nsloc = fallback.nsloc
            if m.file_count == 0: m.file_count = fallback.file_count
            if m.project_shape in ("generic-rust", "unknown"): m.project_shape = fallback.project_shape
    else:
        m = derive_metrics_directly(root)

    if args.findings_est:
        f_low = f_high = args.findings_est
    else:
        f_low, f_high = estimate_findings_count(m)

    estimates_low = stage_estimate(m, f_low, args.dup_mode, args.depth_tier)
    estimates_high = stage_estimate(m, f_high, args.dup_mode, args.depth_tier)

    print(render_report(m, f_low, f_high, estimates_low, estimates_high,
                        args.dup_mode, args.bounty_url_set, args.depth_tier))


if __name__ == "__main__":
    main()
