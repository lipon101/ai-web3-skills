# ZK Framework Constraint Surface — Under-Constraint API Catalog

> **Purpose**: Document the "surface area for under-constraint" in every major ZK proving system framework. For each framework, catalog every API call that assigns a witness value WITHOUT creating a constraint, and every counterpart that DOES create a constraint. This is the operational handbook for CHECK 1 ("Is the cell computed or assigned?") in the ZK Circuit Soundness agent across frameworks.
> **Compiled**: 2026-06-05 from framework documentation (docs.rs + Halo2 book + READMEs + Circom docs), the Orchard post-mortem (vul.md), and the Circomspect analysis passes.
> **Status**: Halo2, arkworks, Bellman/Bellpepper, Plonky2 — complete. Plonky3 marked [INCOMPLETE] (no detailed API docs publicly available).

---

## 1. Halo2 (zcash/halo2, halo2_proofs 0.3.x)

### 1.1 API Surface Table

All methods below are on `Region<'r, F: Field>` unless noted.

| Method | Creates Constraint? | Correct Use Case | Misuse Pattern (Orchard-equivalent) |
|--------|--------------------|------------------|--------------------------------------|
| `assign_advice(annotation, column, offset, value)` | **NO** | Assign witness value that is later constrained by a gate in the same region, or by `constrain_equal` to another region. | Assigned value is never read by any gate and never equality-constrained to any other cell. The exact Orchard bug. |
| `assign_advice_from_constant(annotation, column, offset, constant)` | **NO** | Copy a compile-time constant into an advice cell for gate consumption. The constant itself is in a fixed column (enabled via `ConstraintSystem::enable_constant`), so it is inherently knowledge-zero — but the ASSIGNMENT to the advice cell is not constrained unless a gate reads it. | Assigned constant that no gate reads. Lower severity than `assign_advice` — the prover can still set it to anything, but the constant was public knowledge anyway. |
| `assign_advice_from_instance(annotation, instance_column, row, advice_column, offset)` | **NO** | Bridge a public input (instance column) into an advice cell for gate consumption. | The instance value IS copied to the advice cell, but without a subsequent gate that reads and constrains it relative to other witnesses, the prover can set the advice cell independently and the circuit will only check equality to the instance AFTER the fact. **Mitigation**: the copy creates a permutation check tying the advice cell to the instance column, so the value IS at least equal to the instance. The gap is when the instance itself is wrong for the intended computation. |
| `instance_value(instance_column, row)` | **NO** | Convenience read of an instance column value. Docs explicitly state "does not create any constraints." | Reading an instance value without corresponding `assign_advice_from_instance` + gate constraint. |
| `assign_fixed(annotation, column, offset, value)` | **NO** | Place a value in a fixed column. Fixed columns are known to both prover and verifier and are set during key generation. | **Fixed columns are known to the verifier**: The verifier knows the fixed column assignment from the verifying key. However, the circuit's gates define HOW fixed columns interact with advice columns. If no gate reads a fixed column cell, the fixed value is present but unused — not a soundness issue by itself, but a spec gap. |
| `constrain_constant(cell, constant)` | **YES** | Ensure a cell equals a specific constant. Uses permutation argument. | **[SAFE]** Directly constrains the cell. |
| `constrain_equal(left_cell, right_cell)` | **YES** | Ensure two cells are equal. Uses permutation argument. Correct cross-region binding. | **[SAFE]** This is how cross-region equality is enforced. The Orchard fix used `copy_advice` which internally creates this constraint. |

**Key architectural note**: Halo2 does NOT have a `copy_advice` method on `Region`. The Orchard fix's `copy_advice(|| label, column, offset, source_column, source_row, || value)` is a convenience method available on `Layouter::assign_region` or as a free function that internally calls `region.constrain_equal()`. The Region struct only exposes `constrain_equal` directly. When auditing Halo2 code, the detection recipe must catch BOTH the `assign_advice` call AND the absence of a subsequent `constrain_equal` to the actual input.

### 1.2. Detection Recipe

```bash
# Find all assign_advice calls (NOT assign_advice_from_instance, NOT assign_advice_from_constant)
grep -rn 'assign_advice(' --include='*.rs' circuits/ gadgets/ chips/
```

For EACH match:
1. Check if a gate in the same region reads this column at this offset. Look for: (a) The `create_gate` / `create_gate_with_constraints` closure that defines the gate's polynomial; (b) whether the gate's `query_advice` / `query_fixed` / `query_instance` references include `column` and `offset` or a rotation that covers it.
2. If no gate reads it, check for `constrain_equal` (or higher-level `copy_advice`) that links this cell to another region.
3. **Loop-specific**: If the `assign_advice` is in the first iteration of a loop, the loop's internal-consistency constraints (e.g., `q_mul_2` in Orchard) keep ALL iterations consistent with each OTHER, but NOT with the actual input. This is the highest-signal pattern.

```bash
# Find all copy_advice calls (for verification that they target the CORRECT source cell)
grep -rn 'copy_advice(' --include='*.rs' circuits/ gadgets/ chips/

# Find all constrain_equal calls (what cells are linked?)
grep -rn 'constrain_equal(' --include='*.rs' circuits/ gadgets/ chips/
```

