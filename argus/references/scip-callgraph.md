# SCIP-Backed Callgraph (v0.4.1)

`scripts/build-callgraph.sh` produces the JSON callgraph that `scripts/reachability.py` consumes. When this script is used, downstream FINDINGs are eligible for the `[LSP-TRACE]` evidence tag (per [shared-rules.md](hacking-agents/shared-rules.md) § Evidence-quality tags), which clears the `[CODE-TRACE]`-only floor on HIGH / CRITICAL infra findings.

## What is SCIP

SCIP (Source Code Intelligence Protocol) is a language-agnostic semantic-index format. A SCIP index is a binary file (`index.scip`) that lists every symbol defined or referenced in a project, with bidirectional def/ref edges and enough source-range data to attribute references to their enclosing function. Argus consumes SCIP because it gives the same precision as a full language-server query without the runtime overhead of running an LSP session per audit.

## When to use it

Argus's Stage 2 reachability check (and Stage 4 Pass A's `reachable_from_public_entry` field) can be answered two ways:

| Source | Evidence tag | Precision | Cost |
|--------|--------------|-----------|------|
| `scripts/reachability.py` with grep-extracted callgraph (legacy) | `[CODE-TRACE]` | regex match — misses macros, trait dispatch, generics | seconds |
| `scripts/build-callgraph.sh` + SCIP (v0.4.1+) | `[LSP-TRACE]` | semantic — sees def/ref edges across modules + crates | one-time `rust-analyzer scip` pass per project |

Per Phase 1.2 (the evidence-tag rule in [shared-rules.md](hacking-agents/shared-rules.md)), an infra FINDING claiming HIGH or CRITICAL severity **must** carry at least one of `[FUZZ-PASS]`, `[LSP-TRACE]`, `[NON-DET-PASS]`, `[CONFORMANCE-PASS]`, or `[DIFF-PASS]`. If the angle's only mechanical evidence is the callgraph trace, the callgraph must come from SCIP (not grep) to earn that tag.

## Prerequisites

One of:

```bash
rustup component add rust-analyzer      # preferred — bundled with rustup
cargo install scip-rust                 # alternative — standalone
```

`scripts/doctor.sh --check-rust` reports which is present.

## Usage

### One-shot (Stage 1 produces the callgraph for the run)

```bash
bash scripts/build-callgraph.sh <project-root> \
     --output $RUN_DIR/1-protocol-map/callgraph.json
```

This drives `rust-analyzer scip .` (or `scip-rust index`) over the project, parses the resulting `index.scip`, and emits the JSON shape `reachability.py` consumes. The temp `.scip` file is cleaned up unless `--keep-scip` is passed.

### Forcing a specific indexer

```bash
bash scripts/build-callgraph.sh <project-root> \
     --output callgraph.json \
     --indexer rust-analyzer     # or: --indexer scip-rust
```

Default `--auto` tries `rust-analyzer` first, falls back to `scip-rust`.

### Direct conversion (when you already have a `.scip` file)

```bash
python3 scripts/scip_to_callgraph.py path/to/index.scip --output callgraph.json
```

Useful when CI already produces a SCIP artifact and you want to skip the indexer pass.

## Output schema

```json
{
  "functions": {
    "<crate::module::function>": {
      "callers": ["<other_fn>", ...],
      "callees": ["<other_fn>", ...],
      "is_pub": true,
      "is_test_only": false,
      "attributes": [],
      "definition_location": "<relative/path.rs:line>",
      "scip_symbol": "<raw SCIP symbol string>"
    }
  },
  "trait_implementors": {
    "<Trait#method>": ["<impl#[Type][Trait]method>", ...]
  },
  "_meta": {
    "source": "scip",
    "documents": 1,
    "occurrences": 33,
    "indexer": "rust-analyzer 1.95.0 (...)",
    "project_root": "file:///.../crate",
    "generated_utc": "<ISO-8601>"
  }
}
```

`reachability.py` checks `_meta.source == "scip"` to decide whether the verdict can carry `[LSP-TRACE]` instead of `[CODE-TRACE]`.

