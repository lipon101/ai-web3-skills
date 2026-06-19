# foundry-poc-mainnet-fork

A [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) skill that turns a smart contract vulnerability finding into a submission-ready Foundry PoC that forks mainnet and exercises real deployed contracts end-to-end.

Built and validated by [@cholakovvv](https://x.com/cholakovvv) across four production bounty findings spanning freeze, routing DoS, and pool-drain theft shapes.

## What It Does

Given a vulnerability description and the deployed addresses of the affected protocol, the skill produces a single Foundry test file that:

- Forks mainnet (or any EVM chain) at a block where the bug is reachable
- Binds every protocol contract as a `constant` real address
- Executes the full causal chain from the action that first triggers the vulnerable state to the final realized impact
- Ends with assertions that encode the vulnerability's end-state (balance deltas for theft, reverts for DoS, quantified stranding for freeze)
- Passes `forge test -vvvv` on the first try, or flags a blocker with a concrete reason

No mocks. No minimal reimplementations. No `vm.store` shortcuts around protocol pipelines unless explicitly documented.

## Who This Is For

Smart contract security researchers working on bug bounty platforms or audits who want to produce a clean mainnet-fork PoC without spending 2 hours on boilerplate and address-hunting. The skill takes care of:

- Classification of the finding (frozen historical vs forward-looking risk vs both)
- Identifying the first-triggering action in the causal chain
- Finding real deployed addresses when the user provides partial info
- Writing interfaces that match deployed bytecode
- End-to-end test structure with labeled balance deltas

## Requirements

- Claude Code with a Claude Sonnet 4.5 or Claude Opus 4.5+ subscription (or API access)
- Foundry installed (`forge`, `cast`)
- An EVM RPC URL (free Alchemy, Infura, drpc.org, mevblocker.io all work)

## Installation

```bash
cd ~/.claude/skills
git clone https://github.com/cholakovvv/foundry-poc-mainnet-fork.git
```

Restart Claude Code or start a new conversation. Verify the skill loaded:

```
/skills
```

You should see `foundry-poc-mainnet-fork` in the list.

## Usage

In a Claude Code conversation with your audit/bounty repo as context, provide:

1. The full vulnerability description (root cause, attack path, expected impact)
2. The chain (ethereum, arbitrum, base, etc.)
3. A fork target (`latest` or a specific block number)
4. Real deployed addresses for every contract in the attack path, labeled by role

Example prompt:

```
Using the foundry-poc-mainnet-fork skill, write a PoC for this finding:

[paste finding]

Chain: ethereum
Fork: block 24900000
Addresses:
- Target protocol: 0x...
- Affected pool: 0x...
- Admin: 0x...
```

The skill will:

1. State the finding's classification out loud: "(a) frozen historical / (b) forward-looking / (a+b) both, because [signal]"
2. Name the starting actor, fork block, and causal chain
3. Write the test file and a `forge test` command
4. Provide a 2-3 sentence explanation of what the passing assertions prove

If inputs are missing or the skill cannot verify a required address is deployed on the target chain, it stops and tells you what's needed.

## About The Examples

The `examples/` folder contains three reference PoCs that Claude reads when generating your output. Each demonstrates a distinct bug shape the skill was validated against:

| File                             | Shape                                                                                    | Proof                                                                |
| -------------------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `Example_FreezeHistorical.t.sol` | Category (a): state reached by block progression alone                                   | Recovery attempt reverts; quantified stranding                       |
| `Example_RoutingDoS.t.sol`       | Category (b): adapter logic error produces DoS or fund stranding on every affected route | `vm.expectRevert` on DoS test; balance delta on stranding test       |
| `Example_PoolDrainTheft.t.sol`   | Category (b): decimals mismatch enables share inflation and drain                        | `assertGt(attackerAfter, attackerBefore)` + pool-near-zero assertion |

The addresses in these examples are placeholders and the files don't run. They exist so Claude can pattern-match your finding's shape to the closest example and produce output in the same style. You never need to modify or adapt them.

## What It Won't Do

- **Solana, Cosmos, Aptos, or any non-EVM chain.** Use a different tool.
- **Hardhat tests.** Foundry only.
- **Local-state unit tests.** The entire value of this skill is mainnet forking.
- **Fuzz or invariant harnesses.** These are a different genre.
- **Guess addresses.** If the skill can't verify a contract is deployed at the address you provided, it flags a blocker instead of guessing.
- **Bypass protocol pipelines.** If a protocol's logic requires an oracle callback or a real swap execution, the skill will not `vm.store` the post-state. It either routes through real contracts or documents the limitation.

## Known Limitations

- **Public RPC archive state.** Pinned block numbers require an RPC that retains historical state. Public RPCs vary. The skill tries drpc.org, mevblocker.io, and eth-pokt.nodies.app when publicnode or similar fail.
- **Hostile findings.** If the finding text is ambiguous or contradicts the addresses provided, the skill asks for clarification rather than guessing.
- **One shape per test file.** Multi-finding PoCs are out of scope. Each test file reproduces one finding.

## Validation

Validated on four shape-diverse production bounty findings:

- Freeze historical: rewarder timelock bug (Low severity, Remedy-closed)
- Routing DoS / fund stranding: adapter balance-of-wrong-token bug (Medium, Cantina)
- Pool drain / theft: decimals-mismatch share inflation (Critical, Remedy duplicate)
- Freeze forward-looking: orphaned reward pattern with timelock reset (High, Remedy-closed)

Each produced a submission-ready PoC with zero skill revisions on the third and fourth runs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

Briefly: rule changes require three independent failure cases, new examples require a distinct bug shape with validation evidence. Opinions without findings don't move the skill.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Built by [Simeon Cholakov](https://github.com/cholakovvv/), blockchain security researcher.

If this skill saves you time on a bounty, consider:

- Starring the repo
- Tagging me on X when you submit a PoC you built with it