**High-signal structural patterns to examine**:
- `impl Circuit<F>` blocks: the `configure()` method defines gates; the `synthesize()` method assigns cells. Audit that every cell assigned in `synthesize()` is read by at least one gate defined in `configure()`.
- `create_gate` closures: enumerate the `query_advice` / `query_fixed` / `query_instance` calls to build the full set of columns referenced by the gate.
- Custom gates with selectors: a gate enabled by a selector `s` that the prover controls. Check if the selector can be set to omit a constraint branch.

### 1.3. Orchard-Equivalent Scenario

```rust
// VULNERABLE: The exact Orchard pattern (simplified)
// Incomplete addition stage, first iteration:
region.assign_advice(|| "x_p", config.x_p, row + offset, || x_p_value)?;
region.assign_advice(|| "y_p", config.y_p, row + offset, || y_p_value)?;

// The q_mul_2 gate constrains ALL iterations to use the same base point:
//    q_mul_2 * (x_p_i - x_p_{i+1}) = 0
//    q_mul_2 * (y_p_i - y_p_{i+1}) = 0
// But nothing constrains x_p_0 and y_p_0 to equal the actual input g_d.

// FIX:
// In iteration 0, replace assign_advice with:
region.constrain_equal(
    Cell::new(config.x_p, row + offset),
    Cell::new(input_x_p_column, input_x_p_row),
)?;
// Then assign the value anyway:
region.assign_advice(|| "x_p", config.x_p, row + offset, || x_p_value)?;
// constrain_equal creates the permutation argument; the value can still be assigned.
```

---

## 2. arkworks R1CS (`ark-relations` 0.4.x, `ark-r1cs-std`)

### 2.1 API Surface Table

All methods are on `ConstraintSystem<F>` or `ConstraintSystemRef<F>`.

| Method | Creates Constraint? | Correct Use Case | Misuse Pattern |
|--------|--------------------|------------------|---------------|
| `new_witness_variable(fn -> F)` | **NO** | Allocate a private witness. The return value is a `Variable` handle that can be referenced in linear combinations for subsequent `enforce_constraint` calls. | Allocated variable never used in any `enforce_constraint`. This is the arkworks equivalent of the Orchard bug. |
| `new_input_variable(fn -> F)` | **NO** | Allocate a public input variable. The variable is indexable as an instance variable. | Allocated public input never constrained relative to witnesses. The public input EXISTS in the instance, but if no constraint relates it to witness values, the prover can supply any matching witness. |
| `new_lc(LinearCombination<F>)` | **NO** | Create a symbolic variable for an existing linear combination of variables. Used to inline expressions. The underlying variables are already constrained (or should be). | Linear combination of unconstrained variables. The variable itself inherits whatever constraints its constituents have. |
| `enforce_constraint(a: LC<F>, b: LC<F>, c: LC<F>)` | **YES** | Enforce `⟨a, z⟩ ⋅ ⟨b, z⟩ = ⟨c, z⟩` — the canonical R1CS constraint. Every allocated witness variable MUST appear in at least one `enforce_constraint`. | **[SAFE]** This is the only way to add a constraint in arkworks. |
| `zero()` | **NO** | Returns a `Variable` representing the constant zero. | N/A — constant variable, no constraint needed. |
| `one()` | **NO** | Returns a `Variable` representing the constant one. | N/A — constant variable, no constraint needed. |
| `is_satisfied()` | **NO** | Check if all constraints hold. Useful for testing/Debug. | N/A |
| `num_constraints()` | **NO** | Inspect constraint count. | N/A |
| `num_instance_variables()` | **NO** | Inspect public input count. | N/A |
| `num_witness_variables()` | **NO** | Inspect witness count. | N/A |
| `assigned_value(var)` | **NO** | Read the assignment of a variable. | N/A |

**Key architectural note**: There is NO `enforce_equal` method in arkworks. To enforce `var_a == var_b`, you construct:
```rust
cs.enforce_constraint(
    lc!() + var_a - var_b,  // a: 1*var_a + (-1)*var_b
    lc!() + (F::one(), CS::one()),  // b: constant 1
    lc!(),  // c: 0
)?;
// This enforces (var_a - var_b) * 1 = 0, i.e., var_a == var_b
```
The `lc!()` macro produces an empty linear combination.

**Naming discrepancy**: Older arkworks code may use `alloc` / `alloc_input` / `enforce` — these were renamed to `new_witness_variable` / `new_input_variable` / `enforce_constraint` in v0.4.0. Production codebases (e.g., Penumbra, Aleo snarkVM) may still use the old names depending on their pinned arkworks version.

### 2.2. Detection Recipe

```bash
# Find all witness variable allocations
grep -rn 'new_witness_variable\|\.alloc(' --include='*.rs'

# Find all public input allocations
grep -rn 'new_input_variable\|\.alloc_input(' --include='*.rs'

# Find all constraint enforcements
grep -rn 'enforce_constraint\|\.enforce(' --include='*.rs'

# Find enforce_equal patterns (manual construction)
grep -rn 'enforce_equal\|enforce_constraint.*Var.*one.*zero\|enforce_constraint.*-\|enforce_constraint.*=='
```

**Automated verification approach**:
1. Collect all `Variable` handles returned by `new_witness_variable` / `new_input_variable`.
2. Collect all `Variable` handles that appear in any `enforce_constraint` call (directly or via linear combinations).
3. **Subtract**: any variable in set (1) but not in set (2) is UNCENTERED. It is allocated but never constrained.
4. This is trivially automatable with a Rust visitor/lint, unlike Halo2 where gate-read analysis requires understanding the gate's polynomial.

