# ai-web3-skills

A curated stack of **485 AI agent skills** for Web3 / smart-contract security auditing, assembled from 50+ open-source auditor toolkits. Each skill is a self-contained `SKILL.md` (plus supporting scripts/references) that an agent loads on demand. Packs are namespaced by `owner-repo` to keep same-named skills from different authors separate.

## Largest packs

| Pack | Skills | What it covers |
|------|-------:|----------------|
| `plamen/` | 145 | Multi-chain audit pipeline — EVM, Solana, Sui, Aptos, Soroban, plus L1 client / consensus auditing. |
| `trailofbits-skills-/` | 74 | Trail of Bits — fuzzing (AFL++, libFuzzer, cargo-fuzz, Atheris), per-chain vuln scanners, code-maturity, crypto/constant-time, Trailmark graphs, Semgrep/CodeQL. |
| `grimoire/` | 19 | Audit workflow — cartography, findings draft/review/dedup, PoC, librarian/scribe, sigil agents. |
| `auditmos-skills-/` | 14 | Pattern packs for lending, liquidation, oracle, staking, slippage, signatures, math precision. |
| `quillai-network-qs_skills-/` | 11 | Behavioral state analysis + threat engines (reentrancy, oracle/flashloan, proxy, signatures, invariants). |
| `context-skills/` (forefy) | 11 | smart-contract-audit, tiny-auditor, foundry-poc, blockchain-forensics, gdocs-audit-report. |
| `shuvonsec-claude-bug-bounty-/` | 10 | Full bug-bounty workflow (web2 + web3 + LLM/AI), recon, reporting. |
| `alt-research-solidityguard-/` | 10 | SolidityGuard — 104 vuln patterns, access control, DeFi, proxy, reporting. |
| `slvdev-weasel-/` | 9 | Weasel — analyze, explain, gas, filter, PoC, report, validate. |
| `openzeppelin-openzeppelin-skills-/` | 9 | Secure dev + setup/upgrade for Solidity, Cairo, Stylus, Stellar. |

Plus 37 more packs (Cyfrin solskill, ZeroSkills, cdsecurity, pashov, OpenZeppelin, Move auditors, nemesis/feynman, scv-scan, scoping-bee, K.I.T, drozer-lite, hackenproof, and the reference packs below).

## Reference skills (tools that run on the user's machine, not in the agent)

These document install/usage and how the agent assists — the tool itself runs locally:
`fuzzing-reference/` (ItyFuzz, AFL++, solidity-fuzzing-comparison), `gptscan-gptscan/`, `bradmoonuestc-finite-monkey-engine/`, `scabench-org-hound/`, `kaveyjoe-suizero/`, `cameronkarthik-base-audit-bot/`, `han-sec-trident-fuzz-skill/`, plus `reference/` (ai-auditor-primers, audit-report-examples).

## Dedup

Skills are deduplicated within each pack (nested `.claude/` self-copies and framework-variant duplicates removed). Same-named skills from *different* authors are intentionally kept — they're different implementations.

## Sources

pashov · PlamenTSV · zerocoolailabs · CDSecurity · forefy/.context · JoranHonig/grimoire · marchev/claudit · RASHMOR1/dlt-auditor · berabuddies (agentflow, Semia) · mattpocock · Cyfrin/solskill · quillai-network · kadenzipfel/scv-scan · Archethect · auditmos · KannAILabs · alt-research/SolidityGuard · Frankcastleauditor · sanbir · pantheraudits · trailofbits · 0xiehnnkta/nemesis · OpenZeppelin · Monethic · slvDev/weasel · hackenproof-public · shuvonsec · han-sec/trident · ZealynxSecurity/krait · konstantinvelev · galacticcouncil/hydration-node · DarkNavySecurity · kaveyjoe/SUIZERO · 0xRayaa/scoping-bee · cameronkarthik · BradMoonUESTC · scabench-org/hound · heavyw8t/The-Judge · 33Audits · gdroz3r/drozer-lite · cholakovvv · J4X-Security/K.I.T · zzzuhaibmohd · GPTScan · finite-monkey-engine · ityfuzz · AFLplusplus · devdacian (primers, fuzzing-comparison) · solodit

Each pack retains its original author's license. Refer to the upstream repositories for licensing terms.
