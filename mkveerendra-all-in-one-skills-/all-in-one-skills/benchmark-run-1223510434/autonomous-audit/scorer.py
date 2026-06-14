"""
Scorer for autonomous-audit benchmark.

Usage: python scorer.py <output.json> <expected.json>

output.json must contain:
  {"findings": [{"case_id": "...", "vulnerable": bool, "vulnerability_type": "...",
                 "affected_function": "...", "severity": "...", "explanation": "..."}, ...]}

expected.json is an array where each case may have multiple findings.

Scoring per case (max 1.0):
  - Clean case (no findings expected): 1.0 if no findings reported, 0.0 otherwise.
  - Vulnerable case: each expected finding matched greedily (best output match).
      Per finding: vuln_type 0.4 + affected_function 0.3 + severity 0.2 + explanation keywords 0.1
    False positive penalty: -0.2 per unmatched output finding (floor 0.0).
    Case score = total matched / num expected findings (clamped to 0.0-1.0).

Returns a float 0.0-1.0 printed to stdout.
Exit code 0 on success, 1 on error.
"""

import json
import sys

SEVERITY_ORDER = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"]


def load_json(path: str):
    with open(path) as f:
        return json.load(f)


def normalize(s: str) -> str:
    return s.strip().lower().replace(" ", "_").replace("-", "_")


def severity_score(expected_sev: str, output_sev: str) -> float:
    e = normalize(expected_sev)
    o = normalize(output_sev)
    if e == o:
        return 0.2
    try:
        ei = SEVERITY_ORDER.index(e.upper())
        oi = SEVERITY_ORDER.index(o.upper())
        if abs(ei - oi) == 1:
            return 0.1
    except ValueError:
        pass
    return 0.0


def score_finding_pair(output_f: dict, expected_f: dict) -> float:
    score = 0.0

    exp_type = normalize(expected_f.get("vulnerability_type", ""))
    out_type = normalize(output_f.get("vulnerability_type", ""))
    if exp_type and out_type and exp_type == out_type:
        score += 0.4

    exp_fn = normalize(expected_f.get("affected_function", ""))
    out_fn = normalize(output_f.get("affected_function", ""))
    if exp_fn and out_fn and exp_fn == out_fn:
        score += 0.3

    score += severity_score(
        expected_f.get("severity", ""),
        output_f.get("severity", ""),
    )

    exp_expl = expected_f.get("explanation", "").lower()
    out_expl = output_f.get("explanation", "").lower()
    if exp_expl and out_expl and len(out_expl) > 20:
        keywords = [w for w in exp_expl.split() if len(w) > 5]
        hits = sum(1 for k in keywords if k in out_expl)
        if keywords and hits / len(keywords) >= 0.3:
            score += 0.1

    return score


def score_case(output_findings: list[dict], expected_findings: list[dict]) -> float:
    if not expected_findings:
        return 0.0 if output_findings else 1.0

    if not output_findings:
        return 0.0

    matched_output_indices: set[int] = set()
    total_matched = 0.0

    for exp_f in expected_findings:
        best_score = 0.0
        best_idx = -1
        for i, out_f in enumerate(output_findings):
            if i in matched_output_indices:
                continue
            s = score_finding_pair(out_f, exp_f)
            if s > best_score:
                best_score = s
                best_idx = i
        if best_idx >= 0:
            matched_output_indices.add(best_idx)
        total_matched += best_score

    false_positives = len(output_findings) - len(matched_output_indices)
    penalty = false_positives * 0.2

    raw = total_matched / len(expected_findings) - penalty
    return max(0.0, min(1.0, raw))


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: python scorer.py <output.json> <expected.json>", file=sys.stderr)
        sys.exit(1)

    output_path, expected_path = sys.argv[1], sys.argv[2]

    try:
        output_data = load_json(output_path)
        expected_data = load_json(expected_path)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"Error loading files: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(expected_data, list):
        print("expected.json must be a JSON array", file=sys.stderr)
        sys.exit(1)

    output_cases: list[dict] = output_data.get("cases", [])
    output_by_id: dict[str, list[dict]] = {
        c["case_id"]: c.get("findings", [])
        for c in output_cases
        if "case_id" in c
    }

    total_cases = len(expected_data)
    if total_cases == 0:
        print("1.0")
        return

    total_score = 0.0
    for case in expected_data:
        case_id = case.get("id", "")
        expected_findings = case.get("findings", [])
        output_findings = output_by_id.get(case_id, [])
        total_score += score_case(output_findings, expected_findings)

    final_score = total_score / total_cases
    print(f"{final_score:.4f}")


if __name__ == "__main__":
    main()
