#!/usr/bin/env python3
"""Rank commits that look like security or vulnerability fixes."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


MESSAGE_RULES = (
    (re.compile(r"\b(security|vulnerability|vuln|exploit|attack)\b", re.IGNORECASE), 8, "message uses explicit security language"),
    (re.compile(r"\b(reentran|overflow|underflow|malleab|oracle|liquidat|redeem|permit|signature|ecdsa)\w*", re.IGNORECASE), 5, "message names a security-sensitive concept"),
    (re.compile(r"\b(fix|patch|mitigat|hard(en|ing)|protect)\w*", re.IGNORECASE), 2, "message says the commit is a fix"),
    (re.compile(r"\b(issue|bug|regression)\b", re.IGNORECASE), 1, "message references a bug or issue"),
)

NEGATIVE_MESSAGE_RULES = (
    (re.compile(r"^\s*docs?:", re.IGNORECASE), -4, "message looks like a docs-only change"),
    (re.compile(r"^\s*chore:", re.IGNORECASE), -3, "message looks like maintenance work"),
    (re.compile(r"^\s*ci:", re.IGNORECASE), -3, "message looks like CI-only work"),
    (re.compile(r"^\s*test:", re.IGNORECASE), -3, "message looks like test-only maintenance"),
    (re.compile(r"^\s*feat:", re.IGNORECASE), -2, "message looks like a feature addition"),
    (re.compile(r"\b(readme|typo|format|lint|rename)\b", re.IGNORECASE), -2, "message points to low-risk cleanup"),
    (re.compile(r"\bchange\s+[A-Za-z0-9_]+\s+to\s+[A-Za-z0-9_]+\b", re.IGNORECASE), -8, "message looks like a broad rename or migration"),
)

PATH_RULES = (
    (re.compile(r"(^|/)(contracts|src|protocol|programs|pallets)/", re.IGNORECASE), 2, "touches core source files"),
    (re.compile(r"(^|/)(proxy|upgrade|govern|owner|access|auth|oracle|price|issuance|staking|vault|pool|bridge|token)\b", re.IGNORECASE), 3, "touches a security-sensitive surface"),
    (re.compile(r"(^|/)(test|tests|spec|fuzz|audit)s?/", re.IGNORECASE), 1, "updates tests or audit material"),
)

CODE_RULES = (
    (re.compile(r"\b(require|revert|assert)\s*\(", re.IGNORECASE), 2, "diff changes runtime checks"),
    (re.compile(r"\b(onlyOwner|onlyRole|nonReentrant|safeTransfer|safeTransferFrom)\b", re.IGNORECASE), 3, "diff changes security primitives"),
    (re.compile(r"\b(ecrecover|recover|permit|signature|approve|allowance)\b", re.IGNORECASE), 3, "diff changes signature or approval handling"),
    (re.compile(r"\b(totalSupply|balanceOf|debt|coll|reward|issuance|snapshot|price|oracle)\b", re.IGNORECASE), 2, "diff changes accounting or oracle terms"),
)

SOURCE_SUFFIXES = (".sol", ".vy", ".rs", ".go", ".cairo", ".move")
DOC_SUFFIXES = (".md", ".rst", ".txt")
TEST_HINTS = ("test/", "tests/", "spec/", "fuzz", ".t.sol", ".spec.", "__tests__")


@dataclass
class RankedCommit:
    sha: str
    short_sha: str
    date: str
    author: str
    subject: str
    score: int
    band: str
    reasons: list[str]
    files: list[str]
    source_files: list[str]
    test_files: list[str]
    added_lines: int
    deleted_lines: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="Path to the git repository")
    parser.add_argument(
        "--limit",
        type=int,
        default=25,
        help="Maximum number of ranked commits to print; use 0 for no limit",
    )
    parser.add_argument("--min-score", type=int, default=4, help="Minimum score required to print a commit")
    parser.add_argument(
        "--rev-range",
        default="--all",
        help="Revision set to scan, for example --all or origin/main..HEAD",
    )
    parser.add_argument("--include-merges", action="store_true", help="Include merge commits")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text")
    return parser.parse_args()


def run_git(repo: Path, *args: str) -> str:
    cmd = ["git", "-C", str(repo), *args]
    completed = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return completed.stdout


def list_commits(repo: Path, rev_range: str, include_merges: bool) -> list[str]:
    args = ["rev-list"]
    if not include_merges:
        args.append("--no-merges")
    args.append(rev_range)
    output = run_git(repo, *args)
    return [line for line in output.splitlines() if line.strip()]


def unique_reasons(reasons: list[str]) -> list[str]:
    ordered: list[str] = []
    seen = set()
    for reason in reasons:
        if reason not in seen:
            ordered.append(reason)
            seen.add(reason)
    return ordered


def is_source_file(path: str) -> bool:
    if path.startswith("contracts/TestContracts/"):
        return False
    return path.endswith(SOURCE_SUFFIXES) or path.startswith(("contracts/", "src/"))


def is_doc_file(path: str) -> bool:
    name = path.rsplit("/", 1)[-1]
    return path.endswith(DOC_SUFFIXES) or name.upper().startswith("README")


def is_test_file(path: str) -> bool:
    lowered = path.lower()
    return lowered.startswith("contracts/testcontracts/") or any(hint in lowered for hint in TEST_HINTS)


def score_rules(text: str, rules: tuple[tuple[re.Pattern[str], int, str], ...]) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    for pattern, weight, reason in rules:
        if pattern.search(text):
            score += weight
            reasons.append(reason)
    return score, reasons


def parse_numstat(repo: Path, sha: str) -> tuple[int, int]:
    output = run_git(repo, "diff-tree", "--root", "--no-commit-id", "--numstat", "-r", sha)
    added = 0
    deleted = 0
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        try:
            added += int(parts[0])
            deleted += int(parts[1])
        except ValueError:
            continue
    return added, deleted


def band_for_score(score: int) -> str:
    if score >= 12:
        return "high"
    if score >= 7:
        return "medium"
    if score >= 4:
        return "low"
    return "noise"


def load_metadata(repo: Path, sha: str) -> tuple[str, str, str, str, str]:
    raw = run_git(repo, "show", "--quiet", "--format=%H%x00%h%x00%ad%x00%an%x00%s", "--date=short", sha)
    parts = raw.rstrip("\n").split("\x00")
    if len(parts) != 5:
        raise ValueError(f"unexpected metadata format for commit {sha}")
    return tuple(parts)  # type: ignore[return-value]


def load_body(repo: Path, sha: str) -> str:
    return run_git(repo, "show", "--quiet", "--format=%b", sha).strip()


def load_files(repo: Path, sha: str) -> list[str]:
    output = run_git(repo, "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", sha)
    return [line for line in output.splitlines() if line.strip()]


def load_diff(repo: Path, sha: str) -> str:
    return run_git(repo, "show", "--format=", "--unified=0", "--no-ext-diff", sha)


def analyze_commit(repo: Path, sha: str) -> RankedCommit:
    full_sha, short_sha, date, author, subject = load_metadata(repo, sha)
    body = load_body(repo, sha)
    files = load_files(repo, sha)
    added_lines, deleted_lines = parse_numstat(repo, sha)
    diff_text = load_diff(repo, sha)

    score = 0
    reasons: list[str] = []

    message_score, message_reasons = score_rules(f"{subject}\n{body}", MESSAGE_RULES)
    score += message_score
    reasons.extend(message_reasons)

    negative_score, negative_reasons = score_rules(subject, NEGATIVE_MESSAGE_RULES)
    score += negative_score
    reasons.extend(negative_reasons)

    source_files = [path for path in files if is_source_file(path)]
    test_files = [path for path in files if is_test_file(path)]
    doc_files = [path for path in files if is_doc_file(path)]

    if source_files:
        score += min(6, len(source_files) * 2)
        reasons.append("touches source code rather than only metadata")

    if source_files and len(files) <= 12:
        score += 2
        reasons.append("diff is focused enough for manual vulnerability review")

    if test_files and source_files:
        score += 2
        reasons.append("adds or updates tests beside source changes")

    if files and len(doc_files) == len(files):
        score -= 6
        reasons.append("touches only documentation files")

    if test_files and len(test_files) == len(files):
        score -= 2
        reasons.append("touches only tests")

    matched_path_reasons = set()
    for path in files:
        for pattern, weight, reason in PATH_RULES:
            if pattern.search(path) and reason not in matched_path_reasons:
                score += weight
                reasons.append(reason)
                matched_path_reasons.add(reason)

    diff_score, diff_reasons = score_rules(diff_text, CODE_RULES)
    score += diff_score
    reasons.extend(diff_reasons)

    if len(files) > 25:
        score -= 4
        reasons.append("broad multi-file diff often indicates migration or refactor noise")

    if len(files) > 60:
        score -= 4
        reasons.append("very large file count makes the commit less likely to be a single focused fix")

    if added_lines + deleted_lines > 2000:
        score -= 4
        reasons.append("very large churn often reflects sweeping changes rather than a targeted fix")

    if added_lines + deleted_lines <= 4:
        score -= 1
        reasons.append("very small diff")

    return RankedCommit(
        sha=full_sha,
        short_sha=short_sha,
        date=date,
        author=author,
        subject=subject,
        score=score,
        band=band_for_score(score),
        reasons=unique_reasons(reasons),
        files=files,
        source_files=source_files,
        test_files=test_files,
        added_lines=added_lines,
        deleted_lines=deleted_lines,
    )


def emit_text(commits: list[RankedCommit], scanned_count: int, repo: Path) -> None:
    print(f"Scanned {scanned_count} commits in {repo}")
    print(f"Ranked {len(commits)} candidate commits")
    print()
    for commit in commits:
        print(f"{commit.short_sha}  score={commit.score}  band={commit.band}  {commit.date}  {commit.subject}")
        print(f"  Author: {commit.author}")
        print(f"  Reasons: {', '.join(commit.reasons)}")
        print(f"  Files: {', '.join(commit.files[:8])}")
        if len(commit.files) > 8:
            print(f"  Files+: {len(commit.files) - 8} more")
        print(f"  Churn: +{commit.added_lines} / -{commit.deleted_lines}")
        print(f"  Review: git show --stat --unified=0 {commit.sha}")
        print()


def main() -> int:
    args = parse_args()
    repo = Path(args.repo).resolve()

    try:
        run_git(repo, "rev-parse", "--show-toplevel")
    except subprocess.CalledProcessError:
        print(f"{repo} is not a git repository", file=sys.stderr)
        return 2

    commits = list_commits(repo, args.rev_range, args.include_merges)
    ranked = [analyze_commit(repo, sha) for sha in commits]
    ranked.sort(key=lambda item: (item.score, item.date, item.sha), reverse=True)
    ranked = [item for item in ranked if item.score >= args.min_score]
    if args.limit > 0:
        ranked = ranked[: args.limit]

    if args.json:
        payload = {
            "repo": str(repo),
            "scanned_commits": len(commits),
            "candidates": [asdict(item) for item in ranked],
        }
        print(json.dumps(payload, indent=2))
    else:
        emit_text(ranked, len(commits), repo)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