**High-signal patterns**:
- `new_witness_variable` in a loop where the loop body's `enforce_constraint` only constrains iteration-to-iteration consistency, not the first iteration to the actual input (same CC-6 pattern as Orchard).
- `new_lc` of an unconstrained variable → creates an ALIAS that still flows into constraints, but the value is prover-chosen.
- Any `Variable` returned from a gadget function that the caller does NOT pass to `enforce_constraint` → the gadget's internal constraints are sufficient only if the consumer fully constrains the return value.

### 2.3. Orchard-Equivalent Scenario

```rust
// VULNERABLE: arkworks equivalent of the Orchard bug
fn synthesize<CS: ConstraintSystem<F>>(cs: &mut CS) -> Result<(), SynthesisError> {
    // Allocate the base point (private witness — PROVER SUPPLIES)
    let g_d_x = cs.new_witness_variable(|| Ok(g_d_x_value))?;
    let g_d_y = cs.new_witness_variable(|| Ok(g_d_y_value))?;
    let g_d = (g_d_x, g_d_y);

    // Allocate the scalar (private witness)
    let scalar = cs.new_witness_variable(|| Ok(ivk_value))?;

    // Run the double-and-add loop
    let mut acc = identity;
    let base = g_d; // FIRST ITERATION USES THIS
    for bit in scalar_bits {
        if bit { acc = acc + base; } // constrained by add gadget
        base = base.double();        // constrained by double gadget
    }

    // BUG: Nothing constrains that 'base' in iteration 0 equals g_d.
    //      The loop's internal add/double constraints only prove that
    //      each iteration is correct relative to the PREVIOUS iteration.
    //      A prover sets g_d to an arbitrary point P, and the loop
    //      computes [ivk']P correctly. The result passes any check
    //      that only looks at the final output.

    // FIX: Add an explicit equality constraint:
    // cs.enforce_constraint(
    //     lc!() + base_iter0_x - g_d_x,
    //     lc!() + (F::one(), CS::one()),
    //     lc!()
    // )?;
}
```

---

## 3. Bellman / Bellpepper (`bellpepper_core` trait)

### 3.1 API Surface Table

The `ConstraintSystem<F>` trait in `bellpepper_core`. Implementations: `bellman::ConstraintSystem` (original Zcash), `bellpepper::ConstraintSystem` (fork), `nova-snark::ConstraintSystem` (Nova folding).

| Method | Creates Constraint? | Correct Use Case | Misuse Pattern |
|--------|--------------------|------------------|---------------|
| `alloc(ns, assignment)` | **NO** | Allocate a private witness variable. Returns a `Variable`. The `assignment` is `Option<F>` — `Some(x)` during proving, `None` during verification. | Allocated variable never used in any `enforce` call. The Bellman equivalent of the Orchard bug. |
| `alloc_input(ns, assignment)` | **NO** | Allocate a public input variable. Returns a `Variable`. Same `Option<F>` semantics as `alloc`. | Public input allocated but never constrained relative to witnesses. |
| `enforce(ns, a: LC<F>, b: LC<F>, c: LC<F>)` | **YES** | Enforce `⟨a, z⟩ ⋅ ⟨b, z⟩ = ⟨c, z⟩` (rank-1 constraint). Every allocated `Variable` MUST appear in at least one `enforce` call's linear combinations. | **[SAFE]** The only way to add a constraint. |
| `one()` | **NO** | Returns a `Variable` representing the constant 1. | N/A |
| `push_namespace(ns)` / `pop_namespace()` | **NO** | Hierarchical naming for constraint tracing. | N/A |
| `get_root()` | **NO** | Returns the root `ConstraintSystem`, bypassing namespace indirection. | N/A |
| `is_witness_generator()` | **NO** | Query whether this instance is witness-only (no constraints). | N/A |
| `is_extensible()` | **NO** | Query whether `extend` is specialized. | N/A |
| `extend(other)` | **NO** | Merge another CS into this one. | N/A |
| `extend_inputs(scalars)` | **NO** | Witness-generator only. Extends public input scalars. | N/A |
| `extend_aux(scalars)` | **NO** | Witness-generator only. Extends auxiliary (private) witness scalars. | N/A |

**Key architectural note**: Like arkworks, Bellman does NOT have a built-in `enforce_equal`. Workarounds:
1. Manually construct `enforce(ns, a - b, CS::one(), lc!())` — enforces `(a-b) * 1 = 0`.
2. Use `AllocatedNum::equals(other)` from `bellman::gadgets` or equivalent from `bellpepper::gadgets`.

