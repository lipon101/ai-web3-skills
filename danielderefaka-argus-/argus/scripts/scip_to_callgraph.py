#!/usr/bin/env python3
"""
Argus SCIP → callgraph converter (NEW v0.4.1).

Reads a SCIP index (`index.scip` produced by `rust-analyzer scip <dir>` or
`scip-rust index <dir>`) and emits the JSON callgraph format consumed by
`reachability.py`:

    {
      "functions": {
        "<crate::module::function>": {
          "callers": [...],
          "callees": [...],          # convenience reverse map
          "is_pub": <bool>,
          "is_test_only": <bool>,
          "attributes": [...],
          "definition_location": "<relative/path.rs:line>"
        },
        ...
      },
      "trait_implementors": {
        "<TraitSymbol>": [<ImplSymbol>, ...]
      },
      "_meta": {
        "source": "scip",
        "documents": <int>,
        "occurrences": <int>,
        "indexer": "<tool-version>",
        "generated_utc": "<ISO-8601>"
      }
    }

When this converter is the callgraph source, every reachability verdict the
downstream `reachability.py` produces is eligible for the `[LSP-TRACE]`
evidence tag (per `shared-rules.md` § Evidence-quality tags). When the
callgraph was grep-extracted instead, only `[CODE-TRACE]` is available.

Argus does not depend on `protobuf` from PyPI; this module hand-parses the
subset of SCIP wire-format we need (varints + length-delimited strings +
repeated submessages) so the toolchain works out-of-the-box.

Usage:
    python3 scip_to_callgraph.py <path/to/index.scip> --output callgraph.json
    python3 scip_to_callgraph.py <path/to/index.scip> --output - | jq .

Exit codes:
    0 — converted; callgraph written
    1 — converted but with warnings (unresolved symbols, ambiguous dispatch)
    2 — invocation error (bad path, malformed SCIP)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

# ─── SCIP symbol-role bitmask (from scip.proto) ─────────────────────────────
# https://github.com/sourcegraph/scip/blob/main/scip.proto
ROLE_DEFINITION       = 0x1
ROLE_IMPORT           = 0x2
ROLE_WRITE_ACCESS     = 0x4
ROLE_READ_ACCESS      = 0x8
ROLE_GENERATED        = 0x10
ROLE_TEST             = 0x20
ROLE_FORWARD_DEFN     = 0x40

# SCIP symbol-string suffix grammar (more robust than the `kind` enum, whose
# field number drifts across proto versions and emitter implementations).
# Reference: https://github.com/sourcegraph/scip/blob/main/Symbol.md
#
#   <descriptor>(...).   — method or function (note trailing period after `)`)
#   <descriptor>().      — same, with explicit empty signature
#   <descriptor>#        — class / struct / enum / trait (a "type" descriptor)
#   <descriptor>.        — term (constant, variable, module — non-callable)
#
# rust-analyzer encodes Rust traits with the `#` suffix, like any other type.

# ─── Minimal protobuf wire-format parser ─────────────────────────────────────
# protobuf wire types:
#   0 = varint  (int32/int64/uint32/uint64/bool/enum)
#   1 = 64-bit  (fixed64/sfixed64/double)
#   2 = length-delimited (string/bytes/embedded-message/packed-repeated)
#   5 = 32-bit  (fixed32/sfixed32/float)

def _decode_varint(buf: bytes, pos: int) -> tuple[int, int]:
    """Read a single varint starting at pos. Returns (value, new_pos)."""
    result = 0
    shift = 0
    while True:
        if pos >= len(buf):
            raise ValueError(f"truncated varint at {pos}")
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7
        if shift > 63:
            raise ValueError(f"varint too long at {pos}")

def _decode_tag(buf: bytes, pos: int) -> tuple[int, int, int]:
    """Read a field tag. Returns (field_number, wire_type, new_pos)."""
    tag, pos = _decode_varint(buf, pos)
    return tag >> 3, tag & 0x7, pos

def _read_field(buf: bytes, pos: int, wire_type: int) -> tuple[bytes | int, int]:
    """Read a single field value matching wire_type. Returns (value, new_pos)."""
    if wire_type == 0:  # varint
        v, pos = _decode_varint(buf, pos)
        return v, pos
    if wire_type == 1:  # 64-bit
        return buf[pos:pos+8], pos + 8
    if wire_type == 2:  # length-delimited
        length, pos = _decode_varint(buf, pos)
        return buf[pos:pos+length], pos + length
    if wire_type == 5:  # 32-bit
        return buf[pos:pos+4], pos + 4
    raise ValueError(f"unsupported wire type {wire_type} at {pos}")

def _skip_field(buf: bytes, pos: int, wire_type: int) -> int:
    """Skip an unknown field. Returns new_pos."""
    _, pos = _read_field(buf, pos, wire_type)
    return pos

def parse_message_fields(buf: bytes) -> dict[int, list]:
    """
    Parse a top-level message into {field_number: [values...]}.
    Values are bytes for length-delimited fields, int for varints, raw bytes
    for fixed-width. Repeated fields are collected.
    """
    fields: dict[int, list] = defaultdict(list)
    pos = 0
    while pos < len(buf):
        fnum, wtype, pos = _decode_tag(buf, pos)
        if wtype == 2:
            length, pos = _decode_varint(buf, pos)
            fields[fnum].append(buf[pos:pos+length])
            pos += length
        elif wtype == 0:
            v, pos = _decode_varint(buf, pos)
            fields[fnum].append(v)
        elif wtype == 1:
            fields[fnum].append(buf[pos:pos+8])
            pos += 8
        elif wtype == 5:
            fields[fnum].append(buf[pos:pos+4])
            pos += 4
        else:
            raise ValueError(f"unsupported wire type {wtype} at {pos}")
    return fields

def parse_packed_varints(buf: bytes) -> list[int]:
    """Parse a packed repeated varint field (used for Occurrence.range)."""
    out: list[int] = []
    pos = 0
    while pos < len(buf):
        v, pos = _decode_varint(buf, pos)
        out.append(v)
    return out


# ─── SCIP message decoders ──────────────────────────────────────────────────

def decode_metadata(buf: bytes) -> dict:
    """Metadata: version(1), tool_info(2), project_root(3), text_encoding(4)."""
    f = parse_message_fields(buf)
    meta: dict = {}
    if 2 in f:
        ti = parse_message_fields(f[2][0])
        # ToolInfo: name=1, version=2, arguments=3 (repeated)
        if 1 in ti:
            meta["tool_name"] = ti[1][0].decode("utf-8", errors="replace")
        if 2 in ti:
            meta["tool_version"] = ti[2][0].decode("utf-8", errors="replace")
    if 3 in f:
        meta["project_root"] = f[3][0].decode("utf-8", errors="replace")
    return meta

def _safe_str(field_items: list, default: str = "") -> str:
    """Decode a field's first value as UTF-8 string if it's bytes, else default."""
    if not field_items:
        return default
    v = field_items[0]
    return v.decode("utf-8", errors="replace") if isinstance(v, bytes) else default

def _safe_int(field_items: list, default: int = 0) -> int:
    """Get a field's first value as int if it's varint, else default."""
    if not field_items:
        return default
    v = field_items[0]
    return v if isinstance(v, int) else default


def decode_symbol_information(buf: bytes) -> dict:
    """
    SymbolInformation: symbol(1), repeated documentation(2),
                       repeated relationships(3), ... [kind/display_name vary
                       across emitters; we only consume `symbol` and
                       `relationships` for trait-impl edges].
    Relationship: symbol(1), is_reference(2), is_implementation(3),
                  is_type_definition(4), is_definition(5)
    """
    f = parse_message_fields(buf)
    sym = {
        "symbol": _safe_str(f.get(1, [])),
        "relationships": [],
    }
    for rel_buf in f.get(3, []):
        if not isinstance(rel_buf, bytes):
            continue
        rf = parse_message_fields(rel_buf)
        sym["relationships"].append({
            "symbol":             _safe_str(rf.get(1, [])),
            "is_reference":       bool(_safe_int(rf.get(2, []))),
            "is_implementation":  bool(_safe_int(rf.get(3, []))),
            "is_type_definition": bool(_safe_int(rf.get(4, []))),
            "is_definition":      bool(_safe_int(rf.get(5, []))),
        })
    return sym

def decode_occurrence(buf: bytes) -> dict:
    """
    Occurrence: range(1, packed int32), symbol(2), symbol_roles(3, varint),
                syntax_kind(5), enclosing_range(7, packed int32)
    """
    f = parse_message_fields(buf)
    occ: dict = {
        "symbol": f.get(2, [b""])[0].decode("utf-8", errors="replace"),
        "symbol_roles": f.get(3, [0])[0],
    }
    if 1 in f:
        occ["range"] = parse_packed_varints(f[1][0])
    if 7 in f:
        occ["enclosing_range"] = parse_packed_varints(f[7][0])
    return occ

def decode_document(buf: bytes) -> dict:
    """
    Document — rust-analyzer's SCIP emit (empirically verified against
    rust-analyzer 1.95.0): relative_path(1), occurrences(2,repeated),
    symbols(3,repeated), language(4), text(5).

    Note: this differs from the public scip.proto field ordering (which lists
    language as field 1, relative_path as field 2). Trust the bytes that
    rust-analyzer / scip-rust actually emit.
    """
    f = parse_message_fields(buf)
    doc = {
        "relative_path": f.get(1, [b""])[0].decode("utf-8", errors="replace") if 1 in f else "",
        "occurrences":   [decode_occurrence(o)        for o in f.get(2, [])],
        "symbols":       [decode_symbol_information(s) for s in f.get(3, [])],
        "language":      f.get(4, [b""])[0].decode("utf-8", errors="replace") if 4 in f else "",
    }
    return doc

def parse_scip_index(path: Path) -> dict:
    """
    Index: metadata(1), documents(2, repeated), external_symbols(3, repeated)
    """
    raw = path.read_bytes()
    f = parse_message_fields(raw)
    return {
        "metadata":         decode_metadata(f[1][0]) if 1 in f else {},
        "documents":        [decode_document(d) for d in f.get(2, [])],
        "external_symbols": [decode_symbol_information(s) for s in f.get(3, [])],
    }


# ─── SCIP-symbol → human-readable name ──────────────────────────────────────
# SCIP symbol grammar (Rust): `rust-analyzer cargo <pkg> <ver> <module-path>(<sig>).`
# Example: `rust-analyzer cargo my_crate 0.1.0 my_module/my_func().`

def scip_symbol_to_qualified_name(scip_sym: str) -> str:
    """Best-effort conversion of a SCIP symbol to crate::module::function form."""
    if not scip_sym or scip_sym.startswith("local "):
        return scip_sym
    parts = scip_sym.split(" ")
    if len(parts) < 4:
        return scip_sym
    # parts[0]=scheme, parts[1]=manager, parts[2]=package_name, parts[3]=version, parts[4+]=descriptors
    package = parts[2]
    desc = " ".join(parts[4:]) if len(parts) > 4 else ""
    # Strip the trailing descriptor terminator and parens
    desc = desc.rstrip(".").rstrip("/")
    # SCIP encodes module path as `mod1/mod2/fn().` — convert to `::`
    name = desc.replace("/", "::").replace("().", "").replace("().", "")
    # Drop signature parens from method/function names
    if "(" in name:
        name = name[:name.index("(")]
    return f"{package}::{name}" if name else package

def occurrence_is_definition(occ: dict) -> bool:
    return bool(occ.get("symbol_roles", 0) & ROLE_DEFINITION)

def occurrence_is_test(occ: dict) -> bool:
    return bool(occ.get("symbol_roles", 0) & ROLE_TEST)


# ─── Callgraph builder ──────────────────────────────────────────────────────

def is_function_symbol(scip_sym: str) -> bool:
    """A SCIP symbol is a function/method iff the last descriptor ends with `)`
    followed by the descriptor terminator `.`. Handles non-empty signatures too
    (e.g. `fn(u32)#`-style suffixes don't apply in rust-analyzer's emit but
    we tolerate them).
    """
    if not scip_sym:
        return False
    # Strip whitespace and trailing terminator
    s = scip_sym.rstrip()
    # Strip trailing `.` terminator that ends every descriptor
    while s.endswith("."):
        # Look at character before the terminator
        return s[-2] == ")"
    return False

def is_trait_or_type_symbol(scip_sym: str) -> bool:
    """A SCIP symbol is a class/struct/enum/trait iff it ends with `#`."""
    return bool(scip_sym) and scip_sym.rstrip().endswith("#")

def is_function_or_method(sym_info: dict) -> bool:
    """Compatibility wrapper — accept either symbol-info dict or sym string."""
    if isinstance(sym_info, dict):
        return is_function_symbol(sym_info.get("scip_symbol", "") or sym_info.get("symbol", ""))
    return is_function_symbol(sym_info)

def is_trait(sym_info: dict) -> bool:
    if isinstance(sym_info, dict):
        return is_trait_or_type_symbol(sym_info.get("scip_symbol", "") or sym_info.get("symbol", ""))
    return is_trait_or_type_symbol(sym_info)

def range_contains(outer: list[int], inner_start_line: int, inner_start_char: int) -> bool:
    """Return True iff inner (line, char) starts within outer SCIP range."""
    if not outer or len(outer) < 3:
        return False
    olen = len(outer)
    o_start_line = outer[0]
    o_start_char = outer[1]
    if olen >= 4:
        o_end_line = outer[2]
        o_end_char = outer[3]
    else:
        o_end_line = outer[0]
        o_end_char = outer[2]
    if inner_start_line < o_start_line:
        return False
    if inner_start_line == o_start_line and inner_start_char < o_start_char:
        return False
    if inner_start_line > o_end_line:
        return False
    if inner_start_line == o_end_line and inner_start_char > o_end_char:
        return False
    return True

def is_test_path(rel_path: str) -> bool:
    """Heuristic: a relative path is test-only if any directory segment matches."""
    parts = rel_path.split("/")
    return any(p in ("tests", "test", "benches", "examples") for p in parts) or \
           rel_path.endswith("_test.rs") or rel_path.endswith("tests.rs")


def is_test_symbol_path(scip_sym: str) -> bool:
    """SCIP-symbol descriptor heuristic: any descriptor segment named `tests`,
    `test`, `benches`, or `examples` between the version field and the leaf
    descriptor marks the symbol as test-only. Catches `#[cfg(test)] mod tests`
    blocks that live in lib.rs (which the path heuristic alone misses)."""
    if not scip_sym:
        return False
    parts = scip_sym.split()
    if len(parts) < 5:
        return False
    descriptor = " ".join(parts[4:])
    # Split descriptors at `/` (module separator). Each segment may carry a
    # type tag (`#`), a function tag (`()`), or none (term).
    for seg in descriptor.split("/"):
        # Strip trailing tags / terminators
        s = seg.rstrip(".#")
        if s.endswith(")"):
            s = s.rsplit("(", 1)[0]
        if s in ("tests", "test", "benches", "examples"):
            return True
    return False

def build_callgraph(scip_index: dict) -> tuple[dict, list[str]]:
    """
    Build the callgraph JSON dict from the parsed SCIP index.
    Returns (callgraph_dict, warnings_list).

    Strategy: definition occurrences (DEFINITION role bit set) seed the symbol
    catalog. We use the SCIP symbol-string suffix grammar to detect functions
    (`<name>(...).` or `<name>().`) and traits/types (`<name>#`). SymbolInformation
    metadata is consulted for relationships (trait implementors) only — kind /
    display_name field numbers differ across SCIP proto versions so we don't
    rely on them.
    """
    warnings: list[str] = []

    # Pass 1 — symbol catalog from definition occurrences
    symbols: dict[str, dict] = {}
    for doc in scip_index["documents"]:
        rel = doc["relative_path"]
        doc_is_test = is_test_path(rel)

        # Pre-index SymbolInformation for relationships (trait impl edges)
        sym_info_by_sym: dict[str, dict] = {
            s["symbol"]: s for s in doc["symbols"] if s.get("symbol")
        }

        for occ in doc["occurrences"]:
            if not occurrence_is_definition(occ):
                continue
            sym = occ.get("symbol", "")
            if not sym:
                continue
            meta = symbols.setdefault(sym, {
                "scip_symbol": sym,
                "relationships": sym_info_by_sym.get(sym, {}).get("relationships", []),
                "definition_file": None,
                "definition_line": None,
                "is_test_only": False,
                "is_pub": False,
            })
            if meta["definition_file"] is None:
                meta["definition_file"] = rel
                meta["definition_line"] = (occ["range"][0] + 1) if occ.get("range") else None
            if doc_is_test or occurrence_is_test(occ) or is_test_symbol_path(sym):
                meta["is_test_only"] = True
            # Pub-ness: SCIP doesn't reliably mark visibility, so we treat every
            # non-`local` symbol as pub-eligible. Stage-1 entry-points.md overrides
            # discipline downstream verdicts; over-permissive here is the right default.
            if not sym.startswith("local "):
                meta["is_pub"] = True

    # Pass 2 — for each function definition, find every reference occurrence in
    # every document and attribute each reference to the function that physically
    # encloses it (the enclosing_range of the reference occurrence).
    # The "caller" is the function whose enclosing_range contains the reference;
    # the "callee" is the symbol of the reference.
    callers_of:  dict[str, set[str]] = defaultdict(set)
    callees_of:  dict[str, set[str]] = defaultdict(set)
    occurrence_count = 0

    for doc in scip_index["documents"]:
        # First pass on this doc: find all function-definition ranges
        # so we can attribute reference occurrences to their enclosing function.
        defs_in_doc: list[tuple[str, list[int]]] = []
        for occ in doc["occurrences"]:
            if not occurrence_is_definition(occ):
                continue
            sym = occ["symbol"]
            if sym not in symbols:
                continue
            if not is_function_or_method(symbols[sym]):
                continue
            # Definition's enclosing_range = the function body range
            enc = occ.get("enclosing_range") or occ.get("range")
            if enc:
                defs_in_doc.append((sym, enc))

        # Second pass: every non-definition reference occurrence
        for occ in doc["occurrences"]:
            occurrence_count += 1
            if occurrence_is_definition(occ):
                continue
            ref_sym = occ["symbol"]
            if not ref_sym or ref_sym not in symbols:
                continue
            # Only track references to functions/methods
            if not is_function_or_method(symbols[ref_sym]):
                continue
            r = occ.get("range")
            if not r:
                continue
            ref_line, ref_col = r[0], r[1]
            # Find the enclosing definition
            enclosing_caller = None
            for def_sym, enc_range in defs_in_doc:
                if range_contains(enc_range, ref_line, ref_col):
                    enclosing_caller = def_sym
                    # Don't break — there may be nested functions; the LAST
                    # match in source order is typically the innermost.
            if enclosing_caller and enclosing_caller != ref_sym:
                callers_of[ref_sym].add(enclosing_caller)
                callees_of[enclosing_caller].add(ref_sym)

    # Pass 3 — trait implementors. Two sources:
    #   (a) SymbolInformation.relationships with is_implementation=True (the
    #       "official" SCIP encoding; not always populated).
    #   (b) Symbol-name pattern from rust-analyzer: a method symbol of the form
    #       `... impl#[<ImplType>][<TraitName>]<method>()` synthesizes an edge
    #       from `Trait#method` → `impl#[Impl][Trait]method` so dynamic dispatch
    #       on the trait can be over-approximated to the impl.
    trait_implementors: dict[str, set[str]] = defaultdict(set)
    impl_pat = re.compile(r"impl#\[([^\]]+)\]\[([^\]]+)\]([A-Za-z_][A-Za-z0-9_]*)\(\)")
    for doc in scip_index["documents"]:
        for sym_info in doc["symbols"]:
            impl_sym = sym_info.get("symbol", "")
            if not impl_sym:
                continue
            # Source (a)
            for rel in sym_info.get("relationships", []):
                if rel.get("is_implementation") and rel.get("symbol"):
                    trait_implementors[rel["symbol"]].add(impl_sym)
            # Source (b)
            m = impl_pat.search(impl_sym)
            if m:
                impl_type, trait_name, method = m.group(1), m.group(2), m.group(3)
                prefix = impl_sym.split(" impl#")[0]
                trait_method_sym = f"{prefix} {trait_name}#{method}()."
                trait_implementors[trait_method_sym].add(impl_sym)

    # Assemble output
    functions: dict[str, dict] = {}
    for sym, meta in symbols.items():
        if not is_function_or_method(meta):
            continue
        name = scip_symbol_to_qualified_name(sym)
        functions[name] = {
            "callers":              sorted(scip_symbol_to_qualified_name(c) for c in callers_of.get(sym, set())),
            "callees":              sorted(scip_symbol_to_qualified_name(c) for c in callees_of.get(sym, set())),
            "is_pub":               meta["is_pub"],
            "is_test_only":         meta["is_test_only"],
            "attributes":           [],
            "definition_location":  f"{meta['definition_file']}:{meta['definition_line']}" if meta.get("definition_file") else None,
            "scip_symbol":          sym,
        }

    trait_impls_out: dict[str, list[str]] = {}
    for trait_sym, impls in trait_implementors.items():
        trait_name = scip_symbol_to_qualified_name(trait_sym)
        trait_impls_out[trait_name] = sorted(scip_symbol_to_qualified_name(s) for s in impls)

    unresolved_count = sum(
        1 for doc in scip_index["documents"]
        for occ in doc["occurrences"]
        if not occurrence_is_definition(occ) and occ["symbol"] and occ["symbol"] not in symbols
    )
    if unresolved_count > 0:
        warnings.append(
            f"{unresolved_count} reference occurrences point at symbols outside this SCIP index "
            f"(external crates / std). Their callgraph edges are dropped."
        )

    callgraph = {
        "functions":          functions,
        "trait_implementors": trait_impls_out,
        "_meta": {
            "source":          "scip",
            "documents":       len(scip_index["documents"]),
            "occurrences":     occurrence_count,
            "indexer":         f"{scip_index['metadata'].get('tool_name', '?')} {scip_index['metadata'].get('tool_version', '?')}",
            "project_root":    scip_index["metadata"].get("project_root", ""),
            "generated_utc":   datetime.now(timezone.utc).isoformat(),
        },
    }
    return callgraph, warnings


# ─── Main ───────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("scip_index", type=Path, help="Path to index.scip")
    ap.add_argument("--output", "-o", default="-",
                    help="Output path (default: stdout). Use - for stdout.")
    ap.add_argument("--quiet", action="store_true",
                    help="Suppress informational stderr messages")
    args = ap.parse_args()

    if not args.scip_index.exists():
        print(f"ERROR: SCIP index not found: {args.scip_index}", file=sys.stderr)
        return 2

    try:
        scip_index = parse_scip_index(args.scip_index)
    except (ValueError, IndexError) as e:
        print(f"ERROR: failed to parse SCIP index: {e}", file=sys.stderr)
        return 2

    callgraph, warnings = build_callgraph(scip_index)

    payload = json.dumps(callgraph, indent=2)
    if args.output == "-":
        sys.stdout.write(payload + "\n")
    else:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(payload + "\n")
        if not args.quiet:
            print(
                f"Wrote callgraph: {out} "
                f"({len(callgraph['functions'])} functions, "
                f"{len(callgraph['trait_implementors'])} trait impls, "
                f"{callgraph['_meta']['documents']} documents)",
                file=sys.stderr,
            )

    if warnings and not args.quiet:
        for w in warnings:
            print(f"WARN: {w}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