## What the converter handles

| Source pattern | Result |
|----------------|--------|
| Static function call `foo()` | Caller→callee edge |
| Static method call `x.method()` | Caller→callee edge (with `x`'s concrete type's method) |
| Trait method call `<dyn Trait>::method()` | Edge to the trait method; `trait_implementors[Trait#method]` lists candidate impls for over-approximation |
| Generic function `foo::<T>()` | Edge present; type-parametric resolution is rust-analyzer's responsibility |
| `#[cfg(test)] mod tests` | Functions inside flagged `is_test_only: true` (via SCIP-symbol-path heuristic + the TEST role bit when emitted) |
| External crate / `std::*` symbols | Reference dropped (logged as warning); these symbols aren't in the index |

## Known limitations

- **Macro-expanded code**: rust-analyzer's SCIP emit does index macro expansions, but if the user's `rust-analyzer` version is older than 2025 the macro coverage is partial. Doctor reports the version so you can decide.
- **External `is_implementation` relationships**: rust-analyzer emits trait-impl edges via the SCIP symbol pattern `impl#[Type][Trait]method()`, not via the `SymbolInformation.relationships` field. The converter parses both sources; alternative indexers that only populate `relationships` are equally supported.
- **Attribute metadata** (`#[rpc]`, `#[no_mangle]`, etc.) is not exposed in SCIP. The callgraph's `attributes: []` is always empty; reachability bucket classification still relies on Stage-1's `entry-points.md` annotations (`[REACHABILITY=remote|authenticated|local]`).
- **Workspace boundary**: SCIP indexes one crate or workspace at a time. Cross-workspace edges (e.g., a CLI in workspace A calling a library in workspace B that's a separate clone) are not captured. Build separate callgraphs per workspace or run `cargo metadata --workspace` to enumerate every crate the project consumes.

## Graceful degradation

If neither `rust-analyzer` nor `scip-rust` is installed, `build-callgraph.sh` exits with code 2 and a helpful install message. Argus then falls back to its grep-based caller discipline (the [`reachability_check` field in shared-rules.md](hacking-agents/shared-rules.md) v0.1.8 path); FINDINGs from such a run carry only `[CODE-TRACE]` and HIGH / CRITICAL infra claims must produce a different evidence tag (`[FUZZ-PASS]`, `[NON-DET-PASS]`, `[CONFORMANCE-PASS]`, `[DIFF-PASS]`) or be downgraded.

## Integration in the pipeline

| Stage | Use of the callgraph |
|-------|---------------------|
| Stage 1 | `build-callgraph.sh` runs as part of Phase B (surface enumeration), writing `1-protocol-map/callgraph.json` |
| Stage 2 | Every angle's `reachability_check` field consults the callgraph; `is_test_only` and trait-implementor over-approximation come from here |
| Stage 4 Pass A | `reachable_from_public_entry` is set to `yes` only if a callgraph path exists; absence demotes the finding |
| Stage 4 Pass D | Reads `_meta.source` to decide whether to allow `[LSP-TRACE]` evidence tag on the FINDING |

## Smoke test

```bash
# Generate a tiny test crate
mkdir -p /tmp/scip_smoke/src && cd /tmp/scip_smoke
cat > Cargo.toml <<'EOF'
[package]
name = "scip_smoke"
version = "0.1.0"
edition = "2021"
[lib]
path = "src/lib.rs"
EOF
cat > src/lib.rs <<'EOF'
pub fn entry(x: u32) -> u32 { helper(x) }
fn helper(x: u32) -> u32 { x + 1 }
EOF

# Build the callgraph
bash $SKILL_DIR/scripts/build-callgraph.sh . --output callgraph.json

# Verify a reachability query resolves
python3 $SKILL_DIR/scripts/reachability.py \
  --callgraph callgraph.json \
  --target-function scip_smoke::helper \
  --output reach.json
cat reach.json
```

Expect `paths_count >= 1` with a path through `scip_smoke::entry`.