The `is_witness_generator` split is significant: `bellpepper` supports a mode where constraints are NOT generated, only witness values are recorded. This is used for witness-only computation (e.g., Nova folding scheme's secondary circuit). **If code accidentally runs in witness-generator mode when constraint generation is needed, ALL constraints are silently skipped.**

Bellpepper's `alloc` has different semantics from Halo2's `assign_advice` in one critical way: in Bellman, the `alloc` closure MUST match the variable's value when `enforce` is called. The constraint is on the variable's USAGE in `enforce`, not on its allocation. This is exactly the same risk model as arkworks.

### 3.2. Detection Recipe

```bash
# Find all variable allocations
grep -rn '\.alloc(' --include='*.rs'  # catches both alloc and alloc_input
grep -rn '\.alloc_input(' --include='*.rs'

# Find all constraint enforcements
grep -rn '\.enforce(' --include='*.rs'

# Find enforce_equal gadget usage
grep -rn 'equals\|enforce_equal\|constrain_equal' --include='*.rs'

# CRITICAL: Find witness-generator mode that might skip constraint generation
grep -rn 'is_witness_generator\|WitnessGenerator\|extend_inputs\|extend_aux' --include='*.rs'
```

**Automated verification approach** (same as arkworks):
1. Collect all `Variable` handles from `alloc` / `alloc_input`.
2. Collect all `Variable` handles appearing in any `enforce` call's `LinearCombination`.
3. Unconstrained = set(1) - set(2).

**High-signal structural patterns**:
- **Nova folding circuits**: The secondary circuit often uses `is_witness_generator()` to skip constraint generation. Verify that the primary circuit generates all constraints.
- **`alloc` in `ConstraintSynthesizer` without later `enforce`**: The Bellman `Circuit` trait's `synthesize` method receives `&mut CS`. Every `alloc` call must have a corresponding `enforce` that includes the variable.
- **Bellman gadgets ported from Zcash**: Many of these have been audited (Sapling circuit), but ports may have copy-paste errors where a gadget's output variable is not equality-constrained to the consumer's expected input.

### 3.3. Orchard-Equivalent Scenario

```rust
// VULNERABLE: Bellman equivalent of the Orchard bug
fn synthesize<CS: ConstraintSystem<F>>(cs: &mut CS) -> Result<(), SynthesisError> {
    // Allocate the base point (NO CONSTRAINT)
    let g_d_x = cs.alloc(|| "g_d.x", || Ok(g_d_x_value))?;
    let g_d_y = cs.alloc(|| "g_d.y", || Ok(g_d_y_value))?;

    let scalar = cs.alloc(|| "scalar", || Ok(ivk_value))?;

    // Double-and-add loop allocates internal variables and enforces
    // internal consistency constraints.
    // BUG: No enforce() call includes g_d_x or g_d_y.
    // Result: prover chooses g_d freely.

    // FIX: Ensure g_d_x and g_d_y appear in enforce() calls, or add
    // explicit equality: enforce(ns, base_iter0_x - g_d_x, CS::one(), lc!())
}
```

---

## 4. Plonky2 (Polygon Zero, v0.2.x)

### 4.1 API Surface Table

All methods on `CircuitBuilder<F, D>`.

#### Virtual Targets (ALLOCATE only — NO constraint)

| Method | Creates Constraint? | Note |
|--------|--------------------|------|
| `add_virtual_target()` | **NO** | "Not an actual wire in the witness, but just a target that helps facilitate witness generation." The exact Plonky2 equivalent of Halo2's `assign_advice`. |
| `add_virtual_targets(n)` | **NO** | Batch of `n` targets. |
| `add_virtual_target_arr<N>()` | **NO** | Const-generic array. |
| `add_virtual_hash()` | **NO** | `HashOutTarget` — 4 field elements. |
| `add_virtual_hashes(n)` | **NO** | `n` hash outputs. |
| `add_virtual_cap(cap_height)` | **NO** | `MerkleCapTarget`. |
| `add_virtual_extension_target()` | **NO** | Extension field element. |
| `add_virtual_extension_targets(n)` | **NO** | Batch. |
| `add_virtual_bool_target_unsafe()` | **NO** | **Bool without range check.** Prover can assign any field element. Use `add_virtual_bool_target_safe()` instead. |
| `add_virtual_verifier_data()` | **NO** | Recursive proof verifier data. |
| `add_virtual_fri_proof()` | **NO** | FRI proof target. |
| `add_virtual_proof_with_pis()` | **NO** | Proof + public inputs. |
| `add_virtual_public_input()` | **NO** | Virtual target + registers as public input via `register_public_input`. Does NOT create a constraint — the "public" status is a registration, not a constraint. |
| `constant(value)` | **NO** | Returns a `Target` holding a known constant. No constraint because the value is already fixed. |
| `zero()`, `one()`, `two()`, `neg_one()` | **NO** | Constant wires. |
| `_true()`, `_false()` | **NO** | Constant `BoolTarget`s. |

#### Gates (CREATE constraints)

| Method | Creates Constraint? | Note |
|--------|--------------------|------|
| `add_gate(gate_type, constants)` | **YES** | Registers a custom gate. The gate's `eval` method defines the polynomial constraint. |
| `add_gate_to_gate_set(gate)` | **NO** | Registers gate type metadata for conditional recursion. Does not add a concrete gate. |
| All arithmetic (`add`, `sub`, `mul`, `mul_add`, `square`, `cube`, `div`, `inverse`, `exp*`, `not`, `and`, `or`, `_if`, `select*`, `is_equal`) | **YES** | These delegate to gate allocations internally. |
| `range_check(target, n_log)` | **YES** | Constrains `target < 2^n_log`. |
| `split_le`, `split_le_base`, `split_low_high`, `low_bits`, `le_sum` | **YES** | Bit decomposition using `BaseSum` gates. |
| `assert_bool(target)` | **YES** | Constrains target to be boolean. |
| `assert_zero(target)` | **YES** | Constrains target = 0 via permutation. |
| `assert_one(target)` | **YES** | Constrains target = 1 via permutation. |

#### Copy Constraints (CREATE constraints)

| Method | Creates Constraint? | Note |
|--------|--------------------|------|
| `connect(x, y)` | **YES** | "Uses Plonk's permutation argument to require that two elements be equal." The Plonky2 equivalent of Halo2's `constrain_equal`. |
| `connect_extension`, `connect_hashes`, `connect_merkle_caps`, `connect_verifier_data` | **YES** | Batch connect for structured types. |
| `generate_copy(src, dst)` | **NO** | **Witness-level copy, not a constraint.** This adds a generator that copies `src` to `dst` during witness generation, but does NOT enforce equality in the circuit. This is a potential footgun — if the developer uses `generate_copy` expecting it to constrain, the equality is purely at the witness level and the prover can violate it. |

#### Lookup Tables (DEFERRED constraints)

| Method | Creates Constraint? | Note |
|--------|--------------------|------|
| `add_lookup_table_from_pairs(table)` | **NO** | Registers table metadata. |
| `add_lookup_from_index(in, lut_idx)` | **DEFERRED** | Adds a lookup pair. Constraint is only created when `add_all_lookups()` is called. |
| `update_lookups(in, out, lut_idx)` | **DEFERRED** | Same deferred model. |
| `add_all_lookups()` | **YES** | Materializes all deferred lookups as `LookupTableGate` + `LookupGate`. |
| `add_lookup_rows()` | **YES** | Adds rows for the lookup argument. |

#### Hashing / Merkle / Recursive Verification (CREATE constraints)

| Method | Creates Constraint? |
|--------|--------------------|
| `hash_or_noop`, `hash_n_to_hash_no_pad`, `hash_n_to_m_no_pad`, `permute` | **YES** |
| `verify_merkle_proof`, `verify_merkle_proof_to_cap` | **YES** |
| `verify_fri_proof`, `verify_fri_proof_with_multiple_degree_bits` | **YES** |
| `verify_proof`, `conditionally_verify_proof`, `conditionally_verify_proof_or_dummy`, `conditionally_verify_cyclic_proof*` | **YES** |

### 4.2 Detection Recipe

```bash
# Find ALL virtual target allocations (the Plonky2 equivalent of assign_advice)
grep -rn 'add_virtual_target\b' --include='*.rs'
grep -rn 'add_virtual_bool_target_unsafe' --include='*.rs'  # UNCONSTRAINED bool

# Find all connect calls (constrain_equal equivalent)
grep -rn '\.connect(' --include='*.rs'

# CRITICAL: generate_copy does NOT constrain
grep -rn 'generate_copy' --include='*.rs'

# Find all add_gate calls
grep -rn 'add_gate(' --include='*.rs'

# Find missing add_all_lookups (deferred lookups never materialized)
grep -rn 'add_lookup_from_index\|update_lookups' --include='*.rs'
grep -rn 'add_all_lookups' --include='*.rs'  # must be present if lookups are used
```

**High-signal structural patterns**:
1. **`add_virtual_target` without subsequent `connect` or gate**: The exact Plonky2 Orchard-equivalent.
2. **`add_virtual_bool_target_unsafe`**: Prover can assign any field element as a "bool." Use `add_virtual_bool_target_safe` instead.
3. **`generate_copy` used as if it were `connect`**: Witness-level copy only; no permutation constraint.
4. **`add_lookup_from_index` without `add_all_lookups`**: Lookups are deferred — if `add_all_lookups` is never called, the lookups are NEVER constrained.
5. **`add_gate` with selector conditions**: A custom gate whose `eval` method returns 0 for certain selector values, effectively skipping the constraint. Check if the prover controls the selector.

### 4.3. Orchard-Equivalent Scenario

```rust
// VULNERABLE: Plonky2 equivalent of the Orchard bug
fn build_ec_mul<F: RichField + Extendable<D>, const D: usize>(
    builder: &mut CircuitBuilder<F, D>,
    g_d: AffinePointTarget<F, D>,    // ACTUAL input (already constrained)
    scalar_bits: &[BoolTarget],      // bits of ivk (already constrained)
) {
    // BUG: Allocate the base point as a VIRTUAL target
    // This is equivalent to Halo2's assign_advice
    let x_p = builder.add_virtual_target();  // NO CONSTRAINT
    let y_p = builder.add_virtual_target();  // NO CONSTRAINT

    // Double-and-add loop uses x_p, y_p as the base
    let mut acc_x = builder.zero();
    let mut acc_y = builder.zero();
    let mut base_x = x_p;
    let mut base_y = y_p;

    for bit in scalar_bits {
        // Internal add/double constraints enforce correctness
        // relative to the PREVIOUS iteration's base values.
        // Nothing connects x_p, y_p to g_d.x, g_d.y.
    }

    // FIX: Replace the virtual target allocation with connect:
    // let x_p = g_d.x;  // reuse the constrained target
    // let y_p = g_d.y;
    // Or after allocating virtual, add:
    // builder.connect(x_p, g_d.x);
    // builder.connect(y_p, g_d.y);
}
```

---

## 5. Circom (Rust host perspective)

### 5.1 Signal Model and Constraints

Circom's constraint model is structurally different from the frameworks above. Rather than an explicit API where some calls allocate and others constrain, Circom's **operators** determine whether a constraint is created.

| Operator | What It Does | Creates Constraint? |
|----------|-------------|---------------------|
| `<==` (double arrow) | Assigns RHS to signal AND adds constraint: `signal === expression` | **YES** |
| `==>` (double arrow, reverse) | Same as `<==` but reversed: `expression === signal` | **YES** |
| `<--` (single arrow) | Assigns RHS to signal, NO constraint added | **NO — DANGEROUS** |
| `-->` (single arrow, reverse) | Same as `<--` but reversed | **NO — DANGEROUS** |
| `===` (equality constraint) | Adds constraint: LHS === RHS, without assignment | **YES** |

**Key structural safety**: In Circom, every signal appearing in the RHS of `<==` or `==>` IS automatically part of a constraint. The `signal` declaration (input/output/intermediate) is purely a scoping and visibility declaration — it does not allocate anything at the constraint level. The constraint system is built from the `<==` and `===` statements, not from signal declarations.

**Where Circom can still be under-constrained**: The `<--` operator. This assigns a signal WITHOUT a constraint. It exists because some computations (bitwise shifts, non-deterministic witness generation) cannot be expressed as quadratic constraints. The pattern requires explicit `===` constraints afterward.

### 5.2 Circomspect Under-Constraint Detection Rules

From the Trail of Bits Circomspect static analyzer (`doc/analysis_passes.md`):

| # | Rule | What It Detects | Severity | Detection Signal |
|---|------|-----------------|----------|-----------------|
| 1 | **Under-constrained signal** | An intermediate signal that appears in exactly ONE constraint. Single-constraint intermediates are suspicious because no other constraint pins them. | High | `signal` used in exactly 1 `<==` or `===` context |
| 2 | **`<--` where `<==` would work** | `<--` used with a quadratic RHS — meaning `<==` could have been used. The developer chose the unsafe operator unnecessarily. | High | `<--` with RHS containing only `+`, `*`, constants |
| 3 | **Unused output signal** | An instantiated template's output signal never constrained by the parent. The compiler won't warn; the signal is effectively free for the prover. | High | Template output signal present but never in parent's `<==`/`===` |
| 4 | **Unconstrained division** | `c <-- a / b; c * b === a;` without proving `b != 0`. When `b = 0`, the constraint `c * 0 = a` holds for any `c`, making `c` unconstrained. | High | Pattern: `<--` division followed by `===` with no `IsZero` check |
| 5 | **Unconstrained `LessThan`** | `LessThan` used without constraining inputs to `< log(p) - 1` bits. Field elements larger than this can be negative when normalized, breaking the comparison. | Medium | `LessThan()` call without `Num2Bits()` on inputs |
| 6 | **Non-strict binary conversion** | `Num2Bits` or `Bits2Num` with input size not strictly less than prime bit-length. Multiple binary representations exist for the same field element. | Medium | `Num2Bits(n)` where `n` >= field bit-length |

Additional code quality rules that can mask constraint bugs:
- **Tag 7: Side-effect free assignment** — assigned value never contributes to a constraint or return value. Effectively dead witness code.
- **Tag 8: Shadowing variable** — `var` shadowing, which can cause a reassignment to silently create a new variable instead of updating the intended one.
- **Tag 9: Constant branching condition** — branch always true/false, potentially dead code hiding missing constraints.
- **Tag 13 (BN254 specific circuit)**: 19 specific Circomlib templates that hardcode BN254 constants and are incompatible with Goldilocks or BLS12-381.

### 5.3 Detection Recipe

```bash
# Find ALL single-arrow assignments (under-constraint candidates)
grep -rn '<\-\-' --include='*.circom'
grep -rn '\-\->' --include='*.circom'

# For each <--, check if followed by === constraining the signal
# If <-- appears without subsequent === for the same signal → HIGH RISK

# Find single-constraint intermediates
# (Requires dataflow — count === and <== RHS occurrences per signal)

# Find division with <-- (unconstrained divisor)
grep -rn '<\-\-.*/.*;' --include='*.circom'
# Check for IsZero or non-zero proof in the same context

# Find LessThan without input constraint
grep -rn 'LessThan' --include='*.circom'

# Run Circomspect directly:
circomspect --level warning --verbose path/to/circuits/
```

### 5.4. Orchard-Equivalent Scenario (in Circom)

```circom
// VULNERABLE: Circom equivalent of the Orchard bug
template EcMul() {
    // Actual input point (constrained externally)
    signal input g_d_x;
    signal input g_d_y;

    // Scalar bits (constrained externally)
    signal input scalar_bits[254];

    // BUG: Assign the "working base" via single-arrow <--
    // This is equivalent to Halo2's assign_advice
    signal x_p <-- 0;   // NO CONSTRAINT — prover can set to anything
    signal y_p <-- 0;   // NO CONSTRAINT

    // Set in first iteration (witness only, no constraint):
    x_p <-- g_d_x;      // ASSIGNMENT only, no constraint linking x_p to g_d_x
    y_p <-- g_d_y;

    // ... double-and-add loop ...
    // Internal constraints enforce correctness relative to x_p, y_p.
    // But nothing constrains x_p == g_d_x.

    // FIX: Replace <-- with <== or add explicit ===:
    // x_p <== g_d_x;  ← creates the constraint automatically
    // y_p <== g_d_y;
    //
    // Or if <-- is needed (non-quadratic computation):
    // x_p <-- g_d_x;
    // x_p === g_d_x;  ← explicit constraint
}
```

---

## 6. Plonky3 [INCOMPLETE]

### 6.1 Architectural Differences from Plonky2

Plonky3 is a toolkit for building polynomial IOPs, not a monolithic proving system like Plonky2. Key differences:

- **No `CircuitBuilder`**: Plonky3 does not have Plonky2's `CircuitBuilder` with its large API surface of arithmetic/connect/lookup methods. Instead, it provides lower-level primitive crates (`air`, `lookup`, `fri`, `mmcs`, `challenger`) that the developer composes into a proving system.
- **`air` crate**: Defines the `Air` trait, which is the constraint specification layer. A circuit designer implements `Air` with an `eval` method that returns constraint polynomials. The constraint model is "Algebraic Intermediate Representation" (AIR), used in STARKs.
- **`lookup` crate**: Separate lookup argument infrastructure.
- **Multi-protocol**: Supports univariate STARK, multivariate STARK (GKR), and PLONK-style arithmetization. The constraint surface depends on which protocol is selected.

**What this means for audit methodology**: Plonky3 requires per-project audit, not per-framework. There is no single "add_virtual_target" equivalent because how witness values get assigned depends on the specific AIR implementation. The audit must read the `Air::eval` method for every chip (equivalent to Halo2's `configure`) and trace every witness value in the execution trace (equivalent to Halo2's `synthesize`).

**Under-constraint risk in Plonky3**: Same fundamental issue — a witness column in the trace that no AIR constraint polynomial references. Detection requires enumerating every column and checking its presence in every constraint degree. The absence of a high-level API actually makes under-constraint MORE likely (no `connect` guardrail) but also easier to detect mechanically (columns are numbered, constraints are polynomials — the intersection is well-defined).

**Information needed**:
- [ ] Full `air` crate API documentation
- [ ] Example `Air` implementations from production projects (Succinct SP1, Polygon zkEVM Valida)
- [ ] Whether Plonky3 provides any witness-assignment guardrails or if all constraint enforcement is manual
- [ ] Specific Plonky3 audit reports (if any public)

---

## 7. Cross-Framework Pattern Summary

### 7.1 The Universal Pattern

Every ZK proving system framework has the same fundamental dualism:

| Framework | "Assign Without Constraint" | "Assign AND Constrain" | "Constrain Existing (Equality)" |
|-----------|---------------------------|----------------------|-------------------------------|
| **Halo2** | `assign_advice` | *(not available — constraint is separate)* | `constrain_equal` (via `copy_advice`) |
| **arkworks** | `new_witness_variable` | *(not available)* | `enforce_constraint(a - b, 1, 0)` |
| **Bellman** | `alloc` | *(not available)* | `enforce(a - b, one, lc!())` |
| **Plonky2** | `add_virtual_target` | *(not available)* | `connect` |
| **Circom** | `<--` | `<==` | `===` |
| **Plonky3** | [INCOMPLETE] | [INCOMPLETE] | [INCOMPLETE] |

**Universal truth**: In ALL frameworks, witness allocation and constraint creation are **separate operations**. No framework's allocator automatically constrains what it allocates (except Circom's `<==`, which fuses the two). This is the root of all under-constraint bugs.

