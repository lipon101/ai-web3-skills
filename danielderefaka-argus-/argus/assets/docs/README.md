# Project Docs

Drop any context that helps Argus understand what the protocol is supposed to do. Argus reads these at the start of Stage 1 (Protocol Mapping) and uses them to extract doc-stated invariants, actor definitions, trust assumptions, and economic properties.

Useful contents:

- Design docs and specs
- Whitepaper
- Intended invariants (`/// invariant: ...` comments are read directly from source; this folder is for higher-level prose)
- Plain-English descriptions of protocol behavior
- Known limitations or accepted trade-offs

Files can be plain text, markdown, or PDF. To reference online docs, create a file containing one URL per line — Argus will WebFetch them.

If this folder is empty, Argus uses only what's in the codebase (README.md, source comments, `Cargo.toml` metadata).

Doc-stated claims tagged `(per spec)` in Stage 1 outputs are NOT treated as code-verified — Stage 2 angles look for evidence that the code enforces them.
