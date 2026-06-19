# Security Policy

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities in Argus itself.**

Argus is offensive-security tooling. If you find a way that Argus produces dangerously misleading output on a class of Rust codebases — false-negative on a critical vulnerability category, false-positive that would mislead an auditor into submitting a bad finding, or any path where Argus's gates fail to catch a known-bad finding — that's a security bug in Argus and we want to fix it.

Email the maintainers directly. Include:

- Description of the issue
- A minimal reproducer (Rust codebase or finding text)
- The Argus stage / angle / reference involved
- The model used (Claude version / OpenAI model)
- Potential impact
- Any suggested mitigations

You can expect an acknowledgement within **48 hours** and a status update within **7 days**.

## Scope of this policy

This policy is for security issues in **Argus itself** — the skill, the references, the hacking-agent prompts, the gates. It is **not** for vulnerabilities found in target Rust codebases that you analyzed using Argus — those go to the target project's bug-bounty program (which Argus's Stage 6 fetches and applies).

## Out of scope

- Findings produced by Argus that are AI hallucinations on a specific run. Run-to-run variance is expected; please open a regular issue if you can demonstrate a systemic class of hallucinations.
- "Argus didn't catch X" without a minimal reproducer. Please run the eval benchmarks against the target codebase and include the output.
- Cosmetic / typo / docs issues. Please open a regular PR.
