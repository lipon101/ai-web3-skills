---
name: gptscan
description: Reference for GPTScan, a tool that combines GPT with static program analysis to detect logic vulnerabilities in Solidity smart contracts. GPTScan is a standalone Python+Java tool the user runs locally, NOT inside Sauna. Use when the user wants to run logic-vulnerability detection on a Solidity project with GPTScan, or asks how to install/configure it. Sauna helps install, run, and interpret the JSON output.
---

# GPTScan (reference)

Uses ChatGPT plus program-analysis logic to detect logic vulnerabilities in Solidity. Repo: https://github.com/GPTScan/GPTScan

## Important: standalone tool, not a Sauna capability

GPTScan runs locally (Python 3.10+ and Java 17+). It calls the OpenAI API with the user's own key. Sauna helps set it up and interpret results.

## Install & run

```bash
pip install -r requirements.txt           # Python 3.10+, Java 17+ also required
solc-select install 0.8.19 && solc-select use 0.8.19   # match the project's solc
python3.10 main.py -s /sourcecode -o /sourcecode/output.json -k OPENAI_API_KEY
```

- `-s` points to a **folder** (not a single file).
- `-o` is the JSON output path.
- Supports single-file-in-folder and common frameworks (Truffle, Hardhat, Brownie).

## How Sauna assists

1. Walk through install (solc-select version matching is the common snag).
2. Help structure the source folder GPTScan expects.
3. Parse `output.json`, triage flagged logic issues, and draft findings (pair with `grimoire/finding-draft` and `context-skills/foundry-poc`).
