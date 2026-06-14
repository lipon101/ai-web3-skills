# Pull Request

## Type of change

- [ ] New attack vector (`references/attack-vectors/rust-attack-vectors.md`)
- [ ] New / improved hacking angle (`references/hacking-agents/`)
- [ ] New / updated platform criteria (`references/platform-criteria/`)
- [ ] Stage contract / pipeline change (`references/pipeline-overview.md`)
- [ ] New benchmark (`evals/benchmarks/`)
- [ ] Bug fix
- [ ] Documentation update
- [ ] Other (describe)

## Summary

<!-- 2-4 sentences: what does this PR do and why? Cite the stage / angle / reference touched. -->

## Changes

<!-- Bullet list of what changed. -->
-
-

## Stage impact

<!-- If this PR changes the contract of a stage, describe what changed about INPUT / OPERATIONS / OUTPUT / VERDICT / KILL CRITERIA / EXIT CONDITION. Otherwise write "no stage-contract change". -->

## Severity discipline

<!-- If this PR touches Stage 4 Pass D (severity calibrator) or any platform-criteria severity definitions, describe whether the change can UPGRADE or only DOWNGRADE severity, and whether existing finding outputs would be re-graded. -->

## Testing

<!-- How did you test? Paste a representative input/output pair if applicable. -->

**Input:**
```
```

**Output:**
```
```

## Checklist

- [ ] No API keys, tokens, secrets, or personal data
- [ ] No fabricated examples — outputs reflect real model responses on real Rust code
- [ ] `CHANGELOG.md` updated under the current version section
- [ ] If Stage 2 attack-vector added: next-available `Vn` ID used; Vector Scan classification block expectations match
- [ ] If hacking angle changed: `SKILL.md` Stage 2 dispatch table reflects the change
- [ ] If platform criteria added/changed: `platform-validation.md` URL routing table updated
- [ ] Skill works with Claude Code CLI, VS Code, Cursor, and the OpenAI agent definition (`agents/openai.yaml`)
