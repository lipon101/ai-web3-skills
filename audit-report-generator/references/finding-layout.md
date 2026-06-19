# Finding Layout Template

Use this format for each vulnerability finding in your audit report.

## Format

```markdown
### [S-#] TITLE (Root + Impact)
**Description**

[Detailed description of the vulnerability, including technical context and affected code]

**Impact**

[Explain the consequences if this vulnerability is exploited]

**Proof of Concepts**

[Code snippets, test cases, or step-by-step reproduction instructions]

**Recommended mitigation**

[Specific recommendations to fix the vulnerability]
```

## Severity Prefixes

| Prefix | Severity |
|--------|----------|
| C-#    | Critical |
| H-#    | High     |
| M-#    | Medium   |
| L-#    | Low      |
| I-#    | Informational |
| G-#    | Gas Optimization |

## Example

```markdown
### [M-1] Unchecked return value in token transfer allows silent failures

**Description**

The `withdraw()` function in `Vault.sol:L142` calls `token.transfer()` without checking the return value. Some ERC20 tokens (like USDT) return `false` on failure instead of reverting.

**Impact**

Users may believe their withdrawal succeeded when tokens were not actually transferred, leading to accounting discrepancies and potential loss of funds.

**Proof of Concepts**

```solidity
function testUncheckedTransfer() public {
    // Setup: use a token that returns false on failure
    MockFailingToken token = new MockFailingToken();
    vault.withdraw(100);
    // Balance unchanged but no revert
    assertEq(token.balanceOf(user), 0);
}
```

**Recommended mitigation**

Use OpenZeppelin's `SafeERC20` library:

```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;

// Replace: token.transfer(to, amount);
// With:
token.safeTransfer(to, amount);
```
```
