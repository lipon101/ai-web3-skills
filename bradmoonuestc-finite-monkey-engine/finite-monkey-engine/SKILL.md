---
name: finite-monkey-engine
description: Reference for Finite Monkey Engine, an AI-driven security analysis pipeline (Planning -> Reasoning -> Validation) for auditing Solidity, Rust, C/C++, and Move code, persisting findings to PostgreSQL. It's a standalone platform the user runs locally, NOT inside Sauna. Use when the user wants to run a large-scale automated audit pipeline with Finite Monkey Engine, or asks how to set it up. Sauna helps install/configure and interpret exported reports.
---

# Finite Monkey Engine (reference)

AI security analysis pipeline for code auditing: **Planning → Reasoning → Validation**, with results persisted to PostgreSQL and exportable as reports. Repo: https://github.com/BradMoonUESTC/finite-monkey-engine

## Important: standalone platform, not a Sauna capability

This is a multi-component pipeline (Tree-sitter parsing, Codex CLI for business-flow extraction and scanning, PostgreSQL persistence). It runs on the user's infrastructure. Sauna helps configure it and interpret its output.

## Pipeline (v3.0)

- **Planning**: Tree-sitter function parsing + Codex CLI to extract business flows (Gi/Fi); tasks persisted as Fi × checklist (rule_key).
- **Reasoning**: Codex CLI scans `business_flow_code + prompt`, emitting multi-vulnerability JSON → `project_finding`.
- **Validation**: Codex confirms each `project_finding`, writing back `validation_status` / `validation_record`.
- Codex runs with `--cd <project_root>` from `src/dataset/agent-v1-c4/datasets.json`.

## Languages

Solidity, Rust, C/C++, Move (Go partial). 

## How Sauna assists

1. Help with setup: PostgreSQL, Codex CLI config, dataset registration (`datasets.json`).
2. Interpret exported reports and `project_finding` records.
3. Cross-reference with manual review skills (`smart-contract-audit`, Plamen) and draft final findings.
