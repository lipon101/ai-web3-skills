```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// ILLUSTRATIVE EXAMPLE

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IExampleRewarder {
    function lastUpdateBlock() external view returns (uint256);
    function periodInBlockFinish() external view returns (uint256);
    function rewardToken() external view returns (address);
    function MINIMUM_RECOVER_DURATION() external view returns (uint256);
    function recover(address token, address to) external;
}

interface IExampleAccessController {
    function grantRole(bytes32 role, address account) external;
}

contract Example_FreezeHistorical is Test {
    address constant ACCESS_CONTROLLER = address(0x1001);
    address constant ACCESS_CONTROLLER_OWNER = address(0x1002);
    address constant REWARD_TOKEN = address(0x1003);
    address constant PROTOCOL_REWARDER = address(0x1004);

    bytes32 constant TOKEN_RECOVERY_MANAGER_ROLE = keccak256("TOKEN_RECOVERY_MANAGER");

    uint256 constant BLOCK_WITH_FROZEN_REWARDER = 0;

    IExampleRewarder rewarder;
    address recoveryManager;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), BLOCK_WITH_FROZEN_REWARDER);

        rewarder = IExampleRewarder(PROTOCOL_REWARDER);
        recoveryManager = makeAddr("recoveryManager");

        vm.prank(ACCESS_CONTROLLER_OWNER);
        IExampleAccessController(ACCESS_CONTROLLER).grantRole(
            TOKEN_RECOVERY_MANAGER_ROLE,
            recoveryManager
        );
    }

    function test_FreezeHistorical_BlocksVsSecondsUnitMismatch() public {
        uint256 minRecoverDuration = rewarder.MINIMUM_RECOVER_DURATION();
        uint256 lastUpdate = rewarder.lastUpdateBlock();
        uint256 periodFinish = rewarder.periodInBlockFinish();
        uint256 currentBlock = block.number;
        uint256 rewardBalance = IERC20(REWARD_TOKEN).balanceOf(PROTOCOL_REWARDER);

        assertGt(currentBlock, periodFinish);
        assertEq(lastUpdate, periodFinish);
        assertEq(minRecoverDuration, 31_536_000);

        uint256 unlockBlock = lastUpdate + minRecoverDuration;
        uint256 blocksUntilUnlock = unlockBlock - currentBlock;
        uint256 effectiveLockYears = (blocksUntilUnlock * 12) / 365 days;

        console2.log("Rewarder:", PROTOCOL_REWARDER);
        console2.log("Reward token stranded in rewarder:", rewardBalance);
        console2.log("Reward period ended at block:", periodFinish);
        console2.log("lastUpdateBlock (frozen):", lastUpdate);
        console2.log("Recovery unlock at block:", unlockBlock);
        console2.log("Blocks until unlock:", blocksUntilUnlock);
        console2.log("Effective lock in years:", effectiveLockYears);

        assertTrue(effectiveLockYears >= 10);

        vm.prank(recoveryManager);
        vm.expectRevert(abi.encodeWithSignature("RecoverDurationPending()"));
        rewarder.recover(REWARD_TOKEN, recoveryManager);

        uint256 oneYearInBlocks = 365 days / 12;
        vm.roll(currentBlock + oneYearInBlocks);

        vm.prank(recoveryManager);
        vm.expectRevert(abi.encodeWithSignature("RecoverDurationPending()"));
        rewarder.recover(REWARD_TOKEN, recoveryManager);

        vm.roll(unlockBlock + 1);

        uint256 balBefore = IERC20(REWARD_TOKEN).balanceOf(recoveryManager);
        vm.prank(recoveryManager);
        rewarder.recover(REWARD_TOKEN, recoveryManager);
        uint256 recovered = IERC20(REWARD_TOKEN).balanceOf(recoveryManager) - balBefore;

        assertEq(recovered, rewardBalance);
        console2.log("Recovered after 12 years:", recovered);
    }
}
```