### 7.2 The Orchard Pattern Across Frameworks

The Orchard bug was a specific instance of class **CC-6: Loop internal-consistency without external binding**. The generalized pattern:

```
1. Allocate variable V (assign_advice, new_witness_variable, alloc, add_virtual_target, <--)
2. Use V in a loop/gadget that enforces consistency across iterations/steps
3. Never constrain V to the actual input value it should represent
```

This pattern is detectable in EVERY framework:
- **Halo2**: `assign_advice` in first loop iteration, no `constrain_equal` to input
- **arkworks**: `new_witness_variable` in first loop iteration, no `enforce_constraint(variable - input, 1, 0)`
- **Bellman**: `alloc` in first loop iteration, no `enforce(variable - input, CS::one(), lc!())`
- **Plonky2**: `add_virtual_target` in first loop iteration, no `connect(virtual, input)`
- **Circom**: `<--` in first iteration's signal assignment, no `===` to input signal

### 7.3 CC-1 Detection Equivalents

For each framework, what a static analysis tool should flag:

| Framework | CC-1 Signal | Tooling |
|-----------|------------|---------|
| **Halo2** | Any `assign_advice` call whose cell is not referenced by any gate polynomial OR any `constrain_equal` | Custom grep + gate enumeration tool |
| **arkworks** | Any `Variable` from `new_witness_variable` not appearing in any `enforce_constraint`'s `LinearCombination` | Trivially automatable — every `Variable` has a known set of consumers |
| **Bellman** | Any `Variable` from `alloc` not appearing in any `enforce` call | Same as arkworks |
| **Plonky2** | Any `Target` from `add_virtual_target` not appearing in any gate or `connect` call | Requires gate index enumeration; more complex than arkworks |
| **Circom** | Any signal assigned with `<--` without corresponding `===` | Circomspect already handles this |

