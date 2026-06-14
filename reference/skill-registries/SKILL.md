---
name: skill-registries
description: Reference for discovering more agent skills from external registries — forefy.com/skills (a community-audited Web3 auditor skill registry, GitHub-sourced with commit pinning) and Hermes Agent (hermes-agent.nousresearch.com, a 92k+ skill catalog across 12 registries, mostly general-purpose). Use when the user wants to find, browse, or pull in additional security-audit skills beyond what's already installed, or asks what other skills exist. Explains how to query forefy's API and dedupe against the installed stack.
---

# Skill Registries (reference)

Two external registries worth mining for more skills. Neither is a single repo — they aggregate GitHub-hosted skills.

## forefy.com/skills — Auditor Skills Registry

Community-audited registry focused on Web3 security auditing. Every entry is GitHub-sourced with commit pinning (supply-chain protection) and a guardrail/quality scan.

JSON API (no key):
```bash
# paginated list; each item has name, description, github_url, commit_sha, is_audited
curl -s "https://forefy.com/api/skills?page=1" | jq '.skills[] | {name, github_url, commit_sha}'
```
Total ~131 skills across 7 pages. To add new ones: collect `github_url`s, dedupe against the installed packs under `skills/personal-ZUp1aMpW/` (namespaced `owner-repo`), and install the repos not already present. Most of this registry is already installed in this workspace.

## Hermes Agent — hermes-agent.nousresearch.com/docs/skills

A very large catalog (92k+ skills across 12 registries), mostly general-purpose (productivity, design, ML, devtools) — only a small slice is Web3 security. It's a discovery surface / CLI, not a curated audit set. Browse it for one-off tools, but don't bulk-install; the web3 audit skills there are the same GitHub-sourced ones forefy tracks.

## How Sauna assists

1. Query forefy's API, diff against installed packs, and install genuinely new audit repos.
2. Pin to `commit_sha` when reproducibility matters.
3. Skip non-audit noise unless the user asks for it.
