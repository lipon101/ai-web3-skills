# Research Triangulation

Use this workflow when you want to turn broad security intuition into a
defensible finding or a focused non-finding.

## Source Roles

- generic vulnerability catalogs provide the baseline class taxonomy
- protocol-specific frequency indexes provide a priority order for explicit
  protocol checks
- exploit research and mechanic notes provide edge cases, hidden callback
  surfaces, compiler behavior, and deployment-process failure modes
- skill packaging examples provide user-facing install and update ergonomics

## Audit Loop

1. Start with the local protocol reference and enumerate the entry points
   that can break the protocol's core invariants.
2. Map each candidate issue to one or more generic classes from
   `references/common/vulnerability-taxonomy.md`.
3. Cross-check the protocol's high-frequency categories before declaring an
   area low risk.
4. If the mechanic is unusual, explicitly test whether it is really one of
   these research-heavy classes:
   - hidden token callback reentrancy
   - read-only reentrancy
   - router approval drain or arbitrary calldata execution
   - vault donation or LP pricing oracle manipulation
   - same-transaction governance vote and execution
   - compiler-version or deployment-sequencing bugs
   - proxy initialization race or proxy hijack patterns
5. Return to `references/workflow/judging.md` and keep only findings with a
   reachable exploit path and a broken invariant.

## How To Use Frequency Priors

- use frequency to decide what must get an explicit pass
- do not use frequency as a substitute for evidence
- do not use frequency as a severity score
- rare classes still matter when the code contains the enabling mechanic

## Upstream Knowledge Sources

- `pashov/skills`: concise install and update ergonomics for public skill
  repos
- `kadenzipfel/smart-contract-vulnerabilities`: generic cross-protocol
  vulnerability classes
- `kadenzipfel/protocol-vulnerabilities-index`: high-frequency categories per
  protocol type from audit findings
- `evmresearch`: exploit mechanics, language and compiler footguns, and
  process-layer failure modes