### 7.4 Framework-Specific Footguns

| Framework | Footgun | Severity | Note |
|-----------|---------|----------|------|
| **Halo2** | `assign_advice` + loop internal consistency only | Critical (Orchard) | CC-6. The Orchard bug pattern. |
| **Halo2** | `assign_advice_from_instance` without gate constraint | Medium | Instance value is correct but decoupled from computation. |
| **arkworks** | `new_lc` of unconstrained variables | Medium | Alias that conceals unconstrained origin. |
| **arkworks** | No built-in `enforce_equal` — devs build it manually and may get it wrong | Low/Medium | Manual LC construction risks: wrong variable, wrong coefficient, constraint not actually equating the intended variables. |
| **Bellman** | `is_witness_generator()` mode silently skips constraints | Critical | Nova folding secondary circuit: if accidentally running in witness-gen mode, ALL constraints silently dropped. |
| **Bellman** | Same no-built-in-enforce_equal footgun as arkworks | Low/Medium | |
| **Plonky2** | `add_virtual_bool_target_unsafe` — bool with no range check | High | Prover assigns any field element; all downstream logic that assumes 0/1 is broken. |
| **Plonky2** | `generate_copy` vs `connect` — witness copy vs constraint | High | Developers may use `generate_copy` expecting it to constrain. |
| **Plonky2** | `add_lookup_from_index` without `add_all_lookups` | High | Deferred lookups never materialized → no lookup constraint. |
| **Plonky2** | Selector-gated custom gates: gate `eval` returns 0 when prover-chosen selector is 0 | Medium | CC-7 pattern. |
| **Circom** | `<--` without `===` | High | Circomspect catches this. |
| **Circom** | Division constraint `c * b === a` without `IsZero(b)` | High | `c` unconstrained when `b = 0`. |
| **Circom** | Template output signals unconstrained by parent | High | Circomspect flag #3. |

