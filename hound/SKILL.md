---
name: hound
description: Reference for Hound, a language-agnostic autonomous AI auditor that builds adaptive knowledge graphs for deep iterative code reasoning (scout vs strategist models, belief/hypothesis system). Hound is a standalone Python tool the user runs locally with their own LLM keys, NOT inside Sauna. Use when the user wants to run Hound's graph-driven autonomous audit on a codebase, or asks how to set it up/configure models. Sauna helps install, configure, and interpret its hypotheses/findings.
---

# Hound (reference)

Language-agnostic AI auditor that autonomously builds and refines adaptive knowledge graphs for deep, iterative code reasoning. Repo: https://github.com/scabench-org/hound (OpenAI / Gemini / Anthropic compatible).

## Important: standalone tool, not a Sauna capability

Hound is a Python tool (3.8+) that drives LLMs with the user's own API keys and runs long-horizon autonomous audits. It runs on the user's machine, not inside Sauna.

## Key concepts

- **Graph-driven analysis**: agent-designed graphs model architecture, access control, value flows, math, etc.
- **Relational graph views**: cross-aspect reasoning + precise retrieval of backing code.
- **Belief & hypothesis system**: observations/assumptions/hypotheses evolve with confidence scores for cumulative audits.
- **Dynamic model switching**: lightweight "scout" models explore; heavyweight "strategist" models reason deeply.
- **Strategic planning**: balances broad coverage with focused investigation.

## Usage

Follow the repo README: configure models/keys, run the audit workflow against a target repo, then use the chatbot/telemetry UI to inspect hypotheses. 

## How Sauna assists

1. Help configure models, keys, and the project under audit.
2. Interpret Hound's hypotheses and confidence scores; separate signal from noise.
3. Turn confirmed hypotheses into structured findings (pair with `grimoire/finding-draft`, `context-skills/foundry-poc`).
