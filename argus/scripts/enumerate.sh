#!/bin/bash
# Stage 1 helper: enumerate the Rust workspace, compute nSLOC, count tests / fuzz / unsafe blocks,
# detect project shape, and dump git history stats.
#
# Usage:   enumerate.sh <project-root> [<scope-glob>]
# Output:  labeled sections consumed by Argus Stage 1 (overview.md / hot-zones.md / etc.)
#
# Skips:   target/, node_modules/, vendored / mock / test / bench / example crates.

set -e
ROOT="${1:-.}"
SCOPE_GLOB="${2:-}"

cd "$ROOT"

# ─── Project shape detection ─────────────────────────────────────────────────

echo "=== Project shape ==="
# Anchor: any Anchor.toml at root or workspace member
if [ -f Anchor.toml ] || find . -maxdepth 3 -name 'Anchor.toml' -not -path '*/target/*' 2>/dev/null | head -1 | grep -q .; then
  echo "anchor"
elif [ -f Cargo.toml ] && grep -q 'cosmwasm-std' Cargo.toml 2>/dev/null; then
  echo "cosmwasm"
elif find . -maxdepth 3 -name 'Cargo.toml' -not -path '*/target/*' -exec grep -l 'cosmwasm-std' {} \; 2>/dev/null | head -1 | grep -q .; then
  echo "cosmwasm"
elif [ -f Cargo.toml ] && grep -qE 'frame-support|frame-system|pallet-' Cargo.toml 2>/dev/null; then
  echo "substrate"
elif find . -maxdepth 3 -name 'Cargo.toml' -not -path '*/target/*' -exec grep -lE 'frame-support|frame-system|pallet-' {} \; 2>/dev/null | head -1 | grep -q .; then
  echo "substrate"
elif [ -f Cargo.toml ] && grep -q 'solana-program' Cargo.toml 2>/dev/null; then
  echo "solana-native"
elif [ -f Cargo.toml ]; then
  echo "generic-rust"
else
  echo "unknown"
fi

# ─── Workspace members + crate count ─────────────────────────────────────────

echo "=== Workspace ==="
if [ -f Cargo.toml ]; then
  # Try cargo metadata first; fall back to filesystem walk
  if command -v cargo >/dev/null 2>&1; then
    cargo metadata --no-deps --format-version 1 2>/dev/null | python3 -c "