---

## 8. Integration into Angle 9 Methodology

### 8.1 Updated CHECK 1: Framework-Aware Cell Audit

The current CHECK 1 in `zk-circuit-soundness-agent.md` is Halo2-centric (references `assign_advice` vs `copy_advice`). The framework-agnostic version:

**CHECK 1 (Framework-Agnostic)**: For every witness cell/variable/target/signal in the circuit:

1. **Identify the framework's allocation API**:
   - Halo2: `assign_advice`, `assign_fixed`
   - arkworks: `new_witness_variable`, `new_input_variable`, `new_lc`
   - Bellman: `alloc`, `alloc_input`
   - Plonky2: `add_virtual_target`, `add_virtual_bool_target_unsafe`
   - Circom: `<--`

2. **Verify at least one constraint covers this cell**:
   - Halo2: gate polynomial references the column+offset, OR `constrain_equal` to another constrained cell
   - arkworks: `enforce_constraint` whose `LinearCombination` includes this `Variable`
   - Bellman: `enforce` whose `LinearCombination` includes this `Variable`
   - Plonky2: `add_gate` whose polynomial references this target, OR `connect` to another constrained target
   - Circom: `===` or `<==` that includes this signal

3. **If the constraint is loop-internal-consistency only**: Verify an additional constraint binds the first iteration to the external input (CC-6).

