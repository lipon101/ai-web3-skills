---
name: base-audit-bot
description: Reference for Base Audit Bot, an autonomous agent that monitors Base mainnet for new contract deployments, finds their GitHub source, audits Solidity with Claude, and posts findings to Twitter. It's a deployable Python service (web3.py + SQLite + webhook server), NOT a Sauna skill. Use when the user wants to stand up automated Base deployment monitoring + auto-auditing, or asks how to configure/run it. Sauna helps deploy and configure it.
---

# Base Audit Bot (reference)

Autonomous bot that watches Base blockchain deployments, audits repos for smart-contract vulns, and posts to Twitter. Repo: https://github.com/cameronkarthik/base-audit-bot

## Important: deployable service, not a Sauna capability

This is a long-running Python service (scanner → GitHub finder → Claude auditor → Twitter + SQLite + webhook server). It runs on the user's host/server, not inside Sauna.

## Components

- **Scanner** (web3.py): scans Base mainnet for new contract deployments.
- **GitHub Finder**: locates source repos for verified contracts.
- **Auditor** (Claude): analyzes Solidity for vulnerabilities.
- **Twitter bot**: posts audit results.
- **Webhook server**: receives GitHub push events for monitored repos.
- **SQLite**: state/persistence.

## Usage

Follow the repo's Quick Start: set env vars (Base RPC, GitHub token, Anthropic key, Twitter API keys), install deps, run the service. 

## How Sauna assists

1. Help configure env vars and deploy the service.
2. Tune the audit prompt and severity gating.
3. Interpret/triage findings it surfaces. Pairs with `solidity-auditor` and `context-skills/foundry-poc` for deeper manual follow-up.