import json, sys
try:
    m = json.load(sys.stdin)
    for p in m.get('packages', []):
        print(f\"{p['name']}: {p['manifest_path']}\")
except Exception:
    pass
" 2>/dev/null || true
  fi
  # Always also list raw Cargo.toml paths so we see them even if cargo isn't installed
  echo "--- raw Cargo.toml manifests ---"
  find . -maxdepth 4 -name 'Cargo.toml' -not -path '*/target/*' -not -path '*/node_modules/*' 2>/dev/null | sort
fi

# ─── Source files with line counts (in scope) ────────────────────────────────

echo "=== Source (with line counts) ==="
# Default scope: every .rs file outside target/, examples/, benches/, tests/, mocks/, vendor/
if [ -n "$SCOPE_GLOB" ]; then
  find . -path "$SCOPE_GLOB" -name '*.rs' \
    -not -path '*/target/*' -not -path '*/node_modules/*' \
    -not -path '*/examples/*' -not -path '*/benches/*' \
    -not -path '*/tests/*' -not -path '*/mock/*' -not -path '*/mocks/*' \
    2>/dev/null | sort | xargs wc -l 2>/dev/null
else
  find . -name '*.rs' \
    -not -path '*/target/*' -not -path '*/node_modules/*' \
    -not -path '*/examples/*' -not -path '*/benches/*' \
    -not -path '*/tests/*' -not -path '*/mock/*' -not -path '*/mocks/*' \
    -not -name '*_test.rs' -not -name 'mock_*.rs' -not -name 'tests.rs' \
    2>/dev/null | sort | xargs wc -l 2>/dev/null
fi

# ─── nSLOC (non-blank, non-comment lines) per file + TOTAL ───────────────────

echo "=== nSLOC ==="
sum=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # Total non-blank lines
  t=$(grep -cP '\S' "$f" 2>/dev/null || true)
  # Comment-only lines: //, /*, *, */ (Rust comment styles)
  c=$(grep -cP '^\s*(//|/\*|\*|\*/)' "$f" 2>/dev/null || true)
  n=$((t - c))
  printf "%s: %d\n" "$f" "$n"
  sum=$((sum + n))
done < <(find . -name '*.rs' \
  -not -path '*/target/*' -not -path '*/node_modules/*' \
  -not -path '*/examples/*' -not -path '*/benches/*' \
  -not -path '*/tests/*' -not -path '*/mock/*' -not -path '*/mocks/*' \
  -not -name '*_test.rs' -not -name 'mock_*.rs' -not -name 'tests.rs' \
  2>/dev/null | sort)
echo "TOTAL: $sum"

# ─── Tests ────────────────────────────────────────────────────────────────────

echo "=== test_files ==="
# Files containing #[cfg(test)] or #[test] or paths under tests/
find . \( -name '*.rs' \) \
  \( -path '*/tests/*' -o -name '*_test.rs' -o -name 'tests.rs' \) \
  -not -path '*/target/*' -not -path '*/node_modules/*' \
  2>/dev/null | wc -l

echo "=== test_functions ==="
# #[test], #[tokio::test], #[anchor_lang::test], #[async_std::test]
grep -rcP '^\s*#\[(tokio|async_std|actix|anchor_lang)?::?test' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | awk -F: '{s+=$NF}END{print s+0}'

echo "=== proptest ==="
# proptest! { ... } macro and #[proptest]
grep -rcP 'proptest!|#\[proptest' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | awk -F: '{s+=$NF}END{print s+0}'

echo "=== kani ==="
# kani::proof attribute
grep -rcP '#\[kani::proof' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | awk -F: '{s+=$NF}END{print s+0}'

echo "=== anchor_test ==="
# Anchor program-test / litesvm patterns
if [ -f Anchor.toml ] || find . -maxdepth 3 -name 'Anchor.toml' -not -path '*/target/*' 2>/dev/null | head -1 | grep -q .; then
  grep -rcE '(solana_program_test|litesvm|BanksClient)' . --include='*.rs' \
    --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
    | awk -F: '{s+=$NF}END{print s+0}'
else
  echo "0"
fi

echo "=== cosmwasm_test ==="
# cw-multi-test patterns
grep -rcE '(cw_multi_test|MultiTest|App::default)' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | awk -F: '{s+=$NF}END{print s+0}'

echo "=== substrate_test ==="
# Substrate mock runtime patterns
grep -rcE '(frame_support::construct_runtime|sp_io::TestExternalities|new_test_ext)' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | awk -F: '{s+=$NF}END{print s+0}'

# ─── Unsafe + unchecked-arithmetic markers ───────────────────────────────────

echo "=== unsafe_blocks ==="
grep -rnE 'unsafe[[:space:]]*\{|unsafe[[:space:]]+impl|unsafe[[:space:]]+fn' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | grep -v '/tests/' | grep -v '/benches/' | grep -v '_test.rs' \
  | head -50

echo "=== unwrap_count ==="
# Unwraps and expects in scope (excluding tests)
grep -rnE '\.unwrap\(\)|\.expect\(' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules \
  --exclude-dir=tests --exclude-dir=benches 2>/dev/null \
  | grep -v '_test.rs' | wc -l

echo "=== checked_arith_count ==="
# checked_*, saturating_*, overflowing_* — high count = good signal of arithmetic discipline
grep -rcE 'checked_(add|sub|mul|div)|saturating_(add|sub|mul|div)|overflowing_(add|sub|mul|div)' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
  | awk -F: '{s+=$NF}END{print s+0}'

echo "=== unchecked_arith_files ==="
# Files containing raw + - * / on user-controlled-looking variables (heuristic: in fn body containing pub fn)
# This is approximate; the audit angles do the real check.
grep -rlE 'pub fn .*\([^)]*u(64|128|32|256)[^)]*\)' . --include='*.rs' \
  --exclude-dir=target --exclude-dir=node_modules \
  --exclude-dir=tests --exclude-dir=benches 2>/dev/null \
  | head -30

# ─── Docs ─────────────────────────────────────────────────────────────────────

echo "=== docs ==="
ls -d README.md README* docs/ doc/ whitepaper/ whitepapers/ spec/ specs/ paper/ papers/ 2>/dev/null || true
find . -maxdepth 3 -name 'WHITEPAPER.md' -o -name 'SPEC.md' -o -name 'DESIGN.md' -o -name 'ARCHITECTURE.md' 2>/dev/null | head -5

# ─── Commit + git history ────────────────────────────────────────────────────

echo "=== commit ==="
git rev-parse --short HEAD 2>/dev/null || echo "unknown"

echo "=== git_branch ==="
git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"

echo "=== git_unique_authors ==="
git log --format='%aN' 2>/dev/null | sort -u | wc -l || echo "0"

echo "=== git_contributors ==="
git log --format='%aN' 2>/dev/null | sort | uniq -c | sort -rn | head -10 || true

echo "=== git_repo_age ==="
git log --reverse --format='%aI' 2>/dev/null | head -1 || true
git log -1 --format='%aI' 2>/dev/null || true

echo "=== git_total_commits ==="
git rev-list --count HEAD 2>/dev/null || echo "0"

echo "=== git_merge_count ==="
git log --merges --oneline 2>/dev/null | wc -l || echo "0"

echo "=== git_hotspots ==="
# Source-file change-frequency ranking
git log --name-only --format='' 2>/dev/null \
  | grep -E '\.rs$' \
  | grep -v '/target/' | grep -v '/tests/' | grep -v '_test.rs' \
  | sort | uniq -c | sort -rn | head -15 || true

echo "=== git_recent_30d ==="
git log --since='30 days ago' --oneline -- '*.rs' 2>/dev/null \
  | grep -v '/tests/' | grep -v '_test.rs' | head -20 || true

echo "=== git_security_keywords ==="
# Recent commits with security-relevant keywords
git log --since='1 year ago' --oneline 2>/dev/null \
  | grep -iE 'fix|bug|security|audit|vuln|cve|exploit|reentry|reentrancy|overflow|underflow|invariant|panic' \
  | head -20 || true

# ─── Source snapshot SHA256 (NEW v0.1.10 — reproducibility) ──────────────────

echo "=== source_snapshot_sha256 ==="
# Compute single SHA256 over sorted list of in-scope .rs files' contents.
# Used by Stage 1 to populate `source_snapshot.in_scope_files_sha256` field.
if command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  HASH_CMD="shasum -a 256"
else
  echo "no_sha256_tool_available"
  HASH_CMD=""
fi

if [ -n "$HASH_CMD" ]; then
  find . -name '*.rs' -not -path '*/target/*' -not -path '*/node_modules/*' \
    -not -path '*/tests/*' -not -name '*_test.rs' \
    2>/dev/null \
    | sort \
    | xargs -I{} $HASH_CMD {} 2>/dev/null \
    | $HASH_CMD \
    | awk '{print $1}'
fi

echo "=== git_commit_sha ==="
git rev-parse HEAD 2>/dev/null || echo "not_a_git_repo"

echo "=== git_dirty ==="
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  echo "clean"
else
  echo "uncommitted-changes-present"
fi

echo "=== audit_timestamp_utc ==="
date -u +"%Y-%m-%dT%H:%M:%SZ"
