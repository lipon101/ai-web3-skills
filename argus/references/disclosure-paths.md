# Stage 5 — Disclosure Path Selection (`infra` mode)

> Replaces SC-mode `platform-validation.md` for `infra` mode. Source: DeepSeek `chunk5.md`, integrated 2026-05-12.

## Purpose

For every severity-assigned finding from Stage 4 (per `infra-impact-analysis.md`), select the correct disclosure path. The path determines **who** receives the report, **in what format**, and **on what embargo timeline**.

There are no contest platforms in `infra` mode (no Code4rena / Sherlock / Cantina). DLT infrastructure findings flow through vendor-coordination, vendor-direct reports, standalone CVE disclosure, or public issues.

## Input

- Stage 4 impact analysis: `$RUN_DIR/4-impact/F-NN.md`
- `final_severity` (CRITICAL / HIGH / MEDIUM / LOW / INFORMATIONAL)
- Component type from Stage 1 (`dlt-infra-types.md`): validator client / consensus engine / p2p networking / crypto library / storage engine / RPC node / off-chain worker / bridge relayer / wallet / smart-contract VM / generic Rust DLT crate
- Repository metadata: is the project a core protocol, an independent implementation, or a library crate? (extracted from `Cargo.toml` `package.name`, `repository`, `homepage`, plus download-count from crates.io if available)

## Disclosure Path Table

| Severity | Component scope | Disclosure path |
|----------|-----------------|-----------------|
| **CRITICAL** | Core protocol (consensus, crypto lib, p2p) | **vendor-coordinated** — direct to security team + CVE |
| **CRITICAL** | Independent implementation | **vendor-report** — maintainer + CVE |
| **HIGH** | Any | **vendor-report** (maintainer) + optional CVE |
| **MEDIUM** | Any | **vendor-report** (public issue OK after fix) |
| **LOW** | Any | **generic-infra** (public issue or note) |
| **INFORMATIONAL** | Any | **internal** only (no disclosure) |

If multiple components are affected, the **highest-severity path** wins.

## Path Definitions

### `vendor-coordinated`

- Private disclosure to the organisation's security contact (e.g., `security@<org>.org` or listed Immunefi / HackerOne / private security advisory).
- **Request a CVE ID** from MITRE or via GitHub Security Advisory.
- Include full tool evidence (Miri trace / Kani counterexample / fuzz crash artifact) and reproduction steps.
- **Embargo**: 90 days or until fix released, whichever is earlier.
- Template: `references/report-templates/infra/advisory.md`.

### `vendor-report`

- Private disclosure to the maintainer via email or GitHub private security advisory.
- Optionally request CVE if HIGH severity and likely to be exploited; mandatory CVE for CRITICAL in independent-implementation scope.
- Template: `references/report-templates/infra/vendor-report.md`.

### `cve-disclosure` (standalone, no responsive maintainer)

- For unmaintained crates or upstream dependencies where the vulnerability is severe but no responsive maintainer exists.
- Request CVE directly via MITRE; publish advisory on RustSec.
- Template: `references/report-templates/infra/cve-disclosure.md`.

### `generic-infra`

- Public GitHub issue or pull request with fix.
- No embargo.
- Template: `references/report-templates/infra/generic-infra.md`.

### `internal` (INFORMATIONAL severity only)

- Logged in `$RUN_DIR/5-disclosure/_internal-only.md`.
- No external submission. May still be addressed in routine maintenance.

## Component-scope classification

"Core protocol" vs "independent implementation" boundary depends on the user's audit context:

| Signal | Likely "core protocol" | Likely "independent implementation" |
|--------|------------------------|-------------------------------------|
| Crate name | `solana-runtime`, `polkadot-sdk-*`, `cometbft`, `lighthouse-*` | `my-fork-of-x`, vendor-specific patches |
| Repository owner | `solana-labs/`, `paritytech/`, `cosmos/` | individual / smaller-org GitHub orgs |
| Download count | >100K monthly (canonical) | <10K monthly |
| Stake-weighted usage | runs majority validator stake | runs minority/edge stake |

The orchestrator emits a `component_scope: core-protocol | independent-implementation | library-crate` classification with confidence; user reviews on borderline cases.

## Output

Stage 5 writes `$RUN_DIR/5-disclosure/F-NN.md`:

```markdown
# F-NN — Disclosure path selection (infra Stage 5)

- **final_severity**: <from Stage 4>
- **component_type**: <from Stage 1>
- **component_scope**: core-protocol | independent-implementation | library-crate
- **selected_path**: vendor-coordinated | vendor-report | cve-disclosure | generic-infra | internal
- **contact_details**:
  - **primary**: <security@... or maintainer GitHub>
  - **secondary**: <fallback contact, if any>
  - **public_advisory_channel**: <RustSec advisory, GitHub Security Advisory URL, etc.>
- **cve_recommended**: yes | no | optional
- **cve_decision_routed_to_stage6**: yes (always — Stage 6 makes the final CVE call)
- **embargo_duration**: <90 days | 60 days | n/a>
- **template_to_apply_at_stage_8**: references/report-templates/infra/<advisory|vendor-report|cve-disclosure|generic-infra>.md
```

This file feeds Stage 6 (CVE triage) and Stage 8 (report generation).

## Coordination with `audit-modes.md`

This file is loaded in `infra` mode only. In SC mode, Stage 5 reads `platform-validation.md` + the matching `platform-criteria/<platform>.md` for contest-platform AI-N rule evaluation.

The Cantina AI-3 manual-validation acknowledgment gate from SC mode does NOT apply in `infra` mode. AI-provenance for `infra` mode findings is governed by the vendor's own AI-disclosure policy (varies; some vendors require it, most do not yet). The Stage 8 infra report templates surface AI-provenance in the recommendations section regardless.
