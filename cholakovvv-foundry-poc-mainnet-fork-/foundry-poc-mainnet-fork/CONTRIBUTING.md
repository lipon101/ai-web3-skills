# Contributing

Thanks for the interest in improving this skill. Skills degrade fast when rules are added without evidence, so this project has a higher bar than most open-source repos for changes. Read this before filing an issue or PR.

## What I Want Contributions For

**Finding shapes the skill handles poorly.** If you ran the skill on a real finding and it produced something wrong (anchored on the wrong category, missed the causal chain, used a mock where it shouldn't have, wrote a test that passes but doesn't prove the bug), open an issue. This is the most valuable kind of feedback.

**Bugs in the examples.** If a reference example in `examples/` has a factual error, inconsistent style with the skill's rules, or an outdated pattern, open an issue or PR.

**Documentation gaps.** README unclear, installation instructions broken on your OS, usage examples don't match the skill's actual behavior, open an issue or PR.

**New bug shapes the skill hasn't been validated against.** If you've used the skill on a bug shape not covered by the existing examples (e.g., reentrancy exploitation, governance attack, MEV sandwiching), and it worked cleanly, consider contributing an anonymized reference PoC.

## What I Do Not Want

**Opinions without findings.** "I think the classification rule should be four categories instead of three" without a finding that exposed the gap doesn't move the skill.

**Style preferences.** The style rules (banned words, em-dashes, assertion message length) exist for specific reasons and are stable. Don't propose softening them without evidence that they cause harm.

**Adding support for Hardhat, Truffle, non-EVM chains, or local-state tests.** The skill is deliberately narrow. Wider scope means weaker guarantees. A fork is welcome if you want a different-scoped version.

**Commentary or wishlist-style issues.** Use X or Discord for those. Issues should be actionable.

## Filing An Issue

When the skill produces wrong output, include:

1. **The finding you gave it.** Anonymize protocol names if the finding is under embargo, but keep the structural details (bug category, impact type, causal chain length).
2. **The exact prompt you used.** Including the trigger phrase, whether you named the skill explicitly, what context files were in the conversation.
3. **The skill's output.** The full test file and the classification statement it produced before writing code.
4. **What you expected.** A description of what a correct PoC would have looked like. If you already wrote the correct version yourself, paste it.
5. **Skill version.** Check `SKILL.md` for the current state, or reference the commit hash you have installed.

Issues without these five items will be closed with a request to refile.

## Proposing A Rule Change

Rule changes to `SKILL.md` require:

1. **A concrete failure case.** A finding the skill handled wrong. One example is not enough for a rule change; three independent failures with the same root cause are the threshold.
2. **A proposed rule.** Phrased the way the rest of the skill is phrased. Short, specific, enforceable.
3. **A test plan.** How you verified the proposed rule fixes the failure cases without breaking the existing validation runs.
4. **Re-validation.** If the rule change is accepted, the skill's four validation findings must still produce clean output with the new rule in place. The maintainer or the contributor handles this.

Rule changes that don't follow this process will be closed.

## Proposing A New Example

New reference PoCs in `examples/` require:

1. **A distinct bug shape.** If the new example is structurally similar to an existing one, it's a duplicate and won't be merged. The existing four-shape coverage is a starting point; new shapes like reentrancy, governance, and MEV are welcome.
2. **Full anonymization.** Placeholder addresses in the same style as the existing examples (`address(0xN00M)` pattern). No real protocol addresses, no real bounty-platform report text, no real token names unless the token's properties (decimals, rebase behavior) are themselves the bug.
3. **Validation evidence.** A description of the original finding shape and the skill-produced PoC that matches this example's structure. The example must represent a real validated output, not an idealized template.
4. **A short `examples/README.md` entry.** Describing what category the example is, what bug shape it demonstrates, and what the proof shape is.

## Pull Request Process

1. Fork the repo.
2. Create a branch named after the issue you're addressing (e.g., `fix/classification-anchors-on-freeze` or `add-example/reentrancy`).
3. Make the change. Keep PRs focused; one rule change per PR, one example per PR.
4. Update `CHANGELOG.md` under an `[Unreleased]` heading with your change described in the same style as the existing entries.
5. Open the PR with a description that links to the issue it addresses.

PRs that bundle multiple unrelated changes will be asked to split. PRs that don't update the changelog will be asked to add the entry.

## Code Of Conduct

Be direct, specific, and actionable. Disagreement is fine; grandstanding is not. I close issues that turn into forum threads.

## Questions

Open a discussion on GitHub if you have a question that isn't an issue. X and DM are fine for quick clarifications but don't expect those to be tracked.

## Credits

Contributors who land merged PRs will be listed in the README credits section.
