# Example PoCs

These are reference files that Claude reads when generating your PoC. They pattern-match your finding's shape to a closest-match example and produce output in the same style.

You never need to modify, run, or adapt these files. The addresses are placeholders and the tests don't execute.

## Example_FreezeHistorical.t.sol

Category (a): the vulnerable state is already reached on-chain through block progression or a past action that cannot be replayed. Severity comes entirely from the existing frozen state.

The test forks at a post-vulnerable block, attempts recovery at the point it should be possible, and proves it reverts. Paired with a quantification of the stranded value.

## Example_RoutingDoS.t.sol

Category (b): adapter logic error produces DoS or fund stranding on every affected route. Severity comes from every future user being affected.

Two test functions. First proves the DoS with `vm.expectRevert`. Second proves fund stranding by showing attacker input is consumed, output is zero, and stranded balance appears on the adapter.

## Example_PoolDrainTheft.t.sol

Category (b): decimals mismatch enables share inflation and drain via a trivial deposit. Severity comes from every future depositor being at risk.

The admin whitelists the inflating token via the real permission path, attacker makes a trivial-value deposit, inflated shares are minted, attacker withdraws and receives a disproportionate amount of the pool's real principal. Proven with before/after balance delta on the attacker plus a pool-near-zero assertion.