### 8.2 Detection Priority by Framework Signal

For project detection (Phase 1 circuit inventory), framework-specific grep patterns to run:

| Framework | Cargo.toml Signal | Circuit Files Signal | Primary grep target |
|-----------|-------------------|---------------------|-------------------|
| **Halo2** | `halo2_proofs`, `halo2_gadgets` | `circuits/`, `gadgets/`, `chips/` | `assign_advice\(` |
| **arkworks** | `ark-relations`, `ark-r1cs-std`, `ark-groth16` | `circuit/`, `constraints/`, `synthesis/` | `new_witness_variable\(` |
| **Bellman** | `bellman`, `bellpepper`, `bellpepper-core` | `circuit/`, `gadgets/` | `\.alloc\(` (with context for CS type) |
| **Plonky2** | `plonky2` | `circuit/`, `gadgets/`, `proofs/` | `add_virtual_target\(` |
| **Circom-in-Rust** | `circom-types`, `witness`, `circom-mpc` | `*.circom`, `witness/`, `circuits/` | `<\-\-` (in .circom files) |
| **Plonky3** | `plonky3`, `p3-*` | `air/`, `trace/`, `chips/`, `proofs/` | `Air` trait impls, `eval(` methods |

### 8.3 Framework-Specific PoC Construction

| Framework | Tier-1-mock Tool | Tier-1-e2e Tool |
|-----------|-----------------|----------------|
| **Halo2** | `MockProver::run(k, &circuit, &instances)` — check `verify()` result and `assert_satisfied()` | Full proof gen + verifier. Or `dev::CircuitExt::test_proof()` |
| **arkworks** | `cs.is_satisfied()` after synthesis with modified witness | `Groth16::<_, LibsnarkReduction>::prove()` + `verify()` |
| **Bellman** | `cs.is_satisfied()` (bellpepper `TestConstraintSystem`); `assert!(cs.verify(&inputs))` | `create_random_proof()` + `verify_proof()` |
| **Plonky2** | `builder.mock_build()` — internal constraint check without full proof | `builder.build::<C>()` + `prove()` + `verify()` |
| **Circom** | `circom --inspect` + witness calculator test. Or write a Rust test using `ark-circom` adapter. | `snarkjs groth16 prove` + `snarkjs groth16 verify` |
