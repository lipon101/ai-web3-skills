# Contributing to Argus

## Pull request process

1. Fork the repo and create a branch from `main`.
2. Make your changes — attack vectors, hacking-agent prompts, platform criteria, Stage 1 templates, or documentation.
3. Ensure your branch is up to date with `main` before opening a PR.
4. Do not edit `VERSION` directly — it is bumped automatically on merge via CI (see `.github/workflows/version-bump.yml`).
5. Update `CHANGELOG.md` under the appropriate version section (`Added` / `Changed` / `Fixed` / `Removed`). Never modify entries for already-released versions.
6. Fill in the PR template. A maintainer will review within 5 business days.

### PR checklist

- [ ] No API keys, tokens, secrets, or personal data committed
- [ ] No fabricated examples — outputs must reflect real model responses on real Rust code
- [ ] Changes pass `bash -n` for any modified shell scripts
- [ ] If a stage's contract changed, `references/pipeline-overview.md` updated to match
- [ ] If a hacking angle was added/changed, `SKILL.md` Stage 2 dispatch table updated
- [ ] If a platform was added, `references/platform-criteria/<platform>.md` added AND `platform-validation.md` URL routing table updated
- [ ] If an attack vector was added, the `Vn` ID is the next available and `Vector Scan` agent's classification block expectations match

## What to contribute

- **Attack vectors** — add new vectors to `references/attack-vectors/rust-attack-vectors.md` following the existing `**D:**` (description) / `**FP:**` (fixed pattern) format. Vectors are language-aware: Solana / Anchor, CosmWasm, Substrate, generic Rust.
- **Hacking-agent prompts** — improve the 8 angles in `references/hacking-agents/`. Tighten output format, reduce false positives, add Rust-ecosystem-specific patterns.
- **Platform criteria** — add new bug-bounty / contest platforms under `references/platform-criteria/`. Source rules from the platform's published criteria; bundled file must include the live-page WebFetch divergence-check note.
- **Stage 1 output templates** — improve `references/stage1-output-templates.md` if the current templates produce poor outputs on a real Rust target.
- **Bug fixes** — if Argus produces incorrect output, open an issue or PR with a fix.
- **Eval benchmarks** — add public-Rust-audit ground truth files under `evals/benchmarks/` per the format in `evals/benchmarks/README.md`.

## Quality bar

- One stage, one purpose. Don't bundle changes that touch multiple stages.
- Code citations always include `file:line` (or `crate::module::function`). Prose alone is not evidence.
- Reference files are operational — they tell the model what to do. No marketing language. No "comprehensive" / "robust" / "industry-leading".
- The audit logic must be Rust-native. If a change reads like Solidity-with-Rust-labels, reject it from the PR.

## Reporting bugs

Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) issue template and include:

- Which stage / angle / reference is affected
- The Claude / OpenAI model used
- The input you gave (Rust target, bounty URL, repo URL)
- The output you got
- What you expected instead
