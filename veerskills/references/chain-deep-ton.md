# Chain Deep-Dive: TON (FunC / Tact)

_Loaded when Phase 1.1 detects `.fc`, `.func`, or `.tact` files with `() recv_internal`, `receive()`, or `self.reply`. Sourced from ton-auditor-skills and WEB3-AUDIT-SKILLS ton-scanner._

---

## TON-Specific Attack Vectors (V236–V242)

**V236. Unbounced Message Fund Loss** — D: Contract sends message to non-existing or invalid contract without bounce flag. Funds sent with the message are permanently lost. Or bounce handler doesn't restore state — half-completed operation. FP: All inter-contract messages use `bounce: true`. Bounce handler properly reverses state changes and refunds.

**V237. Storage Fee Depletion Attack** — D: Attacker inflates contract storage (large cells/data) without paying proportional fees. Contract's balance erodes from storage fees. Eventually balance drops below minimum → contract frozen/destroyed → state lost. FP: Storage growth bounded per operation. Caller pays storage fee delta. Minimum balance maintained via admin top-up.

**V238. Message Ordering Assumption Violation** — D: Contract assumes messages arrive in send order. TON's asynchronous sharded architecture delivers messages out-of-order. Multi-step operations break when step 2 arrives before step 1. FP: Each message carries sequence number. Contract verifies order or handles reordering. State machine validates transitions regardless of arrival order.

**V239. Cell Depth/Size Overflow** — D: Data structure exceeds cell limits (1023 bits data, 4 references per cell, max 2^16 cells per message). Runtime error freezes contract or corrupts state. FP: Data structures designed within cell limits. Builder overflow checked before finalization. Pagination for large data.

**V240. External Message Replay Attack** — D: External message handler lacks replay protection. Attacker resubmits previously valid external message to re-execute the operation. FP: Monotonic `seqno` stored in contract state. Each external message includes `seqno` and increments on success.

**V241. Gas Forwarding Exhaustion** — D: Contract sends message with insufficient gas (TON_VALUE) attached. Receiving contract can't complete operation, but sending contract already committed state changes. Partial execution with inconsistent cross-contract state. FP: Gas estimation for `recv_internal` of target. Minimum forward gas enforced. Bounce handler reverts sender state on failure.

**V242. Tact Map Iteration Limitation** — D: Tact's `Map` type doesn't support iteration. Contract stores data in Map assuming it can enumerate entries later — impossible at runtime. Alternative: contract uses repeated `get` with guessed keys = gas bomb. FP: Data structure redesigned with explicit key tracking (separate array of keys). Access patterns don't require enumeration.

---

## TON Scanning Methodology

### Entry Point Discovery
```bash
# FunC entry points
grep -rn "recv_internal\|recv_external" --include="*.fc" --include="*.func"
# Tact entry points
grep -rn "receive(\|bounced(\|external(" --include="*.tact"
# Message handling
grep -rn "send_raw_message\|send\|self.reply\|self.forward\|self.notify" --include="*.tact" --include="*.fc"
# Storage operations
grep -rn "store_\|load_\|begin_cell\|end_cell\|begin_parse" --include="*.fc"
```

### TON-Specific Checks
- Every `recv_internal` validates sender address for privileged operations
- External message handlers have `seqno`-based replay protection
- All outgoing messages have adequate gas attached
- Bounce handlers properly reverse state changes
- Data structures designed within cell limits (1023 bits, 4 refs)
- Storage growth bounded to prevent depletion attacks
- Contract maintains minimum balance for storage fees
- Tact contracts don't rely on Map iteration